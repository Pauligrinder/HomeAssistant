#include "sensorcoordinator.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonValue>
#include <QSettings>
#include <QUrl>
#include <QDebug>
#include <QSysInfo>
#include <QtMath>

#include "appsettings.h"

namespace {

const char kClientName[] = "Helmsman";
const int kPeriodicMs = 15 * 60 * 1000;
const int kConfigRefreshMs = 20 * 60 * 1000;
const int kUpdateDebounceMs = 750;
// Gap between the first webhook calls after start. Issuing config, sensor
// registration, and the first state update together stalled the UI thread on
// slow external endpoints.
const int kStartupStepMs = 500;
const int kMinLocationIntervalMs = 60 * 1000;
const double kMinLocationMoveMeters = 25.0;
const double kAccuracyImproveMeters = 15.0;

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
    , m_locationReporting(true)
    , m_homeOnInternal(true)
    , m_usingInternalUrl(false)
    , m_started(false)
    , m_registrationInFlight(false)
    , m_startupStep(0)
    , m_batteryLevel(-1)
    , m_haveBattery(false)
    , m_haveWifi(false)
    , m_haveLocation(false)
    , m_lastLat(0)
    , m_lastLon(0)
    , m_lastAccuracy(-1)
{
    m_defs = builtInSensors();
    for (const SensorDef &def : m_defs) {
        SensorRuntime rt;
        rt.registered = false;
        rt.disabled = def.defaultDisabled;
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
bool SensorCoordinator::locationReporting() const { return m_locationReporting; }
bool SensorCoordinator::homeOnInternal() const { return m_homeOnInternal; }
QString SensorCoordinator::lastError() const { return m_lastError; }
QString SensorCoordinator::lastLocationText() const { return m_lastLocationText; }

void SensorCoordinator::loadPersistedState()
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("sensors"));
    const QStringList registered = settings.value(QStringLiteral("registered")).toStringList();
    for (const QString &id : registered) {
        if (m_runtime.contains(id))
            m_runtime[id].registered = true;
    }
    if (settings.contains(QStringLiteral("locationReporting")))
        m_locationReporting = settings.value(QStringLiteral("locationReporting")).toBool();
    if (settings.contains(QStringLiteral("homeOnInternal")))
        m_homeOnInternal = settings.value(QStringLiteral("homeOnInternal")).toBool();
    settings.endGroup();
}

void SensorCoordinator::persistState() const
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("sensors"));
    settings.setValue(QStringLiteral("registered"), registeredIds());
    settings.setValue(QStringLiteral("locationReporting"), m_locationReporting);
    settings.setValue(QStringLiteral("homeOnInternal"), m_homeOnInternal);
    settings.endGroup();
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

void SensorCoordinator::setLocationReporting(bool enabled)
{
    if (m_locationReporting == enabled)
        return;
    m_locationReporting = enabled;
    persistState();
    emit locationReportingChanged();
    rebuildStatusList();
}

void SensorCoordinator::configure(const QString &webhookId,
                                  const QString &cloudhookUrl,
                                  const QString &remoteUiUrl,
                                  const QString &baseUrl,
                                  bool ignoreSslErrors)
{
    const bool changed = m_webhookId != webhookId
            || m_cloudhookUrl != cloudhookUrl
            || m_remoteUiUrl != remoteUiUrl
            || m_baseUrl != baseUrl
            || m_ignoreSslErrors != ignoreSslErrors;

    m_webhookId = webhookId;
    m_cloudhookUrl = cloudhookUrl;
    m_remoteUiUrl = remoteUiUrl;
    m_baseUrl = baseUrl;
    m_ignoreSslErrors = ignoreSslErrors;

    if (changed && m_started && !m_webhookId.isEmpty()) {
        // Endpoint switched (internal<->external). Re-sync through the same
        // paced steps as start(): firing these inline hit the new, possibly
        // slow host while the push channel and dashboard were also reloading.
        m_startupStep = 0;
        m_startupTimer.start();
    }
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
    ensureOsVersionSensor();
    m_startupStep = 0;
    m_startupTimer.start();
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
        if (m_homeOnInternal && m_usingInternalUrl)
            postLocationUpdate(true);
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
            if (m_locationReporting == disabled) {
                setLocationReporting(!disabled);
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
    return rt.registered && !rt.disabled;
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

void SensorCoordinator::updateLocation(double latitude, double longitude, double accuracyMeters, int batteryPercent)
{
    m_haveLocation = true;

    if (!m_started || !m_locationReporting)
        return;
    if (!qIsFinite(latitude) || !qIsFinite(longitude))
        return;

    const QDateTime now = QDateTime::currentDateTimeUtc();
    const bool firstFix = !m_lastLocationSent.isValid();
    const bool dueByTime = firstFix
            || m_lastLocationSent.msecsTo(now) >= kMinLocationIntervalMs;
    const bool dueByMove = !firstFix
            && haversineMeters(m_lastLat, m_lastLon, latitude, longitude) >= kMinLocationMoveMeters;
    const bool betterAccuracy = accuracyMeters > 0
            && (m_lastAccuracy <= 0
                || accuracyMeters + kAccuracyImproveMeters < m_lastAccuracy);
    // Prefer a tighter fix (GPS after Wi‑Fi) even before the interval elapses.
    if (!dueByTime && !dueByMove && !betterAccuracy)
        return;
    // Do not replace a good fix with a much worse one unless we moved.
    if (!firstFix && !dueByMove && accuracyMeters > 0 && m_lastAccuracy > 0
            && accuracyMeters > m_lastAccuracy * 1.5
            && accuracyMeters - m_lastAccuracy > kAccuracyImproveMeters)
        return;

    if (batteryPercent >= 0)
        m_batteryLevel = batteryPercent;

    m_lastLat = latitude;
    m_lastLon = longitude;
    m_lastAccuracy = accuracyMeters > 0 ? accuracyMeters : m_lastAccuracy;
    postLocationUpdate(false);
}

void SensorCoordinator::postLocationUpdate(bool force)
{
    if (!m_started || !m_locationReporting || m_webhookId.isEmpty())
        return;

    const bool atHome = m_homeOnInternal && m_usingInternalUrl;
    const bool haveGps = m_haveLocation && qIsFinite(m_lastLat) && qIsFinite(m_lastLon);
    if (!atHome && !haveGps)
        return;

    if (!force && m_lastLocationSent.isValid()
            && m_lastLocationSent.msecsTo(QDateTime::currentDateTimeUtc()) < 2000
            && !atHome)
        return;

    const int battery = m_batteryLevel >= 0 ? m_batteryLevel : 0;

    QJsonObject data;
    if (haveGps) {
        QJsonArray gps;
        gps.append(m_lastLat);
        gps.append(m_lastLon);
        data.insert(QStringLiteral("gps"), gps);
        if (m_lastAccuracy > 0)
            data.insert(QStringLiteral("gps_accuracy"), qRound(m_lastAccuracy));
    }
    if (atHome)
        data.insert(QStringLiteral("location_name"), QStringLiteral("home"));
    if (battery > 0)
        data.insert(QStringLiteral("battery"), battery);

    QJsonObject body;
    body.insert(QStringLiteral("type"), QStringLiteral("update_location"));
    body.insert(QStringLiteral("data"), data);
    postWebhook(WebhookUpdateLocation, body);

    m_lastLocationSent = QDateTime::currentDateTimeUtc();
    if (atHome && !haveGps)
        m_lastLocationText = QStringLiteral("home (internal connection)");
    else if (atHome)
        m_lastLocationText = QStringLiteral("home · %1, %2 (±%3 m)")
                .arg(m_lastLat, 0, 'f', 5)
                .arg(m_lastLon, 0, 'f', 5)
                .arg(qMax(0.0, m_lastAccuracy), 0, 'f', 0);
    else
        m_lastLocationText = QStringLiteral("%1, %2 (±%3 m)")
                .arg(m_lastLat, 0, 'f', 5)
                .arg(m_lastLon, 0, 'f', 5)
                .arg(qMax(0.0, m_lastAccuracy), 0, 'f', 0);
    emit lastLocationTextChanged();
    rebuildStatusList();
}

void SensorCoordinator::setUsingInternalUrl(bool usingInternal)
{
    if (m_usingInternalUrl == usingInternal)
        return;
    m_usingInternalUrl = usingInternal;
    if (m_started && m_locationReporting && m_homeOnInternal)
        postLocationUpdate(true);
}

void SensorCoordinator::setHomeOnInternal(bool enabled)
{
    if (m_homeOnInternal == enabled)
        return;
    m_homeOnInternal = enabled;
    persistState();
    emit homeOnInternalChanged();
    if (m_started && m_locationReporting)
        postLocationUpdate(true);
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

void SensorCoordinator::handleUpdateLocation(const QByteArray &data, int status)
{
    Q_UNUSED(data);
    if (status != 200 && status != 201)
        setLastError(QStringLiteral("update_location failed (HTTP %1)").arg(status));
}

void SensorCoordinator::onAppForegrounded()
{
    if (!m_started)
        return;
    refreshConfig();
    scheduleSensorUpdate();
    // Allow an immediate location post on resume, including a better GPS fix.
    m_lastLocationSent = QDateTime();
    m_lastAccuracy = -1;
}

void SensorCoordinator::onPeriodicTimeout()
{
    if (!m_started)
        return;
    ensureOsVersionSensor();
    for (auto it = m_runtime.begin(); it != m_runtime.end(); ++it) {
        if (it.value().registered && !it.value().disabled && it.value().state.isValid())
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
        if (!rt.registered || rt.disabled || !rt.dirty)
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
    locationRow.insert(QStringLiteral("disabled"), !m_locationReporting);
    locationRow.insert(QStringLiteral("lastError"), QString());
    locationRow.insert(QStringLiteral("lastUpdated"), QString());
    list.append(locationRow);

    if (m_statusList != list) {
        m_statusList = list;
        emit sensorStatusesChanged();
    }
}
