#include "sensorcoordinator.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QSettings>
#include <QUrl>
#include <QDebug>
#include <QSysInfo>
#include <QPair>
#include <QtMath>
#include <algorithm>

#include "appsettings.h"

namespace {

const char kClientName[] = "Helmsman";
const int kPeriodicMs = 15 * 60 * 1000;
const int kConfigRefreshMs = 20 * 60 * 1000;
const int kUpdateDebounceMs = 750;
// HA device_tracker consider_home defaults to 180s. Keep the internal-home
// webhook fresher than that so overnight Wi‑Fi stays "home".
const int kHomeHeartbeatMs = 120 * 1000;
const double kHomeAccuracyFallbackMeters = 100.0;
// Gap between the first webhook calls after start. Issuing config, sensor
// registration, and the first state update together stalled the UI thread on
// slow external endpoints.
const int kStartupStepMs = 500;
const double kAccuracyImproveMeters = 15.0;

const int kLocationPresetBatterySaver = 0;
const int kLocationPresetBalanced = 1;
const int kLocationPresetAccurate = 2;
const int kLocationStaleMinutesDefault = 15;
const int kLocationStaleMinutesMin = 5;
const int kLocationStaleMinutesMax = 60;

int clampLocationStaleMinutes(int minutes)
{
    return qBound(kLocationStaleMinutesMin, minutes, kLocationStaleMinutesMax);
}

int minimumLocationIntervalMs(int preset)
{
    if (preset == kLocationPresetBatterySaver)
        return 15 * 60 * 1000;
    if (preset == kLocationPresetAccurate)
        return 15 * 1000;
    return 60 * 1000;
}

double minimumLocationMoveMeters(int preset)
{
    if (preset == kLocationPresetBatterySaver)
        return 250.0;
    if (preset == kLocationPresetAccurate)
        return 10.0;
    return 25.0;
}

double haversineMeters(double lat1, double lon1, double lat2, double lon2)
{
    const double r = 6371000.0;
    const double p1 = qDegreesToRadians(lat1);
    const double p2 = qDegreesToRadians(lat2);
    const double dp = qDegreesToRadians(lat2 - lat1);
    const double dl = qDegreesToRadians(lon2 - lon1);
    const double a = qSin(dp / 2) * qSin(dp / 2)
            + qCos(p1) * qCos(p2) * qSin(dl / 2) * qSin(dl / 2);
    return 2 * r * qAtan2(qSqrt(a), qSqrt(1 - a));
}

QString locationNameForZone(const QString &entityId, const QString &friendlyName)
{
    if (entityId == QLatin1String("zone.home"))
        return QStringLiteral("home");
    if (!friendlyName.isEmpty())
        return friendlyName;
    const int dot = entityId.indexOf(QLatin1Char('.'));
    return dot >= 0 ? entityId.mid(dot + 1) : entityId;
}

// HA update_location location_name expects home / not_home / the zone entity
// slug (zone.work → "work"), matching the Android companion.
QString webhookLocationNameForEntity(const QString &entityId)
{
    if (entityId.isEmpty() || entityId == QLatin1String("zone.home"))
        return QStringLiteral("home");
    const int dot = entityId.indexOf(QLatin1Char('.'));
    return dot >= 0 ? entityId.mid(dot + 1) : entityId;
}

// Parse "2026.6.0" / "2026.6.0b0" style versions. Missing parts count as 0.
bool haVersionAtLeast(const QString &version, int major, int minor, int patch)
{
    if (version.isEmpty())
        return false;
    const QStringList parts = version.split(QLatin1Char('.'));
    int nums[3] = { 0, 0, 0 };
    for (int i = 0; i < 3 && i < parts.size(); ++i) {
        const QString part = parts.at(i);
        int end = 0;
        while (end < part.size() && part.at(end).isDigit())
            ++end;
        if (end > 0)
            nums[i] = part.left(end).toInt();
    }
    if (nums[0] != major)
        return nums[0] > major;
    if (nums[1] != minor)
        return nums[1] > minor;
    return nums[2] >= patch;
}

bool zoneFenceFromState(const QVariantMap &state, HassZoneFence *out)
{
    const QString entityId = state.value(QStringLiteral("entity_id")).toString();
    if (!entityId.startsWith(QLatin1String("zone.")))
        return false;
    const QVariantMap attrs = state.value(QStringLiteral("attributes")).toMap();
    const QVariant latValue = attrs.contains(QStringLiteral("latitude"))
            ? attrs.value(QStringLiteral("latitude"))
            : state.value(QStringLiteral("latitude"));
    const QVariant lonValue = attrs.contains(QStringLiteral("longitude"))
            ? attrs.value(QStringLiteral("longitude"))
            : state.value(QStringLiteral("longitude"));
    if (!latValue.isValid() || !lonValue.isValid())
        return false;
    const double lat = latValue.toDouble();
    const double lon = lonValue.toDouble();
    if (!qIsFinite(lat) || !qIsFinite(lon)
            || (qFuzzyIsNull(lat) && qFuzzyIsNull(lon)))
        return false;
    const QVariant radiusValue = attrs.contains(QStringLiteral("radius"))
            ? attrs.value(QStringLiteral("radius"))
            : state.value(QStringLiteral("radius"));
    const QString friendly = attrs.value(QStringLiteral("friendly_name")).toString();
    const QString name = state.value(QStringLiteral("name")).toString();
    out->entityId = entityId;
    out->locationName = locationNameForZone(entityId,
                                            !friendly.isEmpty() ? friendly : name);
    out->icon = attrs.value(QStringLiteral("icon")).toString();
    if (out->icon.isEmpty())
        out->icon = state.value(QStringLiteral("icon")).toString();
    out->latitude = lat;
    out->longitude = lon;
    out->radius = radiusValue.isValid() ? radiusValue.toDouble() : -1;
    out->passive = attrs.value(QStringLiteral("passive")).toBool()
            || state.value(QStringLiteral("passive")).toBool();
    return true;
}

bool zoneIdLess(const HassZoneFence &a, const HassZoneFence &b)
{
    return a.entityId < b.entityId;
}

bool zoneListsEqual(const QList<HassZoneFence> &a,
                    const QList<HassZoneFence> &b)
{
    if (a.size() != b.size())
        return false;
    for (int i = 0; i < a.size(); ++i) {
        if (a.at(i).entityId != b.at(i).entityId
                || a.at(i).locationName != b.at(i).locationName
                || a.at(i).icon != b.at(i).icon
                || a.at(i).passive != b.at(i).passive
                || !qFuzzyCompare(a.at(i).latitude + 1.0, b.at(i).latitude + 1.0)
                || !qFuzzyCompare(a.at(i).longitude + 1.0, b.at(i).longitude + 1.0)
                || !qFuzzyCompare(a.at(i).radius + 1.0, b.at(i).radius + 1.0))
            return false;
    }
    return true;
}

void insertSensorState(QJsonObject &obj, const QVariant &state)
{
    if (!state.isValid() || state.isNull())
        obj.insert(QStringLiteral("state"), QJsonValue::Null);
    else if (state.type() == QVariant::Bool)
        obj.insert(QStringLiteral("state"), state.toBool());
    else if (state.type() == QVariant::Int || state.type() == QVariant::LongLong)
        obj.insert(QStringLiteral("state"), state.toLongLong());
    else if (state.type() == QVariant::Double)
        obj.insert(QStringLiteral("state"), state.toDouble());
    else
        obj.insert(QStringLiteral("state"), state.toString());
}

} // namespace

SensorCoordinator::SensorCoordinator(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_ignoreSslErrors(false)
    , m_active(false)
    , m_locationEnabled(true)
    , m_locationDisabledInHa(false)
    , m_locationPreset(kLocationPresetBalanced)
    , m_locationStaleMinutes(kLocationStaleMinutesDefault)
    , m_homeOnInternal(true)
    , m_usingInternalUrl(false)
    , m_started(false)
    , m_registrationInFlight(false)
    , m_startupStep(0)
    , m_batteryLevel(-1)
    , m_haveBattery(false)
    , m_haveWifi(false)
    , m_haveLocation(false)
    , m_haveHomeCoordinates(false)
    , m_zonesFetchPending(false)
    , m_haveMotionExtras(false)
    , m_lastLocationPostOk(true)
    , m_lastLat(0)
    , m_lastLon(0)
    , m_lastAccuracy(-1)
    , m_lastSpeedMps(-1)
    , m_lastAltitudeM(-1)
    , m_lastCourseDeg(-1)
    , m_lastVerticalAccuracyM(-1)
    , m_homeLat(0)
    , m_homeLon(0)
    , m_homeRadius(-1)
{
    m_defs = builtInSensors();
    for (const SensorDef &def : m_defs) {
        SensorRuntime rt;
        rt.registered = false;
        rt.disabled = def.defaultDisabled;
        rt.locallyEnabled = true;
        rt.dirty = false;
        m_runtime.insert(def.uniqueId, rt);
    }

    loadPersistedState();

    m_periodicTimer.setInterval(kPeriodicMs);
    connect(&m_periodicTimer, SIGNAL(timeout()), this, SLOT(onPeriodicTimeout()));

    m_configTimer.setInterval(kConfigRefreshMs);
    connect(&m_configTimer, SIGNAL(timeout()), this, SLOT(onConfigRefreshTimeout()));

    m_updateDebounce.setSingleShot(true);
    m_updateDebounce.setInterval(kUpdateDebounceMs);
    connect(&m_updateDebounce, SIGNAL(timeout()), this, SLOT(onUpdateDebounceTimeout()));

    m_startupTimer.setInterval(kStartupStepMs);
    connect(&m_startupTimer, SIGNAL(timeout()), this, SLOT(onStartupStepTimeout()));

    m_homeHeartbeatTimer.setInterval(kHomeHeartbeatMs);
    connect(&m_homeHeartbeatTimer, SIGNAL(timeout()), this, SLOT(onHomeHeartbeatTimeout()));

    connect(m_nam, SIGNAL(sslErrors(QNetworkReply*,QList<QSslError>)),
            this, SLOT(onSslErrors(QNetworkReply*,QList<QSslError>)));

    rebuildStatusList();
}

QList<SensorCoordinator::SensorDef> SensorCoordinator::builtInSensors()
{
    QList<SensorDef> list;

    SensorDef batteryLevel;
    batteryLevel.uniqueId = QStringLiteral("battery_level");
    batteryLevel.name = QStringLiteral("Battery Level");
    batteryLevel.type = QStringLiteral("sensor");
    batteryLevel.deviceClass = QStringLiteral("battery");
    batteryLevel.unit = QStringLiteral("%");
    batteryLevel.stateClass = QStringLiteral("measurement");
    batteryLevel.icon = QStringLiteral("mdi:battery");
    batteryLevel.entityCategory = QStringLiteral("diagnostic");
    batteryLevel.defaultDisabled = false;
    list.append(batteryLevel);

    SensorDef batteryState;
    batteryState.uniqueId = QStringLiteral("battery_state");
    batteryState.name = QStringLiteral("Battery State");
    batteryState.type = QStringLiteral("sensor");
    batteryState.icon = QStringLiteral("mdi:battery");
    batteryState.entityCategory = QStringLiteral("diagnostic");
    batteryState.defaultDisabled = false;
    list.append(batteryState);

    SensorDef chargerType;
    chargerType.uniqueId = QStringLiteral("charger_type");
    chargerType.name = QStringLiteral("Charger Type");
    chargerType.type = QStringLiteral("sensor");
    chargerType.icon = QStringLiteral("mdi:power-plug");
    chargerType.entityCategory = QStringLiteral("diagnostic");
    chargerType.defaultDisabled = false;
    list.append(chargerType);

    SensorDef wifi;
    wifi.uniqueId = QStringLiteral("wifi_connection");
    wifi.name = QStringLiteral("Wi-Fi Connection");
    wifi.type = QStringLiteral("sensor");
    wifi.icon = QStringLiteral("mdi:wifi");
    wifi.entityCategory = QStringLiteral("diagnostic");
    wifi.defaultDisabled = false;
    list.append(wifi);

    SensorDef osVersion;
    osVersion.uniqueId = QStringLiteral("os_version");
    osVersion.name = QStringLiteral("OS Version");
    osVersion.type = QStringLiteral("sensor");
    osVersion.icon = QStringLiteral("mdi:sail-boat");
    osVersion.entityCategory = QStringLiteral("diagnostic");
    osVersion.defaultDisabled = false;
    list.append(osVersion);

    return list;
}

QVariantList SensorCoordinator::sensorStatuses() const { return m_statusList; }
bool SensorCoordinator::active() const { return m_active; }
bool SensorCoordinator::locationReporting() const
{
    return m_locationEnabled && !m_locationDisabledInHa;
}
bool SensorCoordinator::locationEnabled() const { return m_locationEnabled; }
int SensorCoordinator::locationPreset() const { return m_locationPreset; }
int SensorCoordinator::locationStaleMinutes() const { return m_locationStaleMinutes; }
bool SensorCoordinator::homeOnInternal() const { return m_homeOnInternal; }
QString SensorCoordinator::lastError() const { return m_lastError; }
QString SensorCoordinator::lastLocationText() const { return m_lastLocationText; }
QString SensorCoordinator::locationZone() const { return m_locationZone; }

QString SensorCoordinator::locationZoneIcon() const
{
    if (m_locationZone.isEmpty())
        return QStringLiteral("mdi:map-marker-question");
    if (m_locationZone == QLatin1String("home")) {
        for (int i = 0; i < m_zones.size(); ++i) {
            if (m_zones.at(i).entityId == QLatin1String("zone.home")
                    && !m_zones.at(i).icon.isEmpty())
                return m_zones.at(i).icon;
        }
        return QStringLiteral("mdi:home");
    }
    if (m_locationZone == QLatin1String("not_home"))
        return QStringLiteral("mdi:home-export-outline");
    for (int i = 0; i < m_zones.size(); ++i) {
        const HassZoneFence &zone = m_zones.at(i);
        if (zone.locationName.compare(m_locationZone, Qt::CaseInsensitive) != 0)
            continue;
        if (!zone.icon.isEmpty())
            return zone.icon;
        break;
    }
    return QStringLiteral("mdi:map-marker-radius");
}

double SensorCoordinator::zoneExpandMeters(double accuracyMeters) const
{
    if (accuracyMeters <= 0)
        return 0;
    // Battery saver: strict radius — no extra GPS, no soft boundary that
    // would flip zones on fat cell/Wi‑Fi circles.
    if (m_locationPreset == kLocationPresetBatterySaver)
        return 0;
    // Balanced: modest Android-style expand, capped so noisy MLS fixes
    // cannot swallow neighbouring zones.
    if (m_locationPreset == kLocationPresetBalanced)
        return qMin(accuracyMeters, 75.0);
    // Accurate: full containsWithAccuracy (radius + horizontal accuracy).
    return accuracyMeters;
}

bool SensorCoordinator::zoneContains(const HassZoneFence &zone, double latitude,
                                     double longitude, double accuracyMeters) const
{
    const double radius = zone.radius > 0 ? zone.radius : 100.0;
    const double dist = haversineMeters(latitude, longitude,
                                        zone.latitude, zone.longitude);
    return dist <= radius + zoneExpandMeters(accuracyMeters);
}

const HassZoneFence *SensorCoordinator::bestActiveZoneAt(double latitude,
                                                         double longitude,
                                                         double accuracyMeters) const
{
    if (!qIsFinite(latitude) || !qIsFinite(longitude))
        return nullptr;

    const HassZoneFence *best = nullptr;
    double bestRadius = 0;
    for (int i = 0; i < m_zones.size(); ++i) {
        const HassZoneFence &zone = m_zones.at(i);
        if (zone.passive)
            continue;
        if (!zoneContains(zone, latitude, longitude, accuracyMeters))
            continue;
        const double radius = zone.radius > 0 ? zone.radius : 100.0;
        if (!best || radius < bestRadius) {
            best = &zone;
            bestRadius = radius;
        }
    }
    return best;
}

QString SensorCoordinator::computeLocationZoneAt(double latitude, double longitude,
                                                 double accuracyMeters) const
{
    if (atHomeOnInternal())
        return QStringLiteral("home");
    if (!qIsFinite(latitude) || !qIsFinite(longitude))
        return QString();

    if (const HassZoneFence *best = bestActiveZoneAt(latitude, longitude, accuracyMeters))
        return best->locationName;
    return QStringLiteral("not_home");
}

QString SensorCoordinator::webhookLocationNameAt(double latitude, double longitude,
                                                 double accuracyMeters) const
{
    if (atHomeOnInternal())
        return QStringLiteral("home");
    if (!qIsFinite(latitude) || !qIsFinite(longitude))
        return QString();

    if (const HassZoneFence *best = bestActiveZoneAt(latitude, longitude, accuracyMeters))
        return webhookLocationNameForEntity(best->entityId);
    return QStringLiteral("not_home");
}

bool SensorCoordinator::supportsInZones() const
{
    // Core 2026.6.0 added in_zones to the update_location schema. Older
    // schemas reject the key (PREVENT_EXTRA) but still return HTTP 200, so
    // the app thought the post succeeded while HA silently dropped it —
    // leaving history stuck on home/not_home while the cover showed zones.
    return haVersionAtLeast(m_haVersion, 2026, 6, 0);
}

QStringList SensorCoordinator::computeInZonesAt(double latitude, double longitude,
                                                double accuracyMeters) const
{
    QList<QPair<double, QString> > hits;
    for (int i = 0; i < m_zones.size(); ++i) {
        const HassZoneFence &zone = m_zones.at(i);
        if (!zoneContains(zone, latitude, longitude, accuracyMeters))
            continue;
        const double radius = zone.radius > 0 ? zone.radius : 100.0;
        hits.append(qMakePair(radius, zone.entityId));
    }
    std::sort(hits.begin(), hits.end());
    QStringList ids;
    ids.reserve(hits.size());
    for (int i = 0; i < hits.size(); ++i)
        ids.append(hits.at(i).second);
    return ids;
}

QString SensorCoordinator::computeLocationZone() const
{
    if (!m_haveLocation)
        return atHomeOnInternal() ? QStringLiteral("home") : QString();
    return computeLocationZoneAt(m_lastLat, m_lastLon, m_lastAccuracy);
}

int SensorCoordinator::duplicateSuppressMs() const
{
    if (m_locationPreset == kLocationPresetBatterySaver)
        return 30 * 60 * 1000;
    if (m_locationPreset == kLocationPresetAccurate)
        return 5 * 60 * 1000;
    return 15 * 60 * 1000;
}

bool SensorCoordinator::shouldConfirmZoneTransition(double accuracyMeters) const
{
    if (m_locationPreset == kLocationPresetBatterySaver)
        return false;
    if (accuracyMeters <= 0)
        return true;
    if (m_locationPreset == kLocationPresetAccurate)
        return accuracyMeters > 50.0;
    return accuracyMeters > 100.0;
}

void SensorCoordinator::maybeRequestTransitionSeek(double accuracyMeters)
{
    if (!shouldConfirmZoneTransition(accuracyMeters))
        return;
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const int cooldownMs = m_locationPreset == kLocationPresetAccurate
            ? 2 * 60 * 1000
            : 10 * 60 * 1000;
    if (m_lastTransitionSeekAt.isValid()
            && m_lastTransitionSeekAt.msecsTo(now) < cooldownMs)
        return;
    m_lastTransitionSeekAt = now;
    qWarning() << "Helmsman location: confirmatory seek after zone change"
               << "acc=" << accuracyMeters << "preset=" << m_locationPreset;
    emit locationRefreshRequested();
}

void SensorCoordinator::refreshLocationZone()
{
    const QString next = computeLocationZone();
    if (next == m_locationZone)
        return;
    m_locationZone = next;
    emit locationZoneChanged();
}

void SensorCoordinator::loadPersistedState()
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("sensors"));
    const QStringList registered = settings.value(QStringLiteral("registered")).toStringList();
    for (const QString &id : registered) {
        if (m_runtime.contains(id))
            m_runtime[id].registered = true;
    }
    const QStringList locallyDisabled =
            settings.value(QStringLiteral("locallyDisabled")).toStringList();
    for (const QString &id : locallyDisabled) {
        if (m_runtime.contains(id))
            m_runtime[id].locallyEnabled = false;
    }
    if (settings.contains(QStringLiteral("locationReporting")))
        m_locationEnabled = settings.value(QStringLiteral("locationReporting")).toBool();
    if (settings.contains(QStringLiteral("locationPreset")))
        m_locationPreset = qBound(kLocationPresetBatterySaver,
                                  settings.value(QStringLiteral("locationPreset")).toInt(),
                                  kLocationPresetAccurate);
    if (settings.contains(QStringLiteral("locationStaleMinutes")))
        m_locationStaleMinutes = clampLocationStaleMinutes(
                settings.value(QStringLiteral("locationStaleMinutes")).toInt());
    if (settings.contains(QStringLiteral("homeOnInternal")))
        m_homeOnInternal = settings.value(QStringLiteral("homeOnInternal")).toBool();
    if (settings.contains(QStringLiteral("homeLatitude"))
            && settings.contains(QStringLiteral("homeLongitude"))) {
        const double lat = settings.value(QStringLiteral("homeLatitude")).toDouble();
        const double lon = settings.value(QStringLiteral("homeLongitude")).toDouble();
        const double radius = settings.value(QStringLiteral("homeRadius"), -1).toDouble();
        if (qIsFinite(lat) && qIsFinite(lon)
                && !(qFuzzyIsNull(lat) && qFuzzyIsNull(lon))) {
            m_homeLat = lat;
            m_homeLon = lon;
            m_homeRadius = radius;
            m_haveHomeCoordinates = true;
        }
    }
    settings.endGroup();
    loadPersistedZones();
}

void SensorCoordinator::persistState() const
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("sensors"));
    settings.setValue(QStringLiteral("registered"), registeredIds());
    QStringList locallyDisabled;
    for (auto it = m_runtime.constBegin(); it != m_runtime.constEnd(); ++it) {
        if (!it.value().locallyEnabled)
            locallyDisabled.append(it.key());
    }
    locallyDisabled.sort();
    settings.setValue(QStringLiteral("locallyDisabled"), locallyDisabled);
    settings.setValue(QStringLiteral("locationReporting"), m_locationEnabled);
    settings.setValue(QStringLiteral("locationPreset"), m_locationPreset);
    settings.setValue(QStringLiteral("locationStaleMinutes"), m_locationStaleMinutes);
    settings.setValue(QStringLiteral("homeOnInternal"), m_homeOnInternal);
    if (m_haveHomeCoordinates) {
        settings.setValue(QStringLiteral("homeLatitude"), m_homeLat);
        settings.setValue(QStringLiteral("homeLongitude"), m_homeLon);
        settings.setValue(QStringLiteral("homeRadius"), m_homeRadius);
    }
    settings.endGroup();
    persistZones();
}

QStringList SensorCoordinator::registeredIds() const
{
    QStringList ids;
    for (auto it = m_runtime.constBegin(); it != m_runtime.constEnd(); ++it) {
        if (it.value().registered)
            ids.append(it.key());
    }
    ids.sort();
    return ids;
}

void SensorCoordinator::setRegisteredIds(const QStringList &ids)
{
    Q_UNUSED(ids);
}

void SensorCoordinator::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

void SensorCoordinator::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void SensorCoordinator::updateLocationReporting()
{
    emit locationReportingChanged();
    rebuildStatusList();
    updateHomeHeartbeat();
}

void SensorCoordinator::setLocationEnabled(bool enabled)
{
    if (m_locationEnabled == enabled)
        return;
    m_locationEnabled = enabled;
    persistState();
    emit locationEnabledChanged();
    updateLocationReporting();
    if (locationReporting() && m_started) {
        fetchZones();
        postLocationUpdate(true);
    }
}

void SensorCoordinator::setLocationPreset(int preset)
{
    preset = qBound(kLocationPresetBatterySaver, preset, kLocationPresetAccurate);
    if (m_locationPreset == preset)
        return;
    m_locationPreset = preset;
    persistState();
    emit locationPresetChanged();
    m_lastLocationSent = QDateTime();
}

void SensorCoordinator::setLocationStaleMinutes(int minutes)
{
    minutes = clampLocationStaleMinutes(minutes);
    if (m_locationStaleMinutes == minutes)
        return;
    m_locationStaleMinutes = minutes;
    persistState();
    emit locationStaleMinutesChanged();
}

void SensorCoordinator::configure(const QString &webhookId,
                                  const QString &cloudhookUrl,
                                  const QString &remoteUiUrl,
                                  const QString &baseUrl,
                                  const QString &accessToken,
                                  bool ignoreSslErrors,
                                  const QString &haVersion)
{
    const bool changed = m_webhookId != webhookId
            || m_cloudhookUrl != cloudhookUrl
            || m_remoteUiUrl != remoteUiUrl
            || m_baseUrl != baseUrl
            || m_accessToken != accessToken
            || m_ignoreSslErrors != ignoreSslErrors;

    m_webhookId = webhookId;
    m_cloudhookUrl = cloudhookUrl;
    m_remoteUiUrl = remoteUiUrl;
    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_ignoreSslErrors = ignoreSslErrors;
    if (!haVersion.isEmpty())
        m_haVersion = haVersion;

    if (changed && m_started && !m_webhookId.isEmpty()) {
        // Endpoint switched (internal<->external). Re-sync through the same
        // paced steps as start(): firing these inline hit the new, possibly
        // slow host while the push channel and dashboard were also reloading.
        m_startupStep = 0;
        m_startupTimer.start();
        fetchZones();
    }
}

void SensorCoordinator::setHaVersion(const QString &haVersion)
{
    if (haVersion.isEmpty() || m_haVersion == haVersion)
        return;
    m_haVersion = haVersion;
}

void SensorCoordinator::start()
{
    if (m_webhookId.isEmpty() || m_baseUrl.isEmpty()) {
        qWarning() << "Helmsman sensors: cannot start without webhook/baseUrl";
        return;
    }
    m_started = true;
    setActive(true);
    setLastError(QString());
    m_periodicTimer.start();
    m_configTimer.start();
    updateHomeHeartbeat();
    ensureOsVersionSensor();
    m_startupStep = 0;
    m_startupTimer.start();
    fetchZones();
    qWarning() << "Helmsman sensors: started";
}

void SensorCoordinator::onStartupStepTimeout()
{
    if (!m_started) {
        m_startupTimer.stop();
        return;
    }

    switch (m_startupStep++) {
    case 0:
        refreshConfig();
        break;
    case 1:
        ensureRegistrations();
        break;
    case 2:
        scheduleSensorUpdate();
        claimHomeOnInternal();
        break;
    default:
        m_startupTimer.stop();
        break;
    }
}

void SensorCoordinator::stop()
{
    m_started = false;
    m_periodicTimer.stop();
    m_configTimer.stop();
    m_updateDebounce.stop();
    m_startupTimer.stop();
    m_homeHeartbeatTimer.stop();
    m_registerQueue.clear();
    m_registrationInFlight = false;
    setActive(false);
}

void SensorCoordinator::onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    if (m_ignoreSslErrors && reply)
        reply->ignoreSslErrors();
}

QUrl SensorCoordinator::webhookUrl(int attempt) const
{
    // Prefer cloudhook, then remote UI, then instance URL (HA docs).
    QStringList candidates;
    if (!m_cloudhookUrl.isEmpty())
        candidates.append(m_cloudhookUrl);
    if (!m_remoteUiUrl.isEmpty()) {
        QString base = m_remoteUiUrl;
        while (base.endsWith(QLatin1Char('/')))
            base.chop(1);
        candidates.append(base + QStringLiteral("/api/webhook/") + m_webhookId);
    }
    if (!m_baseUrl.isEmpty()) {
        QString base = m_baseUrl;
        while (base.endsWith(QLatin1Char('/')))
            base.chop(1);
        candidates.append(base + QStringLiteral("/api/webhook/") + m_webhookId);
    }
    if (attempt < 0 || attempt >= candidates.size())
        return QUrl();
    return QUrl(candidates.at(attempt));
}

void SensorCoordinator::postWebhook(WebhookKind kind, const QJsonObject &body, int urlAttempt)
{
    if (m_webhookId.isEmpty())
        return;

    const QUrl url = webhookUrl(urlAttempt);
    if (!url.isValid()) {
        setLastError(QStringLiteral("Invalid webhook URL"));
        return;
    }

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);

    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = m_nam->post(request, payload);
    reply->setProperty("webhookKind", static_cast<int>(kind));
    reply->setProperty("urlAttempt", urlAttempt);
    reply->setProperty("payload", payload);
    if (kind == WebhookRegisterSensor)
        reply->setProperty("uniqueId", body.value(QStringLiteral("data")).toObject()
                          .value(QStringLiteral("unique_id")).toString());
    connect(reply, SIGNAL(finished()), this, SLOT(onWebhookFinished()));
}

void SensorCoordinator::onWebhookFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    const WebhookKind kind = static_cast<WebhookKind>(reply->property("webhookKind").toInt());
    const int urlAttempt = reply->property("urlAttempt").toInt();
    const QByteArray payload = reply->property("payload").toByteArray();
    const QString uniqueId = reply->property("uniqueId").toString();
    const QByteArray data = reply->readAll();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError netError = reply->error();
    reply->deleteLater();

    if (kind == WebhookGetZones) {
        m_zonesFetchPending = false;
        if (status == 200)
            handleZones(data);
        return;
    }

    if (netError != QNetworkReply::NoError && status == 0) {
        // Try next URL fallback.
        if (urlAttempt < 2) {
            const QUrl next = webhookUrl(urlAttempt + 1);
            if (next.isValid()) {
                const QJsonDocument doc = QJsonDocument::fromJson(payload);
                if (doc.isObject()) {
                    postWebhook(kind, doc.object(), urlAttempt + 1);
                    return;
                }
            }
        }
        setLastError(QStringLiteral("Webhook unreachable"));
        if (kind == WebhookUpdateLocation)
            m_lastLocationPostOk = false;
        if (kind == WebhookRegisterSensor) {
            m_registrationInFlight = false;
            registerNextPending();
        }
        return;
    }

    if (status == 410) {
        setLastError(QStringLiteral("Mobile app integration deleted in Home Assistant"));
        stop();
        return;
    }

    if (kind == WebhookGetConfig) {
        if (status == 200)
            handleGetConfig(data);
        else
            setLastError(QStringLiteral("get_config failed (HTTP %1)").arg(status));
        return;
    }

    if (kind == WebhookRegisterSensor) {
        handleRegisterSensor(data, status, uniqueId);
        return;
    }

    if (kind == WebhookUpdateSensors) {
        if (status == 200)
            handleUpdateSensors(data);
        else
            setLastError(QStringLiteral("update_sensor_states failed (HTTP %1)").arg(status));
        return;
    }

    if (kind == WebhookUpdateLocation) {
        handleUpdateLocation(data, status);
        return;
    }
}

void SensorCoordinator::refreshConfig()
{
    if (m_webhookId.isEmpty())
        return;
    QJsonObject body;
    body.insert(QStringLiteral("type"), QStringLiteral("get_config"));
    // Empty data object required by some HA versions when unencrypted.
    body.insert(QStringLiteral("data"), QJsonObject());
    postWebhook(WebhookGetConfig, body);
}

void SensorCoordinator::handleGetConfig(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return;

    const QJsonObject root = doc.object();
    const QJsonObject entities = root.value(QStringLiteral("entities")).toObject();
    bool changed = false;

    for (auto it = entities.begin(); it != entities.end(); ++it) {
        const QString uniqueId = it.key();
        const bool disabled = it.value().toObject().value(QStringLiteral("disabled")).toBool();

        if (uniqueId == QLatin1String("location")
                || uniqueId.contains(QStringLiteral("device_tracker"))
                || uniqueId == m_webhookId) {
            if (m_locationDisabledInHa != disabled) {
                m_locationDisabledInHa = disabled;
                updateLocationReporting();
                changed = true;
            }
            continue;
        }

        if (!m_runtime.contains(uniqueId))
            continue;
        if (m_runtime[uniqueId].disabled != disabled) {
            m_runtime[uniqueId].disabled = disabled;
            changed = true;
        }
    }

    if (changed) {
        rebuildStatusList();
        scheduleSensorUpdate();
    }
}

void SensorCoordinator::ensureRegistrations()
{
    m_registerQueue.clear();
    for (const SensorDef &def : m_defs) {
        if (!m_runtime.value(def.uniqueId).registered)
            m_registerQueue.append(def.uniqueId);
    }
    registerNextPending();
}

void SensorCoordinator::registerNextPending()
{
    if (m_registrationInFlight || m_registerQueue.isEmpty() || !m_started)
        return;

    const QString uniqueId = m_registerQueue.takeFirst();
    const SensorDef def = defFor(uniqueId);
    if (def.uniqueId.isEmpty()) {
        registerNextPending();
        return;
    }

    SensorRuntime &rt = m_runtime[uniqueId];
    // Need a placeholder state for first registration.
    if (!rt.state.isValid() && uniqueId != QLatin1String("wifi_connection")) {
        if (def.type == QLatin1String("binary_sensor"))
            rt.state = false;
        else if (def.unit == QLatin1String("%"))
            rt.state = 0;
        else
            rt.state = QStringLiteral("unknown");
    }

    m_registrationInFlight = true;
    QJsonObject body;
    body.insert(QStringLiteral("type"), QStringLiteral("register_sensor"));
    body.insert(QStringLiteral("data"), buildRegisterPayload(def, rt));
    postWebhook(WebhookRegisterSensor, body);
}

QJsonObject SensorCoordinator::buildRegisterPayload(const SensorDef &def, const SensorRuntime &rt) const
{
    QJsonObject data;
    data.insert(QStringLiteral("unique_id"), def.uniqueId);
    data.insert(QStringLiteral("name"), def.name);
    data.insert(QStringLiteral("type"), def.type);
    data.insert(QStringLiteral("icon"), rt.icon.isEmpty() ? def.icon : rt.icon);
    data.insert(QStringLiteral("disabled"), rt.disabled);
    if (!def.deviceClass.isEmpty())
        data.insert(QStringLiteral("device_class"), def.deviceClass);
    if (!def.unit.isEmpty())
        data.insert(QStringLiteral("unit_of_measurement"), def.unit);
    if (!def.stateClass.isEmpty())
        data.insert(QStringLiteral("state_class"), def.stateClass);
    if (!def.entityCategory.isEmpty())
        data.insert(QStringLiteral("entity_category"), def.entityCategory);
    if (!rt.attributes.isEmpty())
        data.insert(QStringLiteral("attributes"), QJsonObject::fromVariantMap(rt.attributes));

    const QVariant &state = rt.state;
    insertSensorState(data, state);

    return data;
}

void SensorCoordinator::handleRegisterSensor(const QByteArray &data, int status, const QString &uniqueId)
{
    Q_UNUSED(data);
    m_registrationInFlight = false;

    if ((status == 200 || status == 201) && m_runtime.contains(uniqueId)) {
        m_runtime[uniqueId].registered = true;
        persistState();
        qWarning() << "Helmsman sensors: registered" << uniqueId;
        rebuildStatusList();
        scheduleSensorUpdate();
    } else {
        setLastError(QStringLiteral("register_sensor failed for %1 (HTTP %2)")
                     .arg(uniqueId).arg(status));
        // Still mark registered on conflict-ish responses so we do not loop forever;
        // a later update will report not_registered if needed.
        if (status == 200 || status == 201) {
            // handled above
        }
    }
    registerNextPending();
}

SensorCoordinator::SensorDef SensorCoordinator::defFor(const QString &uniqueId) const
{
    for (const SensorDef &def : m_defs) {
        if (def.uniqueId == uniqueId)
            return def;
    }
    return SensorDef();
}

bool SensorCoordinator::isSensorEnabled(const QString &uniqueId) const
{
    const SensorRuntime rt = m_runtime.value(uniqueId);
    return rt.registered && !rt.disabled && rt.locallyEnabled;
}

void SensorCoordinator::setSensorEnabled(const QString &uniqueId, bool enabled)
{
    if (!m_runtime.contains(uniqueId)
            || m_runtime[uniqueId].locallyEnabled == enabled)
        return;

    SensorRuntime &rt = m_runtime[uniqueId];
    rt.locallyEnabled = enabled;
    if (enabled) {
        rt.dirty = true;
        scheduleSensorUpdate();
    }
    persistState();
    rebuildStatusList();
}

QString SensorCoordinator::batteryIconFor(int level, bool charging)
{
    // Match Android companion: mdi:battery[-charging][-XX|-outline]
    const int percentage = qBound(0, 100, level);
    const int rounded = (percentage / 10) * 10;
    const QString base = charging
            ? QStringLiteral("mdi:battery-charging")
            : QStringLiteral("mdi:battery");
    if (percentage <= 9)
        return base + QStringLiteral("-outline");
    if (percentage >= 100)
        return base;
    return base + QLatin1Char('-') + QString::number(rounded);
}

void SensorCoordinator::updateBattery(int levelPercent, bool charging, const QString &state, const QString &chargerType)
{
    m_haveBattery = true;
    m_batteryLevel = qBound(0, 100, levelPercent);

    QString batteryState = state.trimmed().toLower();
    if (batteryState.isEmpty()) {
        if (m_batteryLevel >= 100 && charging)
            batteryState = QStringLiteral("full");
        else if (charging)
            batteryState = QStringLiteral("charging");
        else
            batteryState = QStringLiteral("discharging");
    }

    QString charger = chargerType.trimmed().toLower();
    // Jolla has no Qi by default; DCP/CDP/HVDCP are wired USB charging ports,
    // not wireless. Never report wireless.
    if (charger.contains(QStringLiteral("usb"))
            || charger == QLatin1String("sdp"))
        charger = QStringLiteral("usb");
    else if (charger.contains(QStringLiteral("dcp"))
             || charger.contains(QStringLiteral("cdp"))
             || charger.contains(QStringLiteral("hvdcp"))
             || charger.contains(QStringLiteral("ac"))
             || charger.contains(QStringLiteral("wall"))
             || charger.contains(QStringLiteral("mains"))
             || charger.contains(QStringLiteral("wireless")))
        charger = charging ? QStringLiteral("ac") : QStringLiteral("none");
    else if (charger.isEmpty() || charger == QLatin1String("unknown"))
        charger = charging ? QStringLiteral("ac") : QStringLiteral("none");
    else if (!charging)
        charger = QStringLiteral("none");
    else if (charger != QLatin1String("ac") && charger != QLatin1String("usb"))
        charger = QStringLiteral("ac");

    // Android treats charging/full as "is charging".
    const bool isCharging = (batteryState == QLatin1String("charging")
                             || batteryState == QLatin1String("full"));

    const QString levelIcon = batteryIconFor(m_batteryLevel, isCharging);

    QString stateIcon = QStringLiteral("mdi:battery-unknown");
    if (batteryState == QLatin1String("charging"))
        stateIcon = QStringLiteral("mdi:battery-plus");
    else if (batteryState == QLatin1String("discharging"))
        stateIcon = QStringLiteral("mdi:battery-minus");
    else if (batteryState == QLatin1String("full"))
        stateIcon = QStringLiteral("mdi:battery-charging");
    else if (batteryState == QLatin1String("not_charging"))
        stateIcon = QStringLiteral("mdi:battery");

    QString chargerIcon = QStringLiteral("mdi:battery");
    if (charger == QLatin1String("ac"))
        chargerIcon = QStringLiteral("mdi:power-plug");
    else if (charger == QLatin1String("usb"))
        chargerIcon = QStringLiteral("mdi:usb-port");
    else if (charger == QLatin1String("none"))
        chargerIcon = QStringLiteral("mdi:power-plug-off");

    auto setSensor = [this](const QString &id, const QVariant &state,
                            const QString &icon, const QVariantMap &attrs = QVariantMap()) {
        SensorRuntime &rt = m_runtime[id];
        if (rt.state != state || rt.icon != icon || rt.attributes != attrs) {
            rt.state = state;
            rt.icon = icon;
            rt.attributes = attrs;
            rt.dirty = true;
        }
    };

    // Android companion puts charging info on battery_level via icon; also expose
    // state/charger as attributes so one entity is enough for dashboards/automations.
    QVariantMap levelAttrs;
    levelAttrs.insert(QStringLiteral("battery_state"), batteryState);
    levelAttrs.insert(QStringLiteral("charger_type"), charger);
    levelAttrs.insert(QStringLiteral("is_charging"), isCharging);
    setSensor(QStringLiteral("battery_level"), m_batteryLevel, levelIcon, levelAttrs);

    QVariantMap stateAttrs;
    stateAttrs.insert(QStringLiteral("options"),
                      QStringList() << QStringLiteral("charging")
                                    << QStringLiteral("discharging")
                                    << QStringLiteral("full")
                                    << QStringLiteral("not_charging"));
    setSensor(QStringLiteral("battery_state"), batteryState, stateIcon, stateAttrs);

    QVariantMap chargerAttrs;
    chargerAttrs.insert(QStringLiteral("options"),
                        QStringList() << QStringLiteral("ac")
                                      << QStringLiteral("usb")
                                      << QStringLiteral("none"));
    setSensor(QStringLiteral("charger_type"), charger, chargerIcon, chargerAttrs);

    if (m_started)
        scheduleSensorUpdate();
    else
        rebuildStatusList();
}

void SensorCoordinator::updateWifi(const QString &ssid, bool connected)
{
    m_haveWifi = true;
    const bool on = connected && !ssid.isEmpty();
    const QVariant state = on ? QVariant(ssid) : QVariant();
    const QString icon = on
            ? QStringLiteral("mdi:wifi")
            : QStringLiteral("mdi:wifi-off");

    SensorRuntime &rt = m_runtime[QStringLiteral("wifi_connection")];
    if (rt.state != state || rt.icon != icon) {
        rt.state = state;
        rt.icon = icon;
        rt.dirty = true;
        if (m_started)
            scheduleSensorUpdate();
        else
            rebuildStatusList();
    }
}

void SensorCoordinator::updateLocation(double latitude, double longitude, double accuracyMeters,
                                       int batteryPercent, double speedMps, double altitudeM,
                                       double courseDeg, double verticalAccuracyM)
{
    m_haveLocation = true;

    if (!m_started || !locationReporting())
        return;
    // Internal URL + setting: home is authoritative; never let GPS move us.
    if (atHomeOnInternal())
        return;
    if (!qIsFinite(latitude) || !qIsFinite(longitude))
        return;

    const QDateTime now = QDateTime::currentDateTimeUtc();
    const bool firstFix = !m_lastGpsAt.isValid();
    const bool dueByTime = firstFix
            || !m_lastLocationPostOk
            || !m_lastLocationSent.isValid()
            || m_lastLocationSent.msecsTo(now)
            >= minimumLocationIntervalMs(m_locationPreset);
    const double moveMeters = firstFix
            ? 0.0
            : haversineMeters(m_lastLat, m_lastLon, latitude, longitude);
    const bool dueByMove = !firstFix
            && moveMeters >= minimumLocationMoveMeters(m_locationPreset);
    const bool betterAccuracy = accuracyMeters > 0
            && (m_lastAccuracy <= 0
                || accuracyMeters + kAccuracyImproveMeters < m_lastAccuracy);

    // Software geofence: post promptly when the resolved zone flips. Uses the
    // fix we already have — no GPS wake on battery saver.
    const QString previousZone = m_locationZone;
    const double probeAccuracy = accuracyMeters > 0 ? accuracyMeters : m_lastAccuracy;
    const QString nextZone = computeLocationZoneAt(latitude, longitude, probeAccuracy);
    const bool zoneChanged = !firstFix && !previousZone.isEmpty()
            && !nextZone.isEmpty() && nextZone != previousZone;
    const bool dueByZone = zoneChanged;

    // A multi-kilometre jump is almost always a stale cached fix from another
    // app (GeoClue). Require a real interval tick and a usable accuracy.
    // Zone transitions still win — leaving home for a distant zone is real.
    if (!firstFix && moveMeters >= 2000.0 && !dueByZone) {
        if (!dueByTime)
            return;
        if (accuracyMeters <= 0 || accuracyMeters > 100.0)
            return;
    }
    // Cell/Wi‑Fi dumps with city-sized error circles are noise near home zones.
    if (accuracyMeters > 250.0 && moveMeters < accuracyMeters && !dueByZone)
        return;
    // Prefer a tighter fix (GPS after Wi‑Fi) even before the interval elapses.
    if (!dueByTime && !dueByMove && !betterAccuracy && !dueByZone)
        return;
    // Do not replace a good fix with a much worse one unless we moved or
    // crossed a zone boundary (report the transition, then maybe seek).
    if (!firstFix && !dueByMove && !dueByZone
            && accuracyMeters > 0 && m_lastAccuracy > 0
            && accuracyMeters > m_lastAccuracy * 1.5
            && accuracyMeters - m_lastAccuracy > kAccuracyImproveMeters)
        return;

    // Same-coordinate suppress (Android-style). Zone changes and failed
    // posts always send; only suppress after a successful identical report.
    const QString locationKey = QStringLiteral("%1,%2")
            .arg(latitude, 0, 'f', 5)
            .arg(longitude, 0, 'f', 5);
    if (!dueByZone && !firstFix && m_lastLocationPostOk
            && locationKey == m_lastSentLocationKey
            && m_lastLocationSent.isValid()
            && m_lastLocationSent.msecsTo(now) < duplicateSuppressMs())
        return;

    if (batteryPercent >= 0)
        m_batteryLevel = batteryPercent;

    m_lastLat = latitude;
    m_lastLon = longitude;
    m_lastAccuracy = accuracyMeters > 0 ? accuracyMeters : m_lastAccuracy;
    m_lastGpsAt = now;
    // Motion extras use -1 as "omit" from QML.
    m_haveMotionExtras = false;
    if (speedMps >= 0 && qIsFinite(speedMps)) {
        m_lastSpeedMps = speedMps;
        m_haveMotionExtras = true;
    } else {
        m_lastSpeedMps = -1;
    }
    if (altitudeM != -1 && qIsFinite(altitudeM)) {
        m_lastAltitudeM = altitudeM;
        m_haveMotionExtras = true;
    } else {
        m_lastAltitudeM = -1;
    }
    if (courseDeg >= 0 && qIsFinite(courseDeg)) {
        m_lastCourseDeg = courseDeg;
        m_haveMotionExtras = true;
    } else {
        m_lastCourseDeg = -1;
    }
    if (verticalAccuracyM >= 0 && qIsFinite(verticalAccuracyM)) {
        m_lastVerticalAccuracyM = verticalAccuracyM;
        m_haveMotionExtras = true;
    } else {
        m_lastVerticalAccuracyM = -1;
    }

    qWarning() << "Helmsman location: post gps" << latitude << longitude
               << "acc=" << m_lastAccuracy << "moveM=" << moveMeters
               << "zone=" << nextZone
               << (dueByZone ? "zone-transition" : "");
    refreshLocationZone();
    if (dueByZone)
        maybeRequestTransitionSeek(m_lastAccuracy);
    postLocationUpdate(dueByZone);
}

void SensorCoordinator::postLocationUpdate(bool force)
{
    if (!m_started || !locationReporting() || m_webhookId.isEmpty())
        return;

    const bool atHome = atHomeOnInternal();
    // Home on internal: use the Home zone coordinates rather than a leftover
    // GPS fix from an earlier trip.
    if (atHome && !m_haveHomeCoordinates)
        fetchZones();
    const bool haveHomeGps = atHome && m_haveHomeCoordinates
            && qIsFinite(m_homeLat) && qIsFinite(m_homeLon);
    const bool haveGps = !atHome && m_haveLocation
            && qIsFinite(m_lastLat) && qIsFinite(m_lastLon);
    if (!atHome && !haveGps)
        return;

    const QDateTime now = QDateTime::currentDateTimeUtc();
    if (!force && m_lastLocationAttemptAt.isValid()
            && m_lastLocationAttemptAt.msecsTo(now) < 2000
            && !atHome)
        return;

    const int battery = m_batteryLevel >= 0 ? m_batteryLevel : 0;

    QJsonObject data;
    if (haveHomeGps) {
        QJsonArray gps;
        gps.append(m_homeLat);
        gps.append(m_homeLon);
        data.insert(QStringLiteral("gps"), gps);
        const double accuracy = m_homeRadius > 0 ? m_homeRadius : kHomeAccuracyFallbackMeters;
        data.insert(QStringLiteral("gps_accuracy"), qRound(accuracy));
    } else if (haveGps) {
        QJsonArray gps;
        gps.append(m_lastLat);
        gps.append(m_lastLon);
        data.insert(QStringLiteral("gps"), gps);
        if (m_lastAccuracy > 0)
            data.insert(QStringLiteral("gps_accuracy"), qRound(m_lastAccuracy));
        // Richer motion attributes on accurate only — free once we have a fix.
        if (m_locationPreset == kLocationPresetAccurate && m_haveMotionExtras) {
            if (m_lastSpeedMps >= 0)
                data.insert(QStringLiteral("speed"), m_lastSpeedMps);
            if (m_lastAltitudeM != -1)
                data.insert(QStringLiteral("altitude"), m_lastAltitudeM);
            if (m_lastCourseDeg >= 0)
                data.insert(QStringLiteral("course"), m_lastCourseDeg);
            if (m_lastVerticalAccuracyM >= 0)
                data.insert(QStringLiteral("vertical_accuracy"),
                            qRound(m_lastVerticalAccuracyM));
        }
    }

    // Always send location_name so HA's device_tracker state matches the cover
    // (GPS-only matching can disagree with our accuracy-aware fences).
    QString locationName;
    QStringList inZones;
    if (atHome) {
        locationName = QStringLiteral("home");
        inZones.append(QStringLiteral("zone.home"));
    } else if (haveGps) {
        locationName = webhookLocationNameAt(m_lastLat, m_lastLon, m_lastAccuracy);
        inZones = computeInZonesAt(m_lastLat, m_lastLon, m_lastAccuracy);
    }
    if (!locationName.isEmpty())
        data.insert(QStringLiteral("location_name"), locationName);
    // in_zones only on Core >= 2026.6 — older cores reject the key silently.
    if (supportsInZones() && (atHome || haveGps)) {
        QJsonArray arr;
        for (int i = 0; i < inZones.size(); ++i)
            arr.append(inZones.at(i));
        data.insert(QStringLiteral("in_zones"), arr);
    }
    if (battery > 0)
        data.insert(QStringLiteral("battery"), battery);

    QJsonObject body;
    body.insert(QStringLiteral("type"), QStringLiteral("update_location"));
    body.insert(QStringLiteral("data"), data);
    m_lastLocationAttemptAt = now;
    postWebhook(WebhookUpdateLocation, body);

    // Success-gated: stamp m_lastLocationSent / UI text only after HTTP 2xx.
    if (atHome && haveHomeGps) {
        m_pendingLocationText = QStringLiteral("home · %1, %2 (±%3 m)")
                .arg(m_homeLat, 0, 'f', 5)
                .arg(m_homeLon, 0, 'f', 5)
                .arg(m_homeRadius > 0 ? m_homeRadius : kHomeAccuracyFallbackMeters, 0, 'f', 0);
        m_pendingLocationKey = QStringLiteral("home");
    } else if (atHome) {
        m_pendingLocationText = QStringLiteral("home (internal connection)");
        m_pendingLocationKey = QStringLiteral("home");
    } else {
        m_pendingLocationText = QStringLiteral("%1, %2 (±%3 m)")
                .arg(m_lastLat, 0, 'f', 5)
                .arg(m_lastLon, 0, 'f', 5)
                .arg(qMax(0.0, m_lastAccuracy), 0, 'f', 0);
        m_pendingLocationKey = QStringLiteral("%1,%2")
                .arg(m_lastLat, 0, 'f', 5)
                .arg(m_lastLon, 0, 'f', 5);
    }
    refreshLocationZone();
}

void SensorCoordinator::updateHomeHeartbeat()
{
    const bool need = m_started && locationReporting() && atHomeOnInternal();
    if (need) {
        if (!m_homeHeartbeatTimer.isActive())
            m_homeHeartbeatTimer.start();
    } else {
        m_homeHeartbeatTimer.stop();
    }
}

void SensorCoordinator::onHomeHeartbeatTimeout()
{
    if (!m_started)
        return;
    postLocationUpdate(true);
}

bool SensorCoordinator::atHomeOnInternal() const
{
    return m_homeOnInternal && m_usingInternalUrl;
}

void SensorCoordinator::claimHomeOnInternal()
{
    updateHomeHeartbeat();
    refreshLocationZone();
    if (!m_started || !locationReporting() || !atHomeOnInternal())
        return;
    qWarning() << "Helmsman location: home on internal connection";
    postLocationUpdate(true);
}

void SensorCoordinator::refreshLocation()
{
    if (!m_started || !locationReporting())
        return;
    if (atHomeOnInternal()) {
        postLocationUpdate(true);
        return;
    }
    // Do not re-post m_lastLat/Lon here. That reused a cached GeoClue /
    // PositionSource dump (often an old city) before a fresh seek finished.
    emit locationRefreshRequested();
}

void SensorCoordinator::setUsingInternalUrl(bool usingInternal)
{
    if (m_usingInternalUrl == usingInternal)
        return;
    m_usingInternalUrl = usingInternal;

    if (!usingInternal) {
        updateHomeHeartbeat();
        refreshLocationZone();
        if (m_started && locationReporting())
            emit locationRefreshRequested();
        return;
    }

    // Connected to the internal host: setting says always report home.
    claimHomeOnInternal();
}

void SensorCoordinator::setHomeOnInternal(bool enabled)
{
    if (m_homeOnInternal == enabled)
        return;
    m_homeOnInternal = enabled;
    persistState();
    emit homeOnInternalChanged();
    if (!enabled) {
        updateHomeHeartbeat();
        refreshLocationZone();
        if (m_started && locationReporting())
            emit locationRefreshRequested();
        return;
    }
    claimHomeOnInternal();
}

void SensorCoordinator::ensureOsVersionSensor()
{
    const QString version = QSysInfo::productVersion();
    QVariantMap attrs;
    attrs.insert(QStringLiteral("pretty_name"), QSysInfo::prettyProductName());
    attrs.insert(QStringLiteral("kernel"), QSysInfo::kernelVersion());
    attrs.insert(QStringLiteral("architecture"), QSysInfo::currentCpuArchitecture());
    attrs.insert(QStringLiteral("os_name"), QStringLiteral("Sailfish OS"));
    setSensorState(QStringLiteral("os_version"),
                   version.isEmpty() ? QStringLiteral("unknown") : version,
                   QStringLiteral("mdi:sail-boat"),
                   attrs);
}

void SensorCoordinator::setSensorState(const QString &id, const QVariant &state,
                                       const QString &icon, const QVariantMap &attrs)
{
    if (!m_runtime.contains(id))
        return;
    SensorRuntime &rt = m_runtime[id];
    if (rt.state != state || rt.icon != icon || rt.attributes != attrs) {
        rt.state = state;
        rt.icon = icon;
        rt.attributes = attrs;
        rt.dirty = true;
    }
}

void SensorCoordinator::setHomeCoordinates(double latitude, double longitude, double radiusMeters)
{
    if (!qIsFinite(latitude) || !qIsFinite(longitude)
            || (qFuzzyIsNull(latitude) && qFuzzyIsNull(longitude)))
        return;
    const bool changed = !m_haveHomeCoordinates
            || !qFuzzyCompare(m_homeLat + 1.0, latitude + 1.0)
            || !qFuzzyCompare(m_homeLon + 1.0, longitude + 1.0)
            || !qFuzzyCompare(m_homeRadius + 1.0, radiusMeters + 1.0);
    m_homeLat = latitude;
    m_homeLon = longitude;
    m_homeRadius = qIsFinite(radiusMeters) ? radiusMeters : -1;
    m_haveHomeCoordinates = true;
    if (changed)
        persistState();
    if (changed && m_started && locationReporting() && atHomeOnInternal())
        postLocationUpdate(true);
}

void SensorCoordinator::replaceZones(const QVariantList &states)
{
    QList<HassZoneFence> next;
    for (int i = 0; i < states.size(); ++i) {
        HassZoneFence fence;
        if (zoneFenceFromState(states.at(i).toMap(), &fence))
            next.append(fence);
    }
    std::sort(next.begin(), next.end(), zoneIdLess);
    applyZoneList(next);
}

void SensorCoordinator::applyZoneList(const QList<HassZoneFence> &zones)
{
    if (zoneListsEqual(m_zones, zones))
        return;
    m_zones = zones;
    for (int i = 0; i < m_zones.size(); ++i) {
        const HassZoneFence &zone = m_zones.at(i);
        if (zone.entityId == QLatin1String("zone.home")) {
            setHomeCoordinates(zone.latitude, zone.longitude, zone.radius);
            break;
        }
    }
    persistZones();
    const QString before = m_locationZone;
    refreshLocationZone();
    // Zone icons may change without the resolved name changing.
    if (before == m_locationZone)
        emit locationZoneChanged();
}

void SensorCoordinator::persistZones() const
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("sensors"));
    QJsonArray arr;
    for (int i = 0; i < m_zones.size(); ++i) {
        const HassZoneFence &zone = m_zones.at(i);
        QJsonObject obj;
        obj.insert(QStringLiteral("entity_id"), zone.entityId);
        obj.insert(QStringLiteral("name"), zone.locationName);
        if (!zone.icon.isEmpty())
            obj.insert(QStringLiteral("icon"), zone.icon);
        obj.insert(QStringLiteral("latitude"), zone.latitude);
        obj.insert(QStringLiteral("longitude"), zone.longitude);
        obj.insert(QStringLiteral("radius"), zone.radius);
        obj.insert(QStringLiteral("passive"), zone.passive);
        arr.append(obj);
    }
    settings.setValue(QStringLiteral("zones"),
                      QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact)));
    settings.endGroup();
}

void SensorCoordinator::loadPersistedZones()
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("sensors"));
    const QByteArray json = settings.value(QStringLiteral("zones")).toString().toUtf8();
    settings.endGroup();
    if (json.isEmpty()) {
        if (m_haveHomeCoordinates) {
            HassZoneFence home;
            home.entityId = QStringLiteral("zone.home");
            home.locationName = QStringLiteral("home");
            home.latitude = m_homeLat;
            home.longitude = m_homeLon;
            home.radius = m_homeRadius;
            home.passive = false;
            m_zones.append(home);
        }
        return;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(json);
    if (!doc.isArray())
        return;
    QList<HassZoneFence> next;
    const QJsonArray arr = doc.array();
    for (int i = 0; i < arr.size(); ++i) {
        HassZoneFence fence;
        if (zoneFenceFromState(arr.at(i).toObject().toVariantMap(), &fence))
            next.append(fence);
    }
    std::sort(next.begin(), next.end(), zoneIdLess);
    m_zones = next;
    for (int i = 0; i < m_zones.size(); ++i) {
        const HassZoneFence &zone = m_zones.at(i);
        if (zone.entityId != QLatin1String("zone.home"))
            continue;
        m_homeLat = zone.latitude;
        m_homeLon = zone.longitude;
        m_homeRadius = zone.radius;
        m_haveHomeCoordinates = true;
        break;
    }
    refreshLocationZone();
}

void SensorCoordinator::fetchZones()
{
    if (m_zonesFetchPending || m_accessToken.isEmpty() || m_baseUrl.isEmpty())
        return;

    QString base = m_baseUrl;
    if (base.endsWith(QLatin1Char('/')))
        base.chop(1);
    QNetworkRequest request(QUrl(base + QStringLiteral("/api/states")));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization",
                         QByteArray("Bearer ") + m_accessToken.toUtf8());

    QNetworkReply *reply = m_nam->get(request);
    reply->setProperty("webhookKind", static_cast<int>(WebhookGetZones));
    connect(reply, SIGNAL(finished()), this, SLOT(onWebhookFinished()));
    m_zonesFetchPending = true;
}

void SensorCoordinator::handleZones(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    QVariantList states;
    if (doc.isArray()) {
        states = doc.array().toVariantList();
    } else if (doc.isObject()) {
        states.append(doc.object().toVariantMap());
    } else {
        return;
    }
    replaceZones(states);
}

void SensorCoordinator::handleUpdateLocation(const QByteArray &data, int status)
{
    Q_UNUSED(data);
    if (status != 200 && status != 201) {
        m_lastLocationPostOk = false;
        setLastError(QStringLiteral("update_location failed (HTTP %1)").arg(status));
        return;
    }
    // Only advance the send clock / duplicate key after HA accepted the
    // webhook — failed posts can retry on the next eligible fix.
    m_lastLocationPostOk = true;
    m_lastLocationSent = QDateTime::currentDateTimeUtc();
    m_lastSentLocationKey = m_pendingLocationKey;
    if (m_lastLocationText != m_pendingLocationText) {
        m_lastLocationText = m_pendingLocationText;
        emit lastLocationTextChanged();
    }
    rebuildStatusList();
}

void SensorCoordinator::onAppForegrounded()
{
    if (!m_started)
        return;
    refreshConfig();
    scheduleSensorUpdate();
    if (locationReporting() && atHomeOnInternal())
        postLocationUpdate(true);
}

void SensorCoordinator::onPeriodicTimeout()
{
    if (!m_started)
        return;
    ensureOsVersionSensor();
    for (auto it = m_runtime.begin(); it != m_runtime.end(); ++it) {
        if (it.value().registered && !it.value().disabled
                && it.value().locallyEnabled && it.value().state.isValid())
            it.value().dirty = true;
    }
    scheduleSensorUpdate();
}

void SensorCoordinator::onConfigRefreshTimeout()
{
    refreshConfig();
}

void SensorCoordinator::scheduleSensorUpdate()
{
    if (!m_started)
        return;
    if (!m_updateDebounce.isActive())
        m_updateDebounce.start();
}

void SensorCoordinator::onUpdateDebounceTimeout()
{
    flushSensorUpdates();
}

void SensorCoordinator::flushSensorUpdates()
{
    if (!m_started)
        return;

    QJsonArray updates;
    for (const SensorDef &def : m_defs) {
        SensorRuntime &rt = m_runtime[def.uniqueId];
        if (!rt.registered || rt.disabled || !rt.locallyEnabled || !rt.dirty)
            continue;
        const bool allowNull = (def.uniqueId == QLatin1String("wifi_connection"));
        if (!rt.state.isValid() && !allowNull)
            continue;

        QJsonObject item;
        item.insert(QStringLiteral("unique_id"), def.uniqueId);
        item.insert(QStringLiteral("type"), def.type);
        item.insert(QStringLiteral("icon"), rt.icon.isEmpty() ? def.icon : rt.icon);
        if (!rt.attributes.isEmpty())
            item.insert(QStringLiteral("attributes"), QJsonObject::fromVariantMap(rt.attributes));

        insertSensorState(item, rt.state);

        updates.append(item);
        rt.dirty = false;
    }

    if (updates.isEmpty()) {
        rebuildStatusList();
        return;
    }

    QJsonObject body;
    body.insert(QStringLiteral("type"), QStringLiteral("update_sensor_states"));
    body.insert(QStringLiteral("data"), updates);
    postWebhook(WebhookUpdateSensors, body);
}

void SensorCoordinator::handleUpdateSensors(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return;

    const QJsonObject root = doc.object();
    bool changed = false;
    const QDateTime now = QDateTime::currentDateTimeUtc();

    for (auto it = root.begin(); it != root.end(); ++it) {
        const QString uniqueId = it.key();
        if (!m_runtime.contains(uniqueId))
            continue;

        const QJsonObject result = it.value().toObject();
        SensorRuntime &rt = m_runtime[uniqueId];

        if (result.value(QStringLiteral("success")).toBool()) {
            rt.lastUpdated = now;
            rt.lastError.clear();
            if (result.value(QStringLiteral("is_disabled")).toBool()) {
                if (!rt.disabled) {
                    rt.disabled = true;
                    changed = true;
                }
            }
        } else {
            const QJsonObject error = result.value(QStringLiteral("error")).toObject();
            const QString code = error.value(QStringLiteral("code")).toString();
            rt.lastError = error.value(QStringLiteral("message")).toString();
            if (code == QLatin1String("not_registered")) {
                rt.registered = false;
                m_registerQueue.append(uniqueId);
            }
            changed = true;
            setLastError(QStringLiteral("%1: %2").arg(uniqueId, rt.lastError));
        }
    }

    persistState();
    rebuildStatusList();
    if (!m_registerQueue.isEmpty())
        registerNextPending();
    Q_UNUSED(changed);
}

void SensorCoordinator::rebuildStatusList()
{
    QVariantList list;
    for (const SensorDef &def : m_defs) {
        const SensorRuntime &rt = m_runtime.value(def.uniqueId);
        QVariantMap row;
        row.insert(QStringLiteral("uniqueId"), def.uniqueId);
        row.insert(QStringLiteral("name"), def.name);
        row.insert(QStringLiteral("state"),
                   rt.state.isValid() ? rt.state.toString() : QStringLiteral("—"));
        row.insert(QStringLiteral("registered"), rt.registered);
        row.insert(QStringLiteral("disabled"), rt.disabled);
        row.insert(QStringLiteral("enabled"), rt.locallyEnabled);
        row.insert(QStringLiteral("lastError"), rt.lastError);
        row.insert(QStringLiteral("lastUpdated"),
                   rt.lastUpdated.isValid()
                   ? rt.lastUpdated.toLocalTime().toString(QStringLiteral("HH:mm:ss"))
                   : QString());
        list.append(row);
    }

    QVariantMap locationRow;
    locationRow.insert(QStringLiteral("uniqueId"), QStringLiteral("location"));
    locationRow.insert(QStringLiteral("name"), QStringLiteral("Location"));
    locationRow.insert(QStringLiteral("state"),
                       m_lastLocationText.isEmpty() ? QStringLiteral("—") : m_lastLocationText);
    locationRow.insert(QStringLiteral("registered"), m_haveLocation);
    locationRow.insert(QStringLiteral("disabled"), m_locationDisabledInHa);
    locationRow.insert(QStringLiteral("enabled"), m_locationEnabled);
    locationRow.insert(QStringLiteral("lastError"), QString());
    locationRow.insert(QStringLiteral("lastUpdated"), QString());
    list.append(locationRow);

    if (m_statusList != list) {
        m_statusList = list;
        emit sensorStatusesChanged();
    }
}
