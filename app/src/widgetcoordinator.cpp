#include "widgetcoordinator.h"

#include "mdiiconrenderer.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QFile>
#include <QSaveFile>
#include <QFileSystemWatcher>
#include <QStandardPaths>
#include <QDir>
#include <QUrl>
#include <QHash>
#include <QDateTime>
#include <QDebug>
#include <QDBusConnection>
#include <QColor>
#include <QVariant>
#include <algorithm>

namespace {

const char *kClientName = "Helmsman";
const char *kDbusService = "org.helmsman.harbour-helmsman";
const char *kDbusPath = "/widget";
const int kPollIntervalMs = 8000;
// Never fetch states straight from start()/configure(): those run inside the
// login reply handler and during endpoint switches, where an immediate request
// to a slow remote host wedged the UI thread.
const int kStartupDelayMs = 700;

QString widgetFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/widget.json");
}

bool isLightDimmable(const QJsonObject &attrs)
{
    const QJsonArray modes = attrs.value(QStringLiteral("supported_color_modes")).toArray();
    for (const QJsonValue &value : modes) {
        const QString mode = value.toString();
        if (!mode.isEmpty() && mode != QLatin1String("onoff"))
            return true;
    }
    if (attrs.contains(QStringLiteral("brightness")) && attrs.value(QStringLiteral("brightness")).isDouble())
        return true;
    const int features = attrs.value(QStringLiteral("supported_features")).toInt();
    return (features & 1) != 0;
}

int brightnessToPct(const QJsonValue &brightness)
{
    if (!brightness.isDouble())
        return 0;
    const int raw = qBound(0, brightness.toInt(), 255);
    return qBound(0, int(qRound(raw * 100.0 / 255.0)), 100);
}

QStringList supportedColorModes(const QJsonObject &attrs)
{
    QStringList modes;
    const QJsonArray array = attrs.value(QStringLiteral("supported_color_modes")).toArray();
    for (const QJsonValue &value : array) {
        const QString mode = value.toString();
        if (!mode.isEmpty())
            modes.append(mode);
    }
    return modes;
}

bool modesContain(const QStringList &modes, const QStringList &wanted)
{
    for (const QString &mode : wanted) {
        if (modes.contains(mode))
            return true;
    }
    return false;
}

bool lightSupportsColorTemp(const QJsonObject &attrs)
{
    if (modesContain(supportedColorModes(attrs),
                     QStringList() << QStringLiteral("color_temp")))
        return true;
    const int features = attrs.value(QStringLiteral("supported_features")).toInt();
    return (features & 2) != 0;
}

bool lightSupportsColor(const QJsonObject &attrs)
{
    static const QStringList colorModes = QStringList()
            << QStringLiteral("hs")
            << QStringLiteral("xy")
            << QStringLiteral("rgb")
            << QStringLiteral("rgbw")
            << QStringLiteral("rgbww");
    if (modesContain(supportedColorModes(attrs), colorModes))
        return true;
    const int features = attrs.value(QStringLiteral("supported_features")).toInt();
    return (features & 16) != 0;
}

int miredsToKelvin(int mireds)
{
    if (mireds <= 0)
        return 0;
    return qBound(1000, int(qRound(1000000.0 / double(mireds))), 10000);
}

int kelvinToMireds(int kelvin)
{
    if (kelvin <= 0)
        return 0;
    return qBound(1, int(qRound(1000000.0 / double(kelvin))), 1000);
}

void colorTempRangeK(const QJsonObject &attrs, int *minKelvin, int *maxKelvin)
{
    int minK = attrs.value(QStringLiteral("min_color_temp_kelvin")).toInt();
    int maxK = attrs.value(QStringLiteral("max_color_temp_kelvin")).toInt();
    if (minK <= 0 || maxK <= 0) {
        const int minMireds = attrs.value(QStringLiteral("min_mireds")).toInt();
        const int maxMireds = attrs.value(QStringLiteral("max_mireds")).toInt();
        if (maxMireds > 0)
            minK = miredsToKelvin(maxMireds);
        if (minMireds > 0)
            maxK = miredsToKelvin(minMireds);
    }
    if (minK <= 0)
        minK = 2000;
    if (maxK <= 0)
        maxK = 6500;
    if (minK > maxK)
        std::swap(minK, maxK);
    *minKelvin = minK;
    *maxKelvin = maxK;
}

int currentKelvin(const QJsonObject &attrs)
{
    if (attrs.contains(QStringLiteral("color_temp_kelvin"))
            && attrs.value(QStringLiteral("color_temp_kelvin")).isDouble())
        return attrs.value(QStringLiteral("color_temp_kelvin")).toInt();
    if (attrs.contains(QStringLiteral("color_temp"))
            && attrs.value(QStringLiteral("color_temp")).isDouble())
        return miredsToKelvin(attrs.value(QStringLiteral("color_temp")).toInt());
    return 0;
}

void currentRgb(const QJsonObject &attrs, int *r, int *g, int *b)
{
    *r = *g = *b = -1;
    const QJsonArray rgb = attrs.value(QStringLiteral("rgb_color")).toArray();
    if (rgb.size() >= 3) {
        *r = qBound(0, rgb.at(0).toInt(), 255);
        *g = qBound(0, rgb.at(1).toInt(), 255);
        *b = qBound(0, rgb.at(2).toInt(), 255);
        return;
    }
    const QJsonArray hs = attrs.value(QStringLiteral("hs_color")).toArray();
    if (hs.size() < 2)
        return;
    const QColor color = QColor::fromHsvF(
                qBound(0.0, hs.at(0).toDouble() / 360.0, 1.0),
                qBound(0.0, hs.at(1).toDouble() / 100.0, 1.0),
                1.0);
    *r = color.red();
    *g = color.green();
    *b = color.blue();
}

QString entityDomain(const QString &entityId)
{
    const int dot = entityId.indexOf(QLatin1Char('.'));
    if (dot <= 0)
        return QString();
    return entityId.left(dot);
}

QString entityKind(const QString &entityId)
{
    const QString domain = entityDomain(entityId);
    if (domain == QLatin1String("switch"))
        return QStringLiteral("switch");
    if (domain == QLatin1String("script"))
        return QStringLiteral("script");
    if (domain == QLatin1String("climate"))
        return QStringLiteral("climate");
    if (domain == QLatin1String("light"))
        return QStringLiteral("light");
    return QString();
}

bool isFavoriteEntity(const QString &entityId)
{
    return !entityKind(entityId).isEmpty();
}

QString defaultIconFor(const QString &kind, bool on)
{
    if (kind == QLatin1String("switch"))
        return on ? QStringLiteral("mdi:toggle-switch")
                  : QStringLiteral("mdi:toggle-switch-off");
    if (kind == QLatin1String("script"))
        return QStringLiteral("mdi:script-text");
    if (kind == QLatin1String("climate"))
        return on ? QStringLiteral("mdi:air-conditioner")
                  : QStringLiteral("mdi:fan-off");
    return on ? QStringLiteral("mdi:lightbulb")
              : QStringLiteral("mdi:lightbulb-outline");
}

QStringList jsonStringList(const QJsonObject &attrs, const QString &key)
{
    QStringList out;
    const QJsonArray array = attrs.value(key).toArray();
    for (const QJsonValue &value : array) {
        if (value.isString()) {
            const QString s = value.toString().trimmed();
            if (!s.isEmpty())
                out.append(s);
        } else if (value.isDouble()) {
            out.append(QString::number(value.toInt()));
        }
    }
    return out;
}

QString jsonFlexibleString(const QJsonValue &value)
{
    if (value.isString())
        return value.toString().trimmed();
    if (value.isDouble())
        return QString::number(value.toInt());
    return QString();
}

bool isNonPositionalMode(const QString &mode)
{
    const QString t = mode.trimmed().toLower();
    return t == QLatin1String("auto")
            || t == QLatin1String("swing")
            || t == QLatin1String("off")
            || t == QLatin1String("on")
            || t == QLatin1String("vertical")
            || t == QLatin1String("horizontal")
            || t == QLatin1String("both")
            || t == QLatin1String("split")
            || t == QLatin1String("wide")
            || t == QLatin1String("spot")
            || t == QLatin1String("default");
}

int namedFanPosition(const QString &mode)
{
    QString t = mode.trimmed().toLower();
    t.replace(QLatin1Char('_'), QLatin1Char('-'));
    t.replace(QLatin1Char(' '), QLatin1Char('-'));
    if (t == QLatin1String("quiet") || t == QLatin1String("silent")
            || t == QLatin1String("min") || t == QLatin1String("lowest")
            || t == QLatin1String("low") || t == QLatin1String("level-1"))
        return 1;
    if (t == QLatin1String("low-medium") || t == QLatin1String("level-2"))
        return 2;
    if (t == QLatin1String("medium") || t == QLatin1String("mid")
            || t == QLatin1String("middle") || t == QLatin1String("level-3"))
        return 3;
    if (t == QLatin1String("medium-high") || t == QLatin1String("level-4"))
        return 4;
    if (t == QLatin1String("high") || t == QLatin1String("max")
            || t == QLatin1String("highest") || t == QLatin1String("powerful")
            || t == QLatin1String("level-5"))
        return 5;
    return 0;
}

int trailingPosition(const QString &mode)
{
    const QString t = mode.trimmed();
    int i = t.size() - 1;
    while (i >= 0 && t.at(i).isSpace())
        --i;
    if (i < 0 || !t.at(i).isDigit())
        return 0;
    const int digit = t.at(i).digitValue();
    if (digit < 1 || digit > 5)
        return 0;
    if (i > 0 && t.at(i - 1).isDigit())
        return 0;
    return digit;
}

QStringList emptyFive()
{
    return QStringList() << QString() << QString() << QString()
                         << QString() << QString();
}

int filledLevelCount(const QStringList &levels)
{
    int n = 0;
    for (const QString &mode : levels) {
        if (!mode.isEmpty())
            ++n;
    }
    return n;
}

QStringList positionalLevels(const QStringList &modes, bool namedFan)
{
    QStringList assigned = emptyFive();
    for (const QString &mode : modes) {
        const int pos = trailingPosition(mode);
        if (pos >= 1 && pos <= 5 && assigned.at(pos - 1).isEmpty())
            assigned[pos - 1] = mode;
    }
    if (namedFan) {
        for (const QString &mode : modes) {
            const int pos = namedFanPosition(mode);
            if (pos >= 1 && pos <= 5 && assigned.at(pos - 1).isEmpty())
                assigned[pos - 1] = mode;
        }
    }
    if (filledLevelCount(assigned) > 0)
        return assigned;

    QStringList rest;
    for (const QString &mode : modes) {
        if (isNonPositionalMode(mode))
            continue;
        rest.append(mode);
    }
    const int n = qMin(5, rest.size());
    if (n <= 0)
        return assigned;
    const int spread[][5] = {
        { -1, -1, -1, -1, -1 },
        { 2, -1, -1, -1, -1 },
        { 0, 4, -1, -1, -1 },
        { 0, 2, 4, -1, -1 },
        { 0, 1, 3, 4, -1 },
        { 0, 1, 2, 3, 4 }
    };
    for (int i = 0; i < n; ++i)
        assigned[spread[n][i]] = rest.at(i);
    return assigned;
}

int levelOfMode(const QStringList &levels, const QString &mode)
{
    if (mode.isEmpty())
        return 0;
    for (int i = 0; i < levels.size(); ++i) {
        if (levels.at(i) == mode)
            return i + 1;
    }
    return 0;
}

QString modeForLevel(const QStringList &levels, int level)
{
    if (level < 1 || level > levels.size())
        return QString();
    return levels.at(level - 1);
}

QStringList variantToStringList(const QVariant &value)
{
    if (value.type() == QVariant::StringList)
        return value.toStringList();
    QStringList out;
    const QVariantList list = value.toList();
    for (const QVariant &item : list)
        out.append(item.toString());
    return out;
}

} // namespace

WidgetCoordinator::WidgetCoordinator(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_watcher(new QFileSystemWatcher(this))
    , m_iconRenderer(nullptr)
    , m_ignoreSslErrors(false)
    , m_busy(false)
    , m_active(false)
    , m_dbusRegistered(false)
    , m_loadingSelected(false)
    , m_tokenRejected(false)
    , m_selectedOutstanding(0)
    , m_allStatesReply(nullptr)
{
    m_pollTimer.setInterval(kPollIntervalMs);
    connect(&m_pollTimer, SIGNAL(timeout()), this, SLOT(onPollTimeout()));

    m_startupTimer.setSingleShot(true);
    m_startupTimer.setInterval(kStartupDelayMs);
    connect(&m_startupTimer, SIGNAL(timeout()), this, SLOT(onStartupTimeout()));
    connect(m_nam, SIGNAL(sslErrors(QNetworkReply*,QList<QSslError>)),
            this, SLOT(onSslErrors(QNetworkReply*,QList<QSslError>)));
    connect(m_watcher, SIGNAL(fileChanged(QString)),
            this, SLOT(onWidgetFileChanged(QString)));

    loadSelected();
    watchSelectedFile();
    registerDBus();
}

WidgetCoordinator::~WidgetCoordinator()
{
    if (m_dbusRegistered) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.unregisterObject(QString::fromLatin1(kDbusPath));
        bus.unregisterService(QString::fromLatin1(kDbusService));
    }
}

QVariantList WidgetCoordinator::availableEntities() const
{
    return m_availableEntities;
}

QVariantList WidgetCoordinator::widgetEntities() const
{
    return m_widgetEntities;
}

QVariantList WidgetCoordinator::eventsViewWidgetEntities() const
{
    return m_eventsViewWidgetEntities;
}

QStringList WidgetCoordinator::selectedEntityIds() const
{
    return m_selectedEntityIds;
}

QStringList WidgetCoordinator::eventsViewSelectedEntityIds() const
{
    return m_eventsViewSelectedEntityIds;
}

bool WidgetCoordinator::busy() const
{
    return m_busy;
}

bool WidgetCoordinator::active() const
{
    return m_active;
}

QString WidgetCoordinator::lastError() const
{
    return m_lastError;
}

bool WidgetCoordinator::dbusRegistered() const
{
    return m_dbusRegistered;
}

MdiIconRenderer *WidgetCoordinator::iconRenderer() const
{
    return m_iconRenderer;
}

void WidgetCoordinator::setIconRenderer(MdiIconRenderer *renderer)
{
    if (m_iconRenderer == renderer)
        return;
    m_iconRenderer = renderer;
    emit iconRendererChanged();
    rebuildWidgetEntities();
}

void WidgetCoordinator::configure(const QString &baseUrl,
                                  const QString &accessToken,
                                  const QDateTime &accessExpiresAt,
                                  bool ignoreSslErrors)
{
    const bool tokenChanged = m_accessToken != accessToken;
    const bool changed = m_baseUrl != baseUrl
            || tokenChanged
            || m_accessExpiresAt != accessExpiresAt
            || m_ignoreSslErrors != ignoreSslErrors;
    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_accessExpiresAt = accessExpiresAt;
    m_ignoreSslErrors = ignoreSslErrors;
    if (tokenChanged)
        m_tokenRejected = false;
    if (changed && m_active)
        scheduleStates();
}

void WidgetCoordinator::start()
{
    setActive(true);
    if (!m_pollTimer.isActive())
        m_pollTimer.start();
    scheduleStates();
}

void WidgetCoordinator::stop()
{
    m_pollTimer.stop();
    m_startupTimer.stop();
    setActive(false);
}

void WidgetCoordinator::scheduleStates()
{
    if (!m_startupTimer.isActive())
        m_startupTimer.start();
}

void WidgetCoordinator::onStartupTimeout()
{
    if (m_active)
        getStates();
}

void WidgetCoordinator::setSelectedEntityIds(const QStringList &ids)
{
    QStringList clean;
    clean.reserve(ids.size());
    for (const QString &id : ids) {
        const QString trimmed = id.trimmed();
        if (trimmed.isEmpty() || clean.contains(trimmed))
            continue;
        clean.append(trimmed);
    }
    if (clean == m_selectedEntityIds)
        return;
    m_selectedEntityIds = clean;
    persistSelected();
    emit selectedEntityIdsChanged();
    rebuildWidgetEntities();
    if (m_active)
        getStates();
}

void WidgetCoordinator::setEntitySelected(const QString &entityId, bool selected)
{
    const QString id = entityId.trimmed();
    if (id.isEmpty())
        return;
    QStringList next = m_selectedEntityIds;
    const int index = next.indexOf(id);
    if (selected && index < 0)
        next.append(id);
    else if (!selected && index >= 0)
        next.removeAt(index);
    else
        return;
    setSelectedEntityIds(next);
}

void WidgetCoordinator::setEventsViewSelectedEntityIds(const QStringList &ids)
{
    QStringList clean;
    clean.reserve(ids.size());
    for (const QString &id : ids) {
        const QString trimmed = id.trimmed();
        if (trimmed.isEmpty() || clean.contains(trimmed))
            continue;
        clean.append(trimmed);
    }
    if (clean == m_eventsViewSelectedEntityIds)
        return;
    m_eventsViewSelectedEntityIds = clean;
    persistSelected();
    emit eventsViewSelectedEntityIdsChanged();
    rebuildWidgetEntities();
    if (m_active)
        getStates();
}

void WidgetCoordinator::setEventsViewEntitySelected(const QString &entityId, bool selected)
{
    const QString id = entityId.trimmed();
    if (id.isEmpty())
        return;
    QStringList next = m_eventsViewSelectedEntityIds;
    const int index = next.indexOf(id);
    if (selected && index < 0)
        next.append(id);
    else if (!selected && index >= 0)
        next.removeAt(index);
    else
        return;
    setEventsViewSelectedEntityIds(next);
}

void WidgetCoordinator::refresh()
{
    getSelectedStates();
}

void WidgetCoordinator::refreshAvailable()
{
    getAllStates();
}

void WidgetCoordinator::toggleLight(const QString &entityId)
{
    const QString kind = entityKind(entityId);
    if (kind == QLatin1String("script")) {
        runScript(entityId);
        return;
    }
    if (kind.isEmpty())
        return;

    const QVariantMap current = entityById(entityId);
    const bool wasOn = current.value(QStringLiteral("on")).toBool();
    QVariantMap patch;
    patch.insert(QStringLiteral("on"), !wasOn);
    if (kind == QLatin1String("climate")) {
        if (wasOn) {
            patch.insert(QStringLiteral("state"), QStringLiteral("off"));
            patch.insert(QStringLiteral("hvacMode"), QStringLiteral("off"));
        }
        m_expectOn.insert(entityId, !wasOn);
        applyOptimistic(entityId, patch);
        QJsonObject body;
        body.insert(QStringLiteral("entity_id"), entityId);
        callService(QStringLiteral("climate"),
                    wasOn ? QStringLiteral("turn_off") : QStringLiteral("turn_on"),
                    body);
        return;
    }
    patch.insert(QStringLiteral("state"), wasOn ? QStringLiteral("off") : QStringLiteral("on"));
    if (kind == QLatin1String("light")) {
        if (wasOn) {
            patch.insert(QStringLiteral("brightnessPct"), 0);
        } else {
            int pct = current.value(QStringLiteral("brightnessPct")).toInt();
            if (pct <= 0)
                pct = 100;
            patch.insert(QStringLiteral("brightnessPct"), pct);
        }
    }
    m_expectOn.insert(entityId, !wasOn);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    callService(kind, QStringLiteral("toggle"), body);
}

void WidgetCoordinator::setBrightnessPct(const QString &entityId, int pct)
{
    if (entityKind(entityId) != QLatin1String("light"))
        return;

    pct = qBound(0, pct, 100);
    QVariantMap patch;
    patch.insert(QStringLiteral("brightnessPct"), pct);
    patch.insert(QStringLiteral("on"), pct > 0);
    patch.insert(QStringLiteral("state"), pct > 0 ? QStringLiteral("on") : QStringLiteral("off"));
    m_expectOn.insert(entityId, pct > 0);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    if (pct <= 0) {
        callService(QStringLiteral("light"), QStringLiteral("turn_off"), body);
        return;
    }
    body.insert(QStringLiteral("brightness_pct"), pct);
    callService(QStringLiteral("light"), QStringLiteral("turn_on"), body);
}

void WidgetCoordinator::setColorTempKelvin(const QString &entityId, int kelvin)
{
    if (entityKind(entityId) != QLatin1String("light"))
        return;

    const QVariantMap current = entityById(entityId);
    int minK = current.value(QStringLiteral("minKelvin")).toInt();
    int maxK = current.value(QStringLiteral("maxKelvin")).toInt();
    if (minK <= 0)
        minK = 2000;
    if (maxK <= 0)
        maxK = 6500;
    kelvin = qBound(minK, kelvin, maxK);

    QVariantMap patch;
    patch.insert(QStringLiteral("on"), true);
    patch.insert(QStringLiteral("state"), QStringLiteral("on"));
    patch.insert(QStringLiteral("colorTempKelvin"), kelvin);
    patch.insert(QStringLiteral("colorMode"), QStringLiteral("color_temp"));
    m_expectOn.insert(entityId, true);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("color_temp"), kelvinToMireds(kelvin));
    callService(QStringLiteral("light"), QStringLiteral("turn_on"), body);
}

void WidgetCoordinator::setRgbColor(const QString &entityId, int r, int g, int b)
{
    if (entityKind(entityId) != QLatin1String("light"))
        return;

    r = qBound(0, r, 255);
    g = qBound(0, g, 255);
    b = qBound(0, b, 255);

    QVariantMap patch;
    patch.insert(QStringLiteral("on"), true);
    patch.insert(QStringLiteral("state"), QStringLiteral("on"));
    patch.insert(QStringLiteral("rgbR"), r);
    patch.insert(QStringLiteral("rgbG"), g);
    patch.insert(QStringLiteral("rgbB"), b);
    patch.insert(QStringLiteral("colorMode"), QStringLiteral("rgb"));
    m_expectOn.insert(entityId, true);
    applyOptimistic(entityId, patch);

    QJsonArray rgb;
    rgb.append(r);
    rgb.append(g);
    rgb.append(b);
    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("rgb_color"), rgb);
    callService(QStringLiteral("light"), QStringLiteral("turn_on"), body);
}

void WidgetCoordinator::setHvacMode(const QString &entityId, const QString &mode)
{
    if (entityKind(entityId) != QLatin1String("climate"))
        return;
    QString hvac = mode.trimmed().toLower();
    if (hvac == QLatin1String("fan"))
        hvac = QStringLiteral("fan_only");
    if (hvac.isEmpty())
        return;

    const bool on = hvac != QLatin1String("off");
    QVariantMap patch;
    patch.insert(QStringLiteral("on"), on);
    patch.insert(QStringLiteral("state"), hvac);
    patch.insert(QStringLiteral("hvacMode"), hvac);
    m_expectOn.insert(entityId, on);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("hvac_mode"), hvac);
    callService(QStringLiteral("climate"), QStringLiteral("set_hvac_mode"), body);
}

void WidgetCoordinator::setFanLevel(const QString &entityId, int level)
{
    if (entityKind(entityId) != QLatin1String("climate"))
        return;
    const QVariantMap current = entityById(entityId);
    const QString mode = modeForLevel(
                variantToStringList(current.value(QStringLiteral("fanLevels"))), level);
    if (mode.isEmpty())
        return;

    QVariantMap patch;
    patch.insert(QStringLiteral("fanLevel"), level);
    patch.insert(QStringLiteral("on"), true);
    m_expectOn.insert(entityId, true);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("fan_mode"), mode);
    callService(QStringLiteral("climate"), QStringLiteral("set_fan_mode"), body);
}

void WidgetCoordinator::setVaneVertical(const QString &entityId, int level)
{
    if (entityKind(entityId) != QLatin1String("climate"))
        return;
    const QVariantMap current = entityById(entityId);
    const QString mode = modeForLevel(
                variantToStringList(current.value(QStringLiteral("vaneVerticalLevels"))), level);
    if (mode.isEmpty())
        return;

    QVariantMap patch;
    patch.insert(QStringLiteral("vaneVertical"), level);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("swing_mode"), mode);
    callService(QStringLiteral("climate"), QStringLiteral("set_swing_mode"), body);
}

void WidgetCoordinator::setVaneHorizontal(const QString &entityId, int level)
{
    if (entityKind(entityId) != QLatin1String("climate"))
        return;
    const QVariantMap current = entityById(entityId);
    const QString mode = modeForLevel(
                variantToStringList(current.value(QStringLiteral("vaneHorizontalLevels"))), level);
    if (mode.isEmpty())
        return;

    QVariantMap patch;
    patch.insert(QStringLiteral("vaneHorizontal"), level);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("swing_horizontal_mode"), mode);
    callService(QStringLiteral("climate"), QStringLiteral("set_swing_horizontal_mode"), body);
}

QString WidgetCoordinator::GetEntitiesJson() const
{
    return QString::fromUtf8(QJsonDocument::fromVariant(
                                 m_eventsViewWidgetEntities).toJson(QJsonDocument::Compact));
}

void WidgetCoordinator::Refresh()
{
    refresh();
}

void WidgetCoordinator::ToggleLight(const QString &entityId)
{
    toggleLight(entityId);
}

void WidgetCoordinator::SetBrightnessPct(const QString &entityId, int pct)
{
    setBrightnessPct(entityId, pct);
}

void WidgetCoordinator::SetColorTempKelvin(const QString &entityId, int kelvin)
{
    setColorTempKelvin(entityId, kelvin);
}

void WidgetCoordinator::SetRgbColor(const QString &entityId, int r, int g, int b)
{
    setRgbColor(entityId, r, g, b);
}

void WidgetCoordinator::SetHvacMode(const QString &entityId, const QString &mode)
{
    setHvacMode(entityId, mode);
}

void WidgetCoordinator::SetFanLevel(const QString &entityId, int level)
{
    setFanLevel(entityId, level);
}

void WidgetCoordinator::SetVaneVertical(const QString &entityId, int level)
{
    setVaneVertical(entityId, level);
}

void WidgetCoordinator::SetVaneHorizontal(const QString &entityId, int level)
{
    setVaneHorizontal(entityId, level);
}

void WidgetCoordinator::OpenFavorites()
{
    emit openFavoritesRequested();
}

void WidgetCoordinator::runScript(const QString &entityId)
{
    if (entityKind(entityId) != QLatin1String("script"))
        return;
    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    callService(QStringLiteral("script"), QStringLiteral("turn_on"), body);
}

void WidgetCoordinator::cancelScript(const QString &entityId)
{
    if (entityKind(entityId) != QLatin1String("script"))
        return;
    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    callService(QStringLiteral("script"), QStringLiteral("turn_off"), body);
}

void WidgetCoordinator::RunScript(const QString &entityId)
{
    runScript(entityId);
}

void WidgetCoordinator::CancelScript(const QString &entityId)
{
    cancelScript(entityId);
}

void WidgetCoordinator::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void WidgetCoordinator::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void WidgetCoordinator::setError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

void WidgetCoordinator::loadSelected()
{
    m_loadingSelected = true;
    QFile file(widgetFilePath());
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject()) {
            const QJsonObject object = doc.object();
            const QJsonArray array = object.value(QStringLiteral("selectedEntityIds")).toArray();
            QStringList ids;
            for (const QJsonValue &value : array) {
                const QString id = value.toString().trimmed();
                if (!id.isEmpty() && !ids.contains(id))
                    ids.append(id);
            }
            if (ids != m_selectedEntityIds) {
                m_selectedEntityIds = ids;
                emit selectedEntityIdsChanged();
                rebuildWidgetEntities();
            }

            const QJsonArray eventsArray = object.value(
                        QStringLiteral("eventsViewSelectedEntityIds")).toArray();
            QStringList eventsIds;
            for (const QJsonValue &value : eventsArray) {
                const QString id = value.toString().trimmed();
                if (!id.isEmpty() && !eventsIds.contains(id))
                    eventsIds.append(id);
            }
            if (eventsIds != m_eventsViewSelectedEntityIds) {
                m_eventsViewSelectedEntityIds = eventsIds;
                emit eventsViewSelectedEntityIdsChanged();
                rebuildWidgetEntities();
            }
        }
    }
    m_loadingSelected = false;
}

void WidgetCoordinator::persistSelected()
{
    if (m_loadingSelected)
        return;
    QJsonArray array;
    for (const QString &id : m_selectedEntityIds)
        array.append(id);
    QJsonArray eventsArray;
    for (const QString &id : m_eventsViewSelectedEntityIds)
        eventsArray.append(id);
    QJsonObject obj;
    obj.insert(QStringLiteral("selectedEntityIds"), array);
    obj.insert(QStringLiteral("eventsViewSelectedEntityIds"), eventsArray);

    const QString path = widgetFilePath();
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "Helmsman widget: could not write" << path << file.errorString();
        return;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    if (!file.commit())
        qWarning() << "Helmsman widget: could not commit" << path << file.errorString();
    watchSelectedFile();
}

void WidgetCoordinator::watchSelectedFile()
{
    const QString path = widgetFilePath();
    if (!QFile::exists(path))
        return;
    const QStringList files = m_watcher->files();
    if (!files.contains(path))
        m_watcher->addPath(path);
}

bool WidgetCoordinator::registerDBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QString::fromLatin1(kDbusService))) {
        qWarning() << "Helmsman widget: DBus name already taken";
        return false;
    }
    if (!bus.registerObject(QString::fromLatin1(kDbusPath), this,
                            QDBusConnection::ExportScriptableSlots
                            | QDBusConnection::ExportScriptableSignals)) {
        qWarning() << "Helmsman widget: could not export DBus object";
        bus.unregisterService(QString::fromLatin1(kDbusService));
        return false;
    }
    m_dbusRegistered = true;
    qWarning() << "Helmsman widget: DBus registered as" << kDbusService;
    return true;
}

QUrl WidgetCoordinator::apiUrl(const QString &path) const
{
    QUrl url(m_baseUrl);
    url.setPath(path);
    return url;
}

bool WidgetCoordinator::accessTokenUsable() const
{
    if (m_tokenRejected || m_accessToken.isEmpty())
        return false;
    if (!m_accessExpiresAt.isValid())
        return false;
    return QDateTime::currentDateTimeUtc().msecsTo(m_accessExpiresAt.toUTC()) > 60 * 1000;
}

void WidgetCoordinator::getStates()
{
    getSelectedStates();
}

void WidgetCoordinator::getSelectedStates()
{
    if (!m_active || m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    if (!accessTokenUsable()) {
        emit accessTokenStale();
        return;
    }
    if (m_selectedOutstanding > 0 || m_allStatesReply)
        return;
    QStringList ids = m_selectedEntityIds;
    for (const QString &id : m_eventsViewSelectedEntityIds) {
        if (!ids.contains(id))
            ids.append(id);
    }
    if (ids.isEmpty()) {
        rebuildWidgetEntities();
        return;
    }

    setBusy(true);
    for (const QString &id : ids)
        getEntityState(id);
}

void WidgetCoordinator::getAllStates()
{
    if (!m_active || m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    if (!accessTokenUsable()) {
        emit accessTokenStale();
        return;
    }
    if (m_allStatesReply)
        return;

    QNetworkRequest request(apiUrl(QStringLiteral("/api/states")));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    m_allStatesReply = m_nam->get(request);
    m_allStatesReply->setProperty("kind", int(RequestStates));
    m_allStatesReply->setProperty("token", m_accessToken);
    connect(m_allStatesReply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    setBusy(true);
}

void WidgetCoordinator::getEntityState(const QString &entityId)
{
    QNetworkRequest request(apiUrl(QStringLiteral("/api/states/") + entityId));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    QNetworkReply *reply = m_nam->get(request);
    reply->setProperty("kind", int(RequestOneState));
    reply->setProperty("token", m_accessToken);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    ++m_selectedOutstanding;
}

void WidgetCoordinator::callService(const QString &domain, const QString &service, const QJsonObject &body)
{
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    if (!accessTokenUsable()) {
        emit accessTokenStale();
        return;
    }

    const QString path = QStringLiteral("/api/services/%1/%2").arg(domain, service);
    QNetworkRequest request(apiUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = m_nam->post(request, payload);
    reply->setProperty("kind", int(RequestService));
    reply->setProperty("token", m_accessToken);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
}

void WidgetCoordinator::applyStates(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray()) {
        setError(QStringLiteral("Unexpected states response"));
        return;
    }

    QVariantList lights;
    const QJsonArray array = doc.array();
    for (const QJsonValue &value : array) {
        if (!value.isObject())
            continue;
        const QJsonObject state = value.toObject();
        const QString entityId = state.value(QStringLiteral("entity_id")).toString();
        if (!isFavoriteEntity(entityId))
            continue;
        lights.append(overlayExpectation(entityFromState(state)));
    }

    std::sort(lights.begin(), lights.end(), [](const QVariant &a, const QVariant &b) {
        const QString left = a.toMap().value(QStringLiteral("name")).toString();
        const QString right = b.toMap().value(QStringLiteral("name")).toString();
        return QString::localeAwareCompare(left, right) < 0;
    });

    if (lights != m_availableEntities) {
        m_availableEntities = lights;
        emit availableEntitiesChanged();
    }
    rebuildWidgetEntities();
    setError(QString());
}

void WidgetCoordinator::applyOneState(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return;
    const QJsonObject state = doc.object();
    const QString entityId = state.value(QStringLiteral("entity_id")).toString();
    if (entityId.isEmpty())
        return;

    if (!isFavoriteEntity(entityId))
        return;

    const QVariantMap map = overlayExpectation(entityFromState(state));
    bool found = false;
    for (int i = 0; i < m_availableEntities.size(); ++i) {
        if (m_availableEntities.at(i).toMap().value(QStringLiteral("entityId")).toString() != entityId)
            continue;
        m_availableEntities[i] = map;
        found = true;
        break;
    }
    if (!found)
        m_availableEntities.append(map);
    emit availableEntitiesChanged();
    rebuildWidgetEntities();
}

QVariantMap WidgetCoordinator::entityFromState(const QJsonObject &state) const
{
    const QString entityId = state.value(QStringLiteral("entity_id")).toString();
    const QString kind = entityKind(entityId);
    const QJsonObject attrs = state.value(QStringLiteral("attributes")).toObject();
    const QString status = state.value(QStringLiteral("state")).toString();
    const bool available = status != QLatin1String("unavailable")
            && status != QLatin1String("unknown");
    const bool onOff = kind != QLatin1String("script");
    const bool on = !onOff
            ? false
            : (kind == QLatin1String("climate")
               ? (available && status != QLatin1String("off"))
               : status == QLatin1String("on"));
    const bool dimmable = kind == QLatin1String("light") && isLightDimmable(attrs);
    QString name = attrs.value(QStringLiteral("friendly_name")).toString();
    if (name.isEmpty())
        name = entityId;

    QVariantMap map;
    map.insert(QStringLiteral("entityId"), entityId);
    map.insert(QStringLiteral("name"), name);
    map.insert(QStringLiteral("kind"), kind.isEmpty() ? QStringLiteral("light") : kind);
    map.insert(QStringLiteral("state"), status);
    map.insert(QStringLiteral("on"), on);
    map.insert(QStringLiteral("available"), available);
    map.insert(QStringLiteral("dimmable"), dimmable);
    map.insert(QStringLiteral("brightnessPct"),
               (on && dimmable) ? brightnessToPct(attrs.value(QStringLiteral("brightness"))) : 0);

    const bool colorTemp = kind == QLatin1String("light") && lightSupportsColorTemp(attrs);
    const bool color = kind == QLatin1String("light") && lightSupportsColor(attrs);
    int minKelvin = 2000;
    int maxKelvin = 6500;
    int rgbR = -1;
    int rgbG = -1;
    int rgbB = -1;
    if (colorTemp)
        colorTempRangeK(attrs, &minKelvin, &maxKelvin);
    if (color)
        currentRgb(attrs, &rgbR, &rgbG, &rgbB);
    map.insert(QStringLiteral("supportsColorTemp"), colorTemp);
    map.insert(QStringLiteral("supportsColor"), color);
    map.insert(QStringLiteral("minKelvin"), minKelvin);
    map.insert(QStringLiteral("maxKelvin"), maxKelvin);
    map.insert(QStringLiteral("colorTempKelvin"), colorTemp ? currentKelvin(attrs) : 0);
    map.insert(QStringLiteral("colorMode"), attrs.value(QStringLiteral("color_mode")).toString());
    map.insert(QStringLiteral("rgbR"), rgbR);
    map.insert(QStringLiteral("rgbG"), rgbG);
    map.insert(QStringLiteral("rgbB"), rgbB);

    if (kind == QLatin1String("climate")) {
        const QString hvacMode = (status == QLatin1String("unavailable")
                                  || status == QLatin1String("unknown"))
                ? QString()
                : status;
        const QStringList hvacModes = jsonStringList(attrs, QStringLiteral("hvac_modes"));
        const QStringList fanModes = jsonStringList(attrs, QStringLiteral("fan_modes"));
        const QStringList swingModes = jsonStringList(attrs, QStringLiteral("swing_modes"));
        QStringList swingHorizontalModes = jsonStringList(attrs, QStringLiteral("swing_horizontal_modes"));
        if (swingHorizontalModes.isEmpty())
            swingHorizontalModes = jsonStringList(attrs, QStringLiteral("swing_horizontal_mode_list"));
        const QStringList fanLevels = positionalLevels(fanModes, true);
        const QStringList vaneVerticalLevels = positionalLevels(swingModes, false);
        const QStringList vaneHorizontalLevels = positionalLevels(swingHorizontalModes, false);
        map.insert(QStringLiteral("hvacMode"), hvacMode);
        map.insert(QStringLiteral("hvacModes"), hvacModes);
        map.insert(QStringLiteral("fanLevels"), fanLevels);
        map.insert(QStringLiteral("fanLevel"),
                   levelOfMode(fanLevels, jsonFlexibleString(attrs.value(QStringLiteral("fan_mode")))));
        map.insert(QStringLiteral("vaneVerticalLevels"), vaneVerticalLevels);
        map.insert(QStringLiteral("vaneVertical"),
                   levelOfMode(vaneVerticalLevels,
                               jsonFlexibleString(attrs.value(QStringLiteral("swing_mode")))));
        map.insert(QStringLiteral("vaneHorizontalLevels"), vaneHorizontalLevels);
        map.insert(QStringLiteral("vaneHorizontal"),
                   levelOfMode(vaneHorizontalLevels,
                               jsonFlexibleString(attrs.value(QStringLiteral("swing_horizontal_mode")))));
        map.insert(QStringLiteral("supportsFan"), filledLevelCount(fanLevels) > 0);
        map.insert(QStringLiteral("supportsVaneVertical"), filledLevelCount(vaneVerticalLevels) > 0);
        map.insert(QStringLiteral("supportsVaneHorizontal"), filledLevelCount(vaneHorizontalLevels) > 0);
    }
    QString icon = attrs.value(QStringLiteral("icon")).toString();
    if (icon.isEmpty())
        icon = defaultIconFor(kind, on);
    map.insert(QStringLiteral("icon"), icon);
    map.insert(QStringLiteral("selected"), m_selectedEntityIds.contains(entityId));
    return map;
}

QVariantMap WidgetCoordinator::overlayExpectation(QVariantMap map)
{
    const QString entityId = map.value(QStringLiteral("entityId")).toString();
    if (entityId.isEmpty() || !m_expectOn.contains(entityId))
        return map;
    if (map.value(QStringLiteral("kind")).toString() == QLatin1String("script"))
        return map;

    const bool expected = m_expectOn.value(entityId);
    const bool actual = map.value(QStringLiteral("on")).toBool();
    if (actual == expected) {
        m_expectOn.remove(entityId);
        return map;
    }

    map.insert(QStringLiteral("on"), expected);
    if (map.value(QStringLiteral("kind")).toString() == QLatin1String("climate")) {
        if (!expected) {
            map.insert(QStringLiteral("state"), QStringLiteral("off"));
            map.insert(QStringLiteral("hvacMode"), QStringLiteral("off"));
        }
        return map;
    }

    map.insert(QStringLiteral("state"), expected ? QStringLiteral("on") : QStringLiteral("off"));
    if (!expected)
        map.insert(QStringLiteral("brightnessPct"), 0);
    else if (map.value(QStringLiteral("brightnessPct")).toInt() <= 0)
        map.insert(QStringLiteral("brightnessPct"), 100);
    return map;
}

void WidgetCoordinator::mergeServiceStates(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray() || doc.array().isEmpty())
        return;

    QHash<QString, int> indexById;
    for (int i = 0; i < m_availableEntities.size(); ++i) {
        const QString id = m_availableEntities.at(i).toMap().value(QStringLiteral("entityId")).toString();
        if (!id.isEmpty())
            indexById.insert(id, i);
    }

    bool changed = false;
    const QJsonArray array = doc.array();
    for (const QJsonValue &value : array) {
        if (!value.isObject())
            continue;
        const QJsonObject state = value.toObject();
        const QString entityId = state.value(QStringLiteral("entity_id")).toString();
        if (!isFavoriteEntity(entityId))
            continue;
        const QVariantMap map = overlayExpectation(entityFromState(state));
        if (indexById.contains(entityId)) {
            m_availableEntities[indexById.value(entityId)] = map;
        } else {
            m_availableEntities.append(map);
        }
        changed = true;
    }
    if (!changed)
        return;
    emit availableEntitiesChanged();
    rebuildWidgetEntities();
}

void WidgetCoordinator::rebuildWidgetEntities()
{
    const QVariantList nextCover = entitiesForSelection(m_selectedEntityIds);
    const QVariantList nextEvents = entitiesForSelection(m_eventsViewSelectedEntityIds);

    if (nextCover != m_widgetEntities) {
        m_widgetEntities = nextCover;
        emit widgetEntitiesChanged();
    }
    if (nextEvents != m_eventsViewWidgetEntities) {
        m_eventsViewWidgetEntities = nextEvents;
        emit eventsViewWidgetEntitiesChanged();
        emit EntitiesChanged();
    }
}

QVariantList WidgetCoordinator::entitiesForSelection(const QStringList &ids) const
{
    QHash<QString, QVariantMap> byId;
    for (const QVariant &value : m_availableEntities) {
        const QVariantMap map = value.toMap();
        byId.insert(map.value(QStringLiteral("entityId")).toString(), map);
    }

    QVariantList next;
    for (const QString &id : ids) {
        if (byId.contains(id)) {
            QVariantMap map = byId.value(id);
            map.insert(QStringLiteral("selected"), true);
            const QString iconPath = watermarkIconPath(map);
            if (!iconPath.isEmpty())
                map.insert(QStringLiteral("iconPath"), iconPath);
            next.append(map);
        } else {
            const QString kind = entityKind(id);
            QVariantMap map;
            map.insert(QStringLiteral("entityId"), id);
            map.insert(QStringLiteral("name"), id);
            map.insert(QStringLiteral("kind"),
                       kind.isEmpty() ? QStringLiteral("light") : kind);
            map.insert(QStringLiteral("state"), QStringLiteral("unknown"));
            map.insert(QStringLiteral("on"), false);
            map.insert(QStringLiteral("available"), false);
            map.insert(QStringLiteral("dimmable"), false);
            map.insert(QStringLiteral("brightnessPct"), 0);
            map.insert(QStringLiteral("supportsColorTemp"), false);
            map.insert(QStringLiteral("supportsColor"), false);
            map.insert(QStringLiteral("minKelvin"), 2000);
            map.insert(QStringLiteral("maxKelvin"), 6500);
            map.insert(QStringLiteral("colorTempKelvin"), 0);
            map.insert(QStringLiteral("colorMode"), QString());
            map.insert(QStringLiteral("rgbR"), -1);
            map.insert(QStringLiteral("rgbG"), -1);
            map.insert(QStringLiteral("rgbB"), -1);
            map.insert(QStringLiteral("icon"), defaultIconFor(kind, false));
            map.insert(QStringLiteral("selected"), true);
            next.append(map);
        }
    }
    return next;
}

// White glyph, matching the cover watermark, written to a file lipstick can read.
QString WidgetCoordinator::watermarkIconPath(const QVariantMap &entity) const
{
    if (!m_iconRenderer)
        return QString();

    QString icon = entity.value(QStringLiteral("icon")).toString();
    const QString kind = entity.value(QStringLiteral("kind")).toString();
    const bool on = entity.value(QStringLiteral("on")).toBool();
    if (kind == QLatin1String("script")) {
        if (icon.isEmpty())
            icon = defaultIconFor(kind, false);
    } else if (on) {
        if (icon.isEmpty())
            icon = defaultIconFor(kind, true);
    } else if (icon.isEmpty()) {
        icon = defaultIconFor(kind, false);
    } else if (kind == QLatin1String("climate")) {
        if (icon == QLatin1String("mdi:air-conditioner"))
            icon = QStringLiteral("mdi:fan-off");
    } else if (!icon.contains(QLatin1String("-outline"))
               && kind != QLatin1String("switch")) {
        const QString outline = icon + QStringLiteral("-outline");
        if (m_iconRenderer->hasIcon(outline))
            icon = outline;
    } else if (kind == QLatin1String("switch") && !on
               && icon == QLatin1String("mdi:toggle-switch")) {
        icon = QStringLiteral("mdi:toggle-switch-off");
    }

    auto cached = m_iconPathCache.constFind(icon);
    if (cached != m_iconPathCache.constEnd())
        return cached.value();

    const QString path = m_iconRenderer->renderIconFile(icon, QStringLiteral("#FFFFFF"), 256);
    m_iconPathCache.insert(icon, path);
    return path;
}

QVariantMap WidgetCoordinator::entityById(const QString &entityId) const
{
    for (const QVariant &value : m_widgetEntities) {
        const QVariantMap map = value.toMap();
        if (map.value(QStringLiteral("entityId")).toString() == entityId)
            return map;
    }
    for (const QVariant &value : m_eventsViewWidgetEntities) {
        const QVariantMap map = value.toMap();
        if (map.value(QStringLiteral("entityId")).toString() == entityId)
            return map;
    }
    for (const QVariant &value : m_availableEntities) {
        const QVariantMap map = value.toMap();
        if (map.value(QStringLiteral("entityId")).toString() == entityId)
            return map;
    }
    return QVariantMap();
}

void WidgetCoordinator::applyOptimistic(const QString &entityId, const QVariantMap &patch)
{
    auto patchList = [this, entityId, patch](QVariantList list) {
        for (int i = 0; i < list.size(); ++i) {
            QVariantMap map = list.at(i).toMap();
            if (map.value(QStringLiteral("entityId")).toString() != entityId)
                continue;
            for (auto it = patch.begin(); it != patch.end(); ++it)
                map.insert(it.key(), it.value());
            // The on/off state decides between filled and outline glyphs.
            const QString iconPath = watermarkIconPath(map);
            if (!iconPath.isEmpty())
                map.insert(QStringLiteral("iconPath"), iconPath);
            list[i] = map;
            break;
        }
        return list;
    };

    m_availableEntities = patchList(m_availableEntities);
    emit availableEntitiesChanged();
    m_widgetEntities = patchList(m_widgetEntities);
    emit widgetEntitiesChanged();
    m_eventsViewWidgetEntities = patchList(m_eventsViewWidgetEntities);
    emit eventsViewWidgetEntitiesChanged();
    emit EntitiesChanged();
}

void WidgetCoordinator::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    const RequestKind kind = static_cast<RequestKind>(reply->property("kind").toInt());
    const QByteArray data = reply->readAll();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError netError = reply->error();
    const QString netErrorString = reply->errorString();
    if (reply == m_allStatesReply)
        m_allStatesReply = nullptr;
    if (kind == RequestOneState)
        m_selectedOutstanding = qMax(0, m_selectedOutstanding - 1);
    reply->deleteLater();

    if (kind == RequestStates || (kind == RequestOneState && m_selectedOutstanding == 0))
        setBusy(false);

    if (netError != QNetworkReply::NoError && status == 0) {
        setError(QStringLiteral("Could not reach Home Assistant (%1)").arg(netErrorString));
        return;
    }
    if (status == 401) {
        if (reply->property("token").toString() == m_accessToken) {
            m_tokenRejected = true;
            setError(QStringLiteral("Home Assistant session expired"));
            emit accessTokenStale();
        }
        return;
    }
    if (status < 200 || status >= 300) {
        setError(QStringLiteral("Home Assistant HTTP %1").arg(status));
        return;
    }

    if (kind == RequestStates)
        applyStates(data);
    else if (kind == RequestOneState)
        applyOneState(data);
    else if (kind == RequestService)
        mergeServiceStates(data);
}

void WidgetCoordinator::onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    if (m_ignoreSslErrors && reply)
        reply->ignoreSslErrors();
}

void WidgetCoordinator::onPollTimeout()
{
    if (m_active)
        getStates();
}

void WidgetCoordinator::onWidgetFileChanged(const QString &path)
{
    Q_UNUSED(path);
    watchSelectedFile();
    const QStringList previousCover = m_selectedEntityIds;
    const QStringList previousEvents = m_eventsViewSelectedEntityIds;
    loadSelected();
    if ((previousCover != m_selectedEntityIds
         || previousEvents != m_eventsViewSelectedEntityIds) && m_active)
        getStates();
}
