#include "widgetcoordinator.h"

#include "appsettings.h"
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
#include <QUrlQuery>
#include <QHash>
#include <QDateTime>
#include <QDebug>
#include <QDBusConnection>
#include <QColor>
#include <QVariant>
#include <QSettings>
#include <QtNumeric>
#include <algorithm>
#include <limits>

namespace {

const char *kClientName = "Helmsman";
const char *kDbusService = "org.helmsman.harbour-helmsman";
const char *kDbusPath = "/widget";
const int kPollIntervalMs = 8000;
const int kHistoryIntervalMs = 5 * 60 * 1000;
// Never fetch states straight from start()/configure(): those run inside the
// login reply handler and during endpoint switches, where an immediate request
// to a slow remote host wedged the UI thread.
const int kStartupDelayMs = 700;
const int kPresenceConfirmMs = 45 * 1000;
const int kMaxWidgetNotifications = 8;

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

double jsonValueNumber(const QJsonValue &value, bool *ok)
{
    if (value.isDouble()) {
        if (ok)
            *ok = true;
        return value.toDouble();
    }
    if (value.isString()) {
        bool parsed = false;
        const double n = value.toString().toDouble(&parsed);
        if (ok)
            *ok = parsed;
        return n;
    }
    if (ok)
        *ok = false;
    return 0;
}

QDateTime parseJsonTime(const QJsonValue &value)
{
    if (value.isDouble()) {
        const double n = value.toDouble();
        if (n > 1e12)
            return QDateTime::fromMSecsSinceEpoch(qint64(n), Qt::UTC).toLocalTime();
        if (n > 1e9)
            return QDateTime::fromMSecsSinceEpoch(qint64(n * 1000.0), Qt::UTC).toLocalTime();
    }
    const QString s = value.toString();
    if (s.isEmpty())
        return QDateTime();
    QDateTime dt = QDateTime::fromString(s, Qt::ISODate);
    if (!dt.isValid() && s.size() >= 19) {
        QString normalized = s.left(19);
        if (normalized.at(10) == QLatin1Char(' '))
            normalized[10] = QLatin1Char('T');
        dt = QDateTime::fromString(normalized, QStringLiteral("yyyy-MM-ddTHH:mm:ss"));
    }
    if (dt.isValid() && dt.timeSpec() == Qt::OffsetFromUTC)
        dt = dt.toLocalTime();
    else if (dt.isValid() && dt.timeSpec() == Qt::UTC)
        dt = dt.toLocalTime();
    return dt;
}

void appendGraphPoint(QVariantList *out, const QDateTime &when, double value, int day)
{
    if (!out || !when.isValid() || !qIsFinite(value))
        return;
    QVariantMap point;
    point.insert(QStringLiteral("t"), when.toMSecsSinceEpoch());
    point.insert(QStringLiteral("v"), value);
    point.insert(QStringLiteral("d"), day);
    out->append(point);
}

void parseObjectSeries(const QJsonArray &array, int day, QVariantList *out)
{
    for (const QJsonValue &item : array) {
        if (!item.isObject())
            continue;
        const QJsonObject obj = item.toObject();
        QJsonValue start = obj.value(QStringLiteral("start"));
        if (start.isUndefined() || start.isNull())
            start = obj.value(QStringLiteral("startsAt"));
        if (start.isUndefined() || start.isNull())
            start = obj.value(QStringLiteral("start_time"));
        QJsonValue val = obj.value(QStringLiteral("value"));
        if (val.isUndefined() || val.isNull())
            val = obj.value(QStringLiteral("price"));
        if (val.isUndefined() || val.isNull())
            val = obj.value(QStringLiteral("total"));
        bool ok = false;
        const double v = jsonValueNumber(val, &ok);
        if (!ok)
            continue;
        appendGraphPoint(out, parseJsonTime(start), v, day);
    }
}

void parseNumericSeries(const QJsonArray &array, int day, QVariantList *out)
{
    const int n = array.size();
    if (n < 8)
        return;
    int stepMin = 60;
    if (n >= 90)
        stepMin = 15;
    else if (n >= 46)
        stepMin = 30;
    QDate date = QDate::currentDate();
    if (day == 1)
        date = date.addDays(1);
    const QDateTime start(date, QTime(0, 0), Qt::LocalTime);
    for (int i = 0; i < n; ++i) {
        bool ok = false;
        const double v = jsonValueNumber(array.at(i), &ok);
        if (!ok)
            continue;
        appendGraphPoint(out, start.addSecs(i * stepMin * 60), v, day);
    }
}

bool arrayLooksLikeSeries(const QJsonValue &value)
{
    if (!value.isArray())
        return false;
    const QJsonArray array = value.toArray();
    if (array.size() < 8)
        return false;
    const QJsonValue first = array.first();
    if (first.isDouble())
        return true;
    if (first.isString()) {
        bool ok = false;
        first.toString().toDouble(&ok);
        return ok;
    }
    if (!first.isObject())
        return false;
    const QJsonObject obj = first.toObject();
    return obj.contains(QStringLiteral("value"))
            || obj.contains(QStringLiteral("price"))
            || obj.contains(QStringLiteral("total"));
}

void parseSeriesAttr(const QJsonObject &attrs, const QString &key, int day, QVariantList *out)
{
    const QJsonValue value = attrs.value(key);
    if (!value.isArray())
        return;
    const QJsonArray array = value.toArray();
    if (array.isEmpty())
        return;
    if (array.first().isObject())
        parseObjectSeries(array, day, out);
    else
        parseNumericSeries(array, day, out);
}

QVariantList extractGraphPoints(const QJsonObject &attrs)
{
    QVariantList out;
    parseSeriesAttr(attrs, QStringLiteral("raw_today"), 0, &out);
    if (out.isEmpty())
        parseSeriesAttr(attrs, QStringLiteral("today"), 0, &out);
    const int todayCount = out.size();
    parseSeriesAttr(attrs, QStringLiteral("raw_tomorrow"), 1, &out);
    if (out.size() == todayCount)
        parseSeriesAttr(attrs, QStringLiteral("tomorrow"), 1, &out);
    if (out.isEmpty())
        parseSeriesAttr(attrs, QStringLiteral("prices"), 0, &out);
    const int cap = 200;
    if (out.size() <= cap)
        return out;
    QVariantList sampled;
    const int step = qMax(1, out.size() / cap);
    for (int i = 0; i < out.size(); i += step)
        sampled.append(out.at(i));
    if (sampled.last() != out.last())
        sampled.append(out.last());
    return sampled;
}

bool isGraphSensor(const QJsonObject &state)
{
    const QString entityId = state.value(QStringLiteral("entity_id")).toString();
    if (entityDomain(entityId) != QLatin1String("sensor"))
        return false;
    const QJsonObject attrs = state.value(QStringLiteral("attributes")).toObject();
    return arrayLooksLikeSeries(attrs.value(QStringLiteral("raw_today")))
            || arrayLooksLikeSeries(attrs.value(QStringLiteral("today")))
            || arrayLooksLikeSeries(attrs.value(QStringLiteral("raw_tomorrow")))
            || arrayLooksLikeSeries(attrs.value(QStringLiteral("tomorrow")))
            || arrayLooksLikeSeries(attrs.value(QStringLiteral("prices")));
}

QString graphUnit(const QJsonObject &attrs)
{
    const QString unitOf = attrs.value(QStringLiteral("unit_of_measurement")).toString().trimmed();
    if (!unitOf.isEmpty())
        return unitOf;
    const QString currency = attrs.value(QStringLiteral("currency")).toString().trimmed();
    const QString unit = attrs.value(QStringLiteral("unit")).toString().trimmed();
    if (!currency.isEmpty() && !unit.isEmpty())
        return currency + QLatin1Char('/') + unit;
    if (!currency.isEmpty())
        return currency;
    return unit;
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
    if (kind == QLatin1String("graph"))
        return QStringLiteral("mdi:chart-bar");
    if (kind == QLatin1String("sensor"))
        return QStringLiteral("mdi:chart-line");
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

double jsonNumber(const QJsonObject &obj, const QString &key, double fallback)
{
    const QJsonValue value = obj.value(key);
    if (value.isDouble())
        return value.toDouble();
    if (value.isString()) {
        bool ok = false;
        const double n = value.toString().toDouble(&ok);
        if (ok)
            return n;
    }
    return fallback;
}

QString findSpecialMode(const QStringList &modes, const QString &wanted)
{
    const QString needle = wanted.toLower();
    for (const QString &mode : modes) {
        if (mode.trimmed().toLower() == needle)
            return mode;
    }
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

QStringList variantToStringList(const QVariant &value);

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

QString climateModeForLevel(const QVariantMap &current,
                            const QString &levelsKey,
                            const QString &autoKey,
                            const QString &swingKey,
                            int level)
{
    if (level == 0)
        return current.value(autoKey).toString();
    if (level < 0)
        return current.value(swingKey).toString();
    return modeForLevel(variantToStringList(current.value(levelsKey)), level);
}

bool jsonHasNumber(const QJsonObject &obj, const QString &key)
{
    const QJsonValue value = obj.value(key);
    if (value.isDouble())
        return true;
    if (value.isString()) {
        bool ok = false;
        value.toString().toDouble(&ok);
        return ok;
    }
    return false;
}

QString climateTempUnit(const QString &unit)
{
    if (unit.contains(QLatin1Char('F'))
            || unit.contains(QStringLiteral("fahrenheit"), Qt::CaseInsensitive))
        return QStringLiteral("°F");
    if (!unit.isEmpty() && unit.contains(QChar(0x00B0)))
        return unit;
    return QStringLiteral("°C");
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
    , m_historyReply(nullptr)
    , m_eventsViewWidgetEnabled(false)
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

    m_presenceConfirmTimer.setSingleShot(true);
    m_presenceConfirmTimer.setInterval(kPresenceConfirmMs);
    connect(&m_presenceConfirmTimer, SIGNAL(timeout()),
            this, SLOT(onPresenceConfirmTimeout()));

    loadSelected();
    watchSelectedFile();
    registerDBus();
    loadWidgetPresence();
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

bool WidgetCoordinator::eventsViewWidgetEnabled() const
{
    return m_eventsViewWidgetEnabled;
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
    fetchSensorHistory(true);
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

void WidgetCoordinator::reorderEventsViewEntity(const QString &entityId, int newIndex)
{
    const QString id = entityId.trimmed();
    if (id.isEmpty())
        return;
    QStringList next = m_eventsViewSelectedEntityIds;
    const int from = next.indexOf(id);
    if (from < 0)
        return;
    next.removeAt(from);
    const int dest = qBound(0, newIndex, next.size());
    next.insert(dest, id);
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
    const QString mode = climateModeForLevel(current,
                                            QStringLiteral("fanLevels"),
                                            QStringLiteral("fanAutoMode"),
                                            QString(),
                                            level);
    if (mode.isEmpty())
        return;

    QVariantMap patch;
    patch.insert(QStringLiteral("fanLevel"), level > 0 ? level : 0);
    patch.insert(QStringLiteral("fanIsAuto"), level == 0);
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
    const QString mode = climateModeForLevel(current,
                                            QStringLiteral("vaneVerticalLevels"),
                                            QStringLiteral("vaneVerticalAutoMode"),
                                            QStringLiteral("vaneVerticalSwingMode"),
                                            level);
    if (mode.isEmpty())
        return;

    QVariantMap patch;
    patch.insert(QStringLiteral("vaneVertical"), level > 0 ? level : 0);
    patch.insert(QStringLiteral("vaneVerticalIsAuto"), level == 0);
    patch.insert(QStringLiteral("vaneVerticalIsSwing"), level < 0);
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
    const QString mode = climateModeForLevel(current,
                                            QStringLiteral("vaneHorizontalLevels"),
                                            QStringLiteral("vaneHorizontalAutoMode"),
                                            QStringLiteral("vaneHorizontalSwingMode"),
                                            level);
    if (mode.isEmpty())
        return;

    QVariantMap patch;
    patch.insert(QStringLiteral("vaneHorizontal"), level > 0 ? level : 0);
    patch.insert(QStringLiteral("vaneHorizontalIsAuto"), level == 0);
    patch.insert(QStringLiteral("vaneHorizontalIsSwing"), level < 0);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("swing_horizontal_mode"), mode);
    callService(QStringLiteral("climate"), QStringLiteral("set_swing_horizontal_mode"), body);
}

void WidgetCoordinator::setTargetTemp(const QString &entityId, double temp)
{
    if (entityKind(entityId) != QLatin1String("climate"))
        return;
    const QVariantMap current = entityById(entityId);
    if (!current.value(QStringLiteral("supportsTargetTemp")).toBool())
        return;

    const double minT = current.value(QStringLiteral("minTemp")).toDouble();
    const double maxT = current.value(QStringLiteral("maxTemp")).toDouble();
    if (maxT > minT)
        temp = qBound(minT, temp, maxT);

    QVariantMap patch;
    patch.insert(QStringLiteral("targetTemp"), temp);
    patch.insert(QStringLiteral("on"), true);
    m_expectOn.insert(entityId, true);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    body.insert(QStringLiteral("temperature"), temp);
    callService(QStringLiteral("climate"), QStringLiteral("set_temperature"), body);
}

QString WidgetCoordinator::GetEntitiesJson() const
{
    QVariantList combined = m_notifications;
    for (const QVariant &value : m_eventsViewWidgetEntities)
        combined.append(value);
    return QString::fromUtf8(QJsonDocument::fromVariant(
                                 combined).toJson(QJsonDocument::Compact));
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

void WidgetCoordinator::SetTargetTemp(const QString &entityId, double temp)
{
    setTargetTemp(entityId, temp);
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

void WidgetCoordinator::pushNotification(const QString &title,
                                         const QString &body,
                                         const QString &color,
                                         const QString &iconPath,
                                         const QString &tag)
{
    const QString id = notificationEntityId(tag);
    QVariantMap map;
    map.insert(QStringLiteral("entityId"), id);
    map.insert(QStringLiteral("kind"), QStringLiteral("notification"));
    map.insert(QStringLiteral("name"), title);
    map.insert(QStringLiteral("state"), body);
    map.insert(QStringLiteral("color"), color);
    QString path = iconPath;
    if (path.isEmpty() && m_iconRenderer)
        path = m_iconRenderer->renderIconFile(QStringLiteral("mdi:bell"),
                                             QStringLiteral("#FFFFFF"), 256);
    map.insert(QStringLiteral("iconPath"), path);
    map.insert(QStringLiteral("tag"), tag);
    map.insert(QStringLiteral("on"), true);
    map.insert(QStringLiteral("available"), true);
    map.insert(QStringLiteral("dimmable"), false);

    QVariantList next;
    next.append(map);
    for (const QVariant &value : m_notifications) {
        const QVariantMap existing = value.toMap();
        if (existing.value(QStringLiteral("entityId")).toString() == id)
            continue;
        next.append(value);
        if (next.size() >= kMaxWidgetNotifications)
            break;
    }
    m_notifications = next;
    emitWidgetPayloadChanged();
}

void WidgetCoordinator::dismissNotification(const QString &idOrTag)
{
    if (idOrTag.isEmpty() || m_notifications.isEmpty())
        return;
    const QString id = notificationEntityId(idOrTag);
    QVariantList next;
    bool removed = false;
    for (const QVariant &value : m_notifications) {
        const QVariantMap existing = value.toMap();
        const QString existingId = existing.value(QStringLiteral("entityId")).toString();
        const QString existingTag = existing.value(QStringLiteral("tag")).toString();
        if (existingId == id || existingId == idOrTag || existingTag == idOrTag) {
            removed = true;
            continue;
        }
        next.append(value);
    }
    if (!removed)
        return;
    m_notifications = next;
    emitWidgetPayloadChanged();
}

void WidgetCoordinator::WidgetPresent()
{
    m_presenceConfirmTimer.stop();
    setEventsViewWidgetEnabled(true);
    fetchSensorHistory(false);
}

void WidgetCoordinator::WidgetGone()
{
    m_presenceConfirmTimer.stop();
    setEventsViewWidgetEnabled(false);
}

void WidgetCoordinator::DismissNotification(const QString &idOrTag)
{
    dismissNotification(idOrTag);
}

void WidgetCoordinator::OpenApp()
{
    emit activateAppRequested();
}

void WidgetCoordinator::ReorderEventsViewEntity(const QString &entityId, int newIndex)
{
    reorderEventsViewEntity(entityId, newIndex);
}

void WidgetCoordinator::RemoveEventsViewEntity(const QString &entityId)
{
    setEventsViewEntitySelected(entityId, false);
}

void WidgetCoordinator::onPresenceConfirmTimeout()
{
    setEventsViewWidgetEnabled(false);
}

void WidgetCoordinator::setEventsViewWidgetEnabled(bool enabled)
{
    if (m_eventsViewWidgetEnabled == enabled)
        return;
    m_eventsViewWidgetEnabled = enabled;
    persistWidgetPresence();
    emit eventsViewWidgetEnabledChanged();
}

void WidgetCoordinator::persistWidgetPresence() const
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("widget"));
    settings.setValue(QStringLiteral("eventsViewEnabled"), m_eventsViewWidgetEnabled);
    settings.endGroup();
}

void WidgetCoordinator::loadWidgetPresence()
{
    QSettings settings(AppSettings::filePath(), QSettings::IniFormat);
    settings.beginGroup(QStringLiteral("widget"));
    const bool enabled = settings.value(QStringLiteral("eventsViewEnabled"), false).toBool();
    settings.endGroup();
    if (!enabled)
        return;
    m_eventsViewWidgetEnabled = true;
    emit eventsViewWidgetEnabledChanged();
    m_presenceConfirmTimer.start();
}

QString WidgetCoordinator::notificationEntityId(const QString &tag) const
{
    if (tag.startsWith(QLatin1String("notification:")))
        return tag;
    if (tag.isEmpty())
        return QStringLiteral("notification:") + QString::number(QDateTime::currentMSecsSinceEpoch());
    return QStringLiteral("notification:") + tag;
}

void WidgetCoordinator::emitWidgetPayloadChanged()
{
    emit eventsViewWidgetEntitiesChanged();
    emit EntitiesChanged();
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
        fetchSensorHistory(false);
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

QStringList WidgetCoordinator::historyEntityIds() const
{
    QHash<QString, QString> kindById;
    for (const QVariant &value : m_availableEntities) {
        const QVariantMap map = value.toMap();
        kindById.insert(map.value(QStringLiteral("entityId")).toString(),
                        map.value(QStringLiteral("kind")).toString());
    }

    QStringList ids;
    for (const QString &id : m_eventsViewSelectedEntityIds) {
        if (entityDomain(id) != QLatin1String("sensor"))
            continue;
        if (kindById.value(id) == QLatin1String("graph"))
            continue;
        ids.append(id);
    }
    return ids;
}

void WidgetCoordinator::fetchSensorHistory(bool force)
{
    if (!m_active || m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    if (!accessTokenUsable())
        return;

    const QStringList ids = historyEntityIds();
    if (ids.isEmpty()) {
        if (!m_historyPoints.isEmpty()) {
            m_historyPoints.clear();
            m_historyRequestedIds.clear();
            m_historyFetchedAt = QDateTime();
            rebuildWidgetEntities();
        }
        return;
    }
    if (m_historyReply)
        return;

    const bool idsChanged = ids != m_historyRequestedIds;
    if (!force && !idsChanged && m_historyFetchedAt.isValid()
            && m_historyFetchedAt.msecsTo(QDateTime::currentDateTimeUtc()) < kHistoryIntervalMs)
        return;

    const QDateTime end = QDateTime::currentDateTimeUtc();
    const QDateTime start = end.addDays(-1);
    const QString stamp = start.toUTC().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"))
            + QLatin1Char('Z');
    QUrl url = apiUrl(QStringLiteral("/api/history/period/") + stamp);
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("filter_entity_id"), ids.join(QLatin1Char(',')));
    query.addQueryItem(QStringLiteral("end_time"),
                       end.toUTC().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"))
                       + QLatin1Char('Z'));
    query.addQueryItem(QStringLiteral("significant_changes_only"), QStringLiteral("0"));
    query.addQueryItem(QStringLiteral("no_attributes"), QStringLiteral("1"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    m_historyReply = m_nam->get(request);
    m_historyReply->setProperty("kind", int(RequestHistory));
    m_historyReply->setProperty("token", m_accessToken);
    m_historyRequestedIds = ids;
    connect(m_historyReply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
}

void WidgetCoordinator::applyHistory(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray())
        return;

    QHash<QString, QVariantList> next;
    const QJsonArray outer = doc.array();
    for (const QJsonValue &groupVal : outer) {
        if (!groupVal.isArray())
            continue;
        const QJsonArray states = groupVal.toArray();
        QString entityId;
        QVariantList points;
        for (const QJsonValue &item : states) {
            if (!item.isObject())
                continue;
            const QJsonObject obj = item.toObject();
            if (obj.contains(QStringLiteral("entity_id")))
                entityId = obj.value(QStringLiteral("entity_id")).toString();
            const QString status = obj.value(QStringLiteral("state")).toString();
            if (status.isEmpty()
                    || status == QLatin1String("unavailable")
                    || status == QLatin1String("unknown"))
                continue;
            bool ok = false;
            const double v = jsonValueNumber(obj.value(QStringLiteral("state")), &ok);
            if (!ok)
                continue;
            QJsonValue when = obj.value(QStringLiteral("last_changed"));
            if (when.isUndefined() || when.isNull() || when.toString().isEmpty())
                when = obj.value(QStringLiteral("last_updated"));
            appendGraphPoint(&points, parseJsonTime(when), v, 0);
        }
        if (entityId.isEmpty() || points.size() < 2)
            continue;
        const int cap = 120;
        if (points.size() <= cap) {
            next.insert(entityId, points);
        } else {
            QVariantList sampled;
            const int step = qMax(1, points.size() / cap);
            for (int i = 0; i < points.size(); i += step)
                sampled.append(points.at(i));
            if (sampled.last() != points.last())
                sampled.append(points.last());
            next.insert(entityId, sampled);
        }
    }

    m_historyPoints = next;
    m_historyFetchedAt = QDateTime::currentDateTimeUtc();
    rebuildWidgetEntities();
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
        if (!isFavoriteEntity(entityId) && entityDomain(entityId) != QLatin1String("sensor"))
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
    fetchSensorHistory(false);
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

    if (!isFavoriteEntity(entityId) && entityDomain(entityId) != QLatin1String("sensor"))
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
    QString kind = entityKind(entityId);
    if (kind.isEmpty() && isGraphSensor(state))
        kind = QStringLiteral("graph");
    else if (kind.isEmpty() && entityDomain(entityId) == QLatin1String("sensor"))
        kind = QStringLiteral("sensor");
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
        const QString fanAutoMode = findSpecialMode(fanModes, QStringLiteral("auto"));
        const QString vaneVerticalAutoMode = findSpecialMode(swingModes, QStringLiteral("auto"));
        const QString vaneVerticalSwingMode = findSpecialMode(swingModes, QStringLiteral("swing"));
        const QString vaneHorizontalAutoMode = findSpecialMode(swingHorizontalModes, QStringLiteral("auto"));
        const QString vaneHorizontalSwingMode = findSpecialMode(swingHorizontalModes, QStringLiteral("swing"));
        const QString currentFan = jsonFlexibleString(attrs.value(QStringLiteral("fan_mode")));
        const QString currentVaneV = jsonFlexibleString(attrs.value(QStringLiteral("swing_mode")));
        const QString currentVaneH = jsonFlexibleString(attrs.value(QStringLiteral("swing_horizontal_mode")));
        const bool fanIsAuto = !fanAutoMode.isEmpty()
                && currentFan.compare(fanAutoMode, Qt::CaseInsensitive) == 0;
        const bool vaneVerticalIsAuto = !vaneVerticalAutoMode.isEmpty()
                && currentVaneV.compare(vaneVerticalAutoMode, Qt::CaseInsensitive) == 0;
        const bool vaneVerticalIsSwing = !vaneVerticalSwingMode.isEmpty()
                && currentVaneV.compare(vaneVerticalSwingMode, Qt::CaseInsensitive) == 0;
        const bool vaneHorizontalIsAuto = !vaneHorizontalAutoMode.isEmpty()
                && currentVaneH.compare(vaneHorizontalAutoMode, Qt::CaseInsensitive) == 0;
        const bool vaneHorizontalIsSwing = !vaneHorizontalSwingMode.isEmpty()
                && currentVaneH.compare(vaneHorizontalSwingMode, Qt::CaseInsensitive) == 0;
        const int features = static_cast<int>(jsonNumber(attrs, QStringLiteral("supported_features"), 0));
        const QString unitRaw = attrs.value(QStringLiteral("temperature_unit")).toString();
        const QString tempUnit = climateTempUnit(unitRaw);
        const bool fahrenheit = tempUnit.contains(QLatin1Char('F'));
        const double minTemp = jsonNumber(attrs, QStringLiteral("min_temp"), fahrenheit ? 60.0 : 16.0);
        const double maxTemp = jsonNumber(attrs, QStringLiteral("max_temp"), fahrenheit ? 86.0 : 30.0);
        double tempStep = jsonNumber(attrs, QStringLiteral("target_temp_step"), 0);
        if (tempStep <= 0)
            tempStep = fahrenheit ? 1.0 : 0.5;
        const bool supportsTargetTemp = (features & 1) != 0
                || jsonHasNumber(attrs, QStringLiteral("temperature"))
                || (attrs.contains(QStringLiteral("min_temp"))
                    && attrs.contains(QStringLiteral("max_temp")));
        double targetTemp = jsonHasNumber(attrs, QStringLiteral("temperature"))
                ? jsonNumber(attrs, QStringLiteral("temperature"), (minTemp + maxTemp) / 2.0)
                : (minTemp + maxTemp) / 2.0;
        map.insert(QStringLiteral("hvacMode"), hvacMode);
        map.insert(QStringLiteral("hvacModes"), hvacModes);
        map.insert(QStringLiteral("fanLevels"), fanLevels);
        map.insert(QStringLiteral("fanLevel"), fanIsAuto ? 0 : levelOfMode(fanLevels, currentFan));
        map.insert(QStringLiteral("fanAutoMode"), fanAutoMode);
        map.insert(QStringLiteral("fanIsAuto"), fanIsAuto);
        map.insert(QStringLiteral("vaneVerticalLevels"), vaneVerticalLevels);
        map.insert(QStringLiteral("vaneVertical"),
                   (vaneVerticalIsAuto || vaneVerticalIsSwing)
                   ? 0 : levelOfMode(vaneVerticalLevels, currentVaneV));
        map.insert(QStringLiteral("vaneVerticalAutoMode"), vaneVerticalAutoMode);
        map.insert(QStringLiteral("vaneVerticalSwingMode"), vaneVerticalSwingMode);
        map.insert(QStringLiteral("vaneVerticalIsAuto"), vaneVerticalIsAuto);
        map.insert(QStringLiteral("vaneVerticalIsSwing"), vaneVerticalIsSwing);
        map.insert(QStringLiteral("vaneHorizontalLevels"), vaneHorizontalLevels);
        map.insert(QStringLiteral("vaneHorizontal"),
                   (vaneHorizontalIsAuto || vaneHorizontalIsSwing)
                   ? 0 : levelOfMode(vaneHorizontalLevels, currentVaneH));
        map.insert(QStringLiteral("vaneHorizontalAutoMode"), vaneHorizontalAutoMode);
        map.insert(QStringLiteral("vaneHorizontalSwingMode"), vaneHorizontalSwingMode);
        map.insert(QStringLiteral("vaneHorizontalIsAuto"), vaneHorizontalIsAuto);
        map.insert(QStringLiteral("vaneHorizontalIsSwing"), vaneHorizontalIsSwing);
        map.insert(QStringLiteral("supportsFan"),
                   filledLevelCount(fanLevels) > 0 || !fanAutoMode.isEmpty());
        map.insert(QStringLiteral("supportsVaneVertical"),
                   filledLevelCount(vaneVerticalLevels) > 0
                   || !vaneVerticalAutoMode.isEmpty()
                   || !vaneVerticalSwingMode.isEmpty());
        map.insert(QStringLiteral("supportsVaneHorizontal"),
                   filledLevelCount(vaneHorizontalLevels) > 0
                   || !vaneHorizontalAutoMode.isEmpty()
                   || !vaneHorizontalSwingMode.isEmpty());
        map.insert(QStringLiteral("supportsTargetTemp"), supportsTargetTemp);
        map.insert(QStringLiteral("minTemp"), minTemp);
        map.insert(QStringLiteral("maxTemp"), maxTemp);
        map.insert(QStringLiteral("tempStep"), tempStep);
        map.insert(QStringLiteral("tempUnit"), tempUnit);
        map.insert(QStringLiteral("targetTemp"), targetTemp);
        if (jsonHasNumber(attrs, QStringLiteral("current_temperature")))
            map.insert(QStringLiteral("currentTemp"),
                       jsonNumber(attrs, QStringLiteral("current_temperature"), 0));
    }

    if (kind == QLatin1String("graph")) {
        const QVariantList points = extractGraphPoints(attrs);
        bool hasNow = jsonHasNumber(attrs, QStringLiteral("current_price"));
        double nowVal = hasNow
                ? jsonNumber(attrs, QStringLiteral("current_price"), 0)
                : 0;
        if (!hasNow) {
            bool ok = false;
            nowVal = jsonValueNumber(QJsonValue(status), &ok);
            hasNow = ok;
        }
        if (!hasNow && !points.isEmpty()) {
            const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
            int best = 0;
            qint64 bestDelta = std::numeric_limits<qint64>::max();
            for (int i = 0; i < points.size(); ++i) {
                const qint64 t = points.at(i).toMap().value(QStringLiteral("t")).toLongLong();
                const qint64 delta = qAbs(t - nowMs);
                if (delta < bestDelta) {
                    bestDelta = delta;
                    best = i;
                }
            }
            nowVal = points.at(best).toMap().value(QStringLiteral("v")).toDouble();
            hasNow = true;
        }
        double gmin = 0;
        double gmax = 0;
        if (!points.isEmpty()) {
            bool first = true;
            for (const QVariant &item : points) {
                const double v = item.toMap().value(QStringLiteral("v")).toDouble();
                if (first) {
                    gmin = gmax = v;
                    first = false;
                } else {
                    gmin = qMin(gmin, v);
                    gmax = qMax(gmax, v);
                }
            }
        } else if (jsonHasNumber(attrs, QStringLiteral("min"))
                   && jsonHasNumber(attrs, QStringLiteral("max"))) {
            gmin = jsonNumber(attrs, QStringLiteral("min"), 0);
            gmax = jsonNumber(attrs, QStringLiteral("max"), 0);
        }
        map.insert(QStringLiteral("graphPoints"), points);
        if (hasNow)
            map.insert(QStringLiteral("graphNow"), nowVal);
        map.insert(QStringLiteral("graphUnit"), graphUnit(attrs));
        map.insert(QStringLiteral("graphMin"), gmin);
        map.insert(QStringLiteral("graphMax"), gmax);
        map.insert(QStringLiteral("on"), false);
    }

    if (kind == QLatin1String("sensor")) {
        bool ok = false;
        const double nowVal = jsonValueNumber(QJsonValue(status), &ok);
        if (ok)
            map.insert(QStringLiteral("graphNow"), nowVal);
        map.insert(QStringLiteral("graphUnit"), graphUnit(attrs));
        map.insert(QStringLiteral("on"), false);
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
    if (map.value(QStringLiteral("kind")).toString() == QLatin1String("script")
            || map.value(QStringLiteral("kind")).toString() == QLatin1String("graph")
            || map.value(QStringLiteral("kind")).toString() == QLatin1String("sensor"))
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
        if (!isFavoriteEntity(entityId) && entityDomain(entityId) != QLatin1String("sensor"))
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
    QVariantList nextCover;
    const QVariantList coverAll = entitiesForSelection(m_selectedEntityIds);
    for (const QVariant &value : coverAll) {
        if (value.toMap().value(QStringLiteral("kind")).toString() == QLatin1String("graph")
                || value.toMap().value(QStringLiteral("kind")).toString() == QLatin1String("sensor"))
            continue;
        nextCover.append(value);
    }
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
            if (m_historyPoints.contains(id)) {
                QVariantList pts = m_historyPoints.value(id);
                if (map.contains(QStringLiteral("graphNow")) && !pts.isEmpty()) {
                    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
                    const qint64 lastT = pts.last().toMap().value(QStringLiteral("t")).toLongLong();
                    if (nowMs > lastT) {
                        QVariantMap cur;
                        cur.insert(QStringLiteral("t"), nowMs);
                        cur.insert(QStringLiteral("v"), map.value(QStringLiteral("graphNow")));
                        pts.append(cur);
                    }
                }
                double hmin = 0;
                double hmax = 0;
                bool first = true;
                for (const QVariant &item : pts) {
                    const double v = item.toMap().value(QStringLiteral("v")).toDouble();
                    if (first) {
                        hmin = hmax = v;
                        first = false;
                    } else {
                        hmin = qMin(hmin, v);
                        hmax = qMax(hmax, v);
                    }
                }
                map.insert(QStringLiteral("historyPoints"), pts);
                map.insert(QStringLiteral("historyMin"), hmin);
                map.insert(QStringLiteral("historyMax"), hmax);
            }
            const QString iconPath = watermarkIconPath(map);
            if (!iconPath.isEmpty())
                map.insert(QStringLiteral("iconPath"), iconPath);
            next.append(map);
        } else {
            QString kind = entityKind(id);
            if (kind.isEmpty())
                kind = entityDomain(id) == QLatin1String("sensor")
                        ? QStringLiteral("sensor")
                        : QStringLiteral("light");
            QVariantMap map;
            map.insert(QStringLiteral("entityId"), id);
            map.insert(QStringLiteral("name"), id);
            map.insert(QStringLiteral("kind"), kind);
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
    } else if (kind == QLatin1String("graph") || kind == QLatin1String("sensor")) {
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
    if (reply == m_historyReply)
        m_historyReply = nullptr;
    if (kind == RequestOneState)
        m_selectedOutstanding = qMax(0, m_selectedOutstanding - 1);
    reply->deleteLater();

    if (kind == RequestStates || (kind == RequestOneState && m_selectedOutstanding == 0))
        setBusy(false);

    if (kind == RequestHistory) {
        if (netError != QNetworkReply::NoError && status == 0) {
            qWarning() << "Helmsman widget: history unreachable" << netErrorString;
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
            qWarning() << "Helmsman widget: history HTTP" << status;
            return;
        }
        applyHistory(data);
        if (historyEntityIds() != m_historyRequestedIds)
            fetchSensorHistory(true);
        return;
    }

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
    else if (kind == RequestOneState) {
        applyOneState(data);
        if (m_selectedOutstanding == 0)
            fetchSensorHistory(false);
    } else if (kind == RequestService)
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
    if (m_active) {
        getStates();
        fetchSensorHistory(false);
    }
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
    if (previousEvents != m_eventsViewSelectedEntityIds)
        fetchSensorHistory(true);
}
