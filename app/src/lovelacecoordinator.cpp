#include "lovelacecoordinator.h"
#include "hasswebsocket.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QCryptographicHash>
#include <QDateTime>
#include <QUrlQuery>
#include <QDebug>
#include <QSslError>
#include <algorithm>

namespace {

const char *kClientName = "Helmsman";

QString domainOfEntity(const QString &entityId)
{
    const int dot = entityId.indexOf(QLatin1Char('.'));
    if (dot <= 0)
        return QString();
    return entityId.left(dot);
}

bool domainIsToggleable(const QString &domain)
{
    return domain == QLatin1String("light")
            || domain == QLatin1String("switch")
            || domain == QLatin1String("fan")
            || domain == QLatin1String("input_boolean")
            || domain == QLatin1String("cover")
            || domain == QLatin1String("lock")
            || domain == QLatin1String("climate")
            || domain == QLatin1String("media_player")
            || domain == QLatin1String("humidifier")
            || domain == QLatin1String("siren")
            || domain == QLatin1String("vacuum")
            || domain == QLatin1String("remote")
            || domain == QLatin1String("automation")
            || domain == QLatin1String("script")
            || domain == QLatin1String("scene")
            || domain == QLatin1String("group")
            || domain == QLatin1String("input_button")
            || domain == QLatin1String("button")
            || domain == QLatin1String("valve")
            || domain == QLatin1String("water_heater")
            || domain == QLatin1String("alarm_control_panel");
}

QString defaultIconForDomain(const QString &domain)
{
    if (domain == QLatin1String("light"))
        return QStringLiteral("mdi:lightbulb");
    if (domain == QLatin1String("switch"))
        return QStringLiteral("mdi:toggle-switch");
    if (domain == QLatin1String("climate"))
        return QStringLiteral("mdi:thermostat");
    if (domain == QLatin1String("sensor"))
        return QStringLiteral("mdi:eye");
    if (domain == QLatin1String("binary_sensor"))
        return QStringLiteral("mdi:checkbox-marked-circle");
    if (domain == QLatin1String("cover"))
        return QStringLiteral("mdi:window-shutter");
    if (domain == QLatin1String("fan"))
        return QStringLiteral("mdi:fan");
    if (domain == QLatin1String("lock"))
        return QStringLiteral("mdi:lock");
    if (domain == QLatin1String("media_player"))
        return QStringLiteral("mdi:cast");
    if (domain == QLatin1String("camera"))
        return QStringLiteral("mdi:webcam");
    if (domain == QLatin1String("weather"))
        return QStringLiteral("mdi:weather-partly-cloudy");
    if (domain == QLatin1String("alarm_control_panel"))
        return QStringLiteral("mdi:shield-home");
    if (domain == QLatin1String("script"))
        return QStringLiteral("mdi:script-text");
    if (domain == QLatin1String("scene"))
        return QStringLiteral("mdi:palette");
    if (domain == QLatin1String("person"))
        return QStringLiteral("mdi:account");
    if (domain == QLatin1String("device_tracker"))
        return QStringLiteral("mdi:map-marker");
    if (domain == QLatin1String("todo"))
        return QStringLiteral("mdi:clipboard-list");
    if (domain == QLatin1String("calendar"))
        return QStringLiteral("mdi:calendar");
    if (domain == QLatin1String("humidifier"))
        return QStringLiteral("mdi:air-humidifier");
    if (domain == QLatin1String("plant"))
        return QStringLiteral("mdi:flower");
    return QStringLiteral("mdi:bookmark");
}

int gridColumnsOf(const QVariantMap &card)
{
    const QVariantMap options = card.value(QStringLiteral("grid_options")).toMap();
    if (options.contains(QStringLiteral("columns"))) {
        const QVariant columns = options.value(QStringLiteral("columns"));
        if (columns.toString() == QLatin1String("full"))
            return 12;
        const int n = columns.toInt();
        if (n > 0)
            return qBound(1, n, 48);
    }
    const QVariantMap legacy = card.value(QStringLiteral("layout_options")).toMap();
    if (legacy.contains(QStringLiteral("grid_columns")))
        return qBound(1, legacy.value(QStringLiteral("grid_columns")).toInt(), 48);
    const QString type = card.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("tile") || type == QLatin1String("button")
            || type == QLatin1String("sensor") || type == QLatin1String("gauge")
            || type == QLatin1String("entity"))
        return 6;
    if (type == QLatin1String("heading"))
        return 12;
    return 12;
}

int gridRowsOf(const QVariantMap &card)
{
    const QVariantMap options = card.value(QStringLiteral("grid_options")).toMap();
    if (options.contains(QStringLiteral("rows"))) {
        const QVariant rows = options.value(QStringLiteral("rows"));
        if (rows.toString() == QLatin1String("auto"))
            return 0;
        const int n = rows.toInt();
        if (n > 0)
            return n;
    }
    return 0;
}

QVariantList variantListOf(const QVariant &value)
{
    if (value.type() == QVariant::List)
        return value.toList();
    if (value.type() == QVariant::StringList) {
        QVariantList out;
        const QStringList strings = value.toStringList();
        for (int i = 0; i < strings.size(); ++i)
            out.append(strings.at(i));
        return out;
    }
    if (value.isValid() && !value.isNull())
        return QVariantList() << value;
    return QVariantList();
}

QString dashboardUrlPath(const QVariantMap &dashboard)
{
    QString path = dashboard.value(QStringLiteral("url_path")).toString();
    if (path.isEmpty())
        path = dashboard.value(QStringLiteral("path")).toString();
    if (path == QLatin1String("lovelace") || path == QLatin1String("null"))
        path.clear();
    return path;
}

QVariantMap configMapFromResult(const QVariant &result)
{
    QVariantMap map = result.toMap();
    if (!map.isEmpty())
        return map;
    if (result.type() == QVariant::String) {
        const QByteArray json = result.toString().trimmed().toUtf8();
        if (!json.isEmpty()) {
            const QJsonDocument doc = QJsonDocument::fromJson(json);
            if (doc.isObject())
                return doc.object().toVariantMap();
        }
    }
    return map;
}

bool isConfigNotFound(const QVariantMap &error)
{
    const QString code = error.value(QStringLiteral("code")).toString();
    if (code == QLatin1String("config_not_found"))
        return true;
    const QString message = error.value(QStringLiteral("message")).toString();
    return message.contains(QStringLiteral("No config found"), Qt::CaseInsensitive)
            || message.startsWith(QStringLiteral("Unknown config specified"));
}

bool skipGeneratedDomain(const QString &domain)
{
    return domain == QLatin1String("persistent_notification")
            || domain == QLatin1String("sun")
            || domain == QLatin1String("zone")
            || domain == QLatin1String("conversation")
            || domain == QLatin1String("stt")
            || domain == QLatin1String("tts")
            || domain == QLatin1String("wake_word")
            || domain == QLatin1String("assist_satellite")
            || domain == QLatin1String("tag")
            || domain == QLatin1String("event")
            || domain == QLatin1String("update");
}

QString headingForDomain(const QString &domain)
{
    if (domain == QLatin1String("light"))
        return QStringLiteral("Lights");
    if (domain == QLatin1String("switch"))
        return QStringLiteral("Switches");
    if (domain == QLatin1String("binary_sensor"))
        return QStringLiteral("Binary sensors");
    if (domain == QLatin1String("media_player"))
        return QStringLiteral("Media players");
    if (domain == QLatin1String("climate"))
        return QStringLiteral("Climate");
    if (domain == QLatin1String("cover"))
        return QStringLiteral("Covers");
    if (domain == QLatin1String("sensor"))
        return QStringLiteral("Sensors");
    if (domain == QLatin1String("alarm_control_panel"))
        return QStringLiteral("Alarms");
    if (domain == QLatin1String("device_tracker"))
        return QStringLiteral("Devices");
    QString heading = domain;
    heading.replace(QLatin1Char('_'), QLatin1Char(' '));
    if (!heading.isEmpty())
        heading[0] = heading.at(0).toUpper();
    return heading;
}

const QStringList &generatedDomainOrder()
{
    static const QStringList order = QStringList()
            << QStringLiteral("light")
            << QStringLiteral("switch")
            << QStringLiteral("fan")
            << QStringLiteral("cover")
            << QStringLiteral("climate")
            << QStringLiteral("lock")
            << QStringLiteral("alarm_control_panel")
            << QStringLiteral("media_player")
            << QStringLiteral("vacuum")
            << QStringLiteral("humidifier")
            << QStringLiteral("water_heater")
            << QStringLiteral("camera")
            << QStringLiteral("weather")
            << QStringLiteral("scene")
            << QStringLiteral("script")
            << QStringLiteral("automation")
            << QStringLiteral("input_boolean")
            << QStringLiteral("input_button")
            << QStringLiteral("button")
            << QStringLiteral("person")
            << QStringLiteral("device_tracker")
            << QStringLiteral("binary_sensor")
            << QStringLiteral("sensor")
            << QStringLiteral("todo")
            << QStringLiteral("calendar")
            << QStringLiteral("plant");
    return order;
}

QStringList stringListOf(const QVariant &value)
{
    QStringList out;
    if (value.type() == QVariant::StringList)
        return value.toStringList();
    if (value.type() == QVariant::String) {
        const QString s = value.toString();
        if (!s.isEmpty())
            out.append(s);
        return out;
    }
    const QVariantList list = variantListOf(value);
    for (int i = 0; i < list.size(); ++i) {
        const QString s = list.at(i).toString();
        if (!s.isEmpty())
            out.append(s);
        else if (list.at(i).type() == QVariant::Map) {
            const QString entity = list.at(i).toMap().value(QStringLiteral("entity")).toString();
            if (!entity.isEmpty())
                out.append(entity);
        }
    }
    return out;
}

} // namespace

LovelaceCoordinator::LovelaceCoordinator(QObject *parent)
    : QObject(parent)
    , m_socket(0)
    , m_nam(new QNetworkAccessManager(this))
    , m_ignoreSslErrors(false)
    , m_wantRunning(false)
    , m_ready(false)
    , m_busy(false)
    , m_statesLoaded(false)
    , m_configLoaded(false)
    , m_configFallbackTried(false)
    , m_pendingGenerated(false)
    , m_userIsAdmin(false)
    , m_statesRevision(0)
    , m_currentViewIndex(0)
    , m_getStatesId(0)
    , m_subscribeStatesId(0)
    , m_subscribeLovelaceId(0)
    , m_dashboardsId(0)
    , m_configId(0)
    , m_userIdReq(0)
    , m_areasId(0)
    , m_energyId(0)
{
}

LovelaceCoordinator::~LovelaceCoordinator()
{
}

void LovelaceCoordinator::setWebsocket(HassWebsocket *socket)
{
    if (m_socket == socket)
        return;
    if (m_socket)
        disconnect(m_socket, 0, this, 0);
    m_socket = socket;
    if (!m_socket)
        return;
    connect(m_socket, SIGNAL(connectionReady()), this, SLOT(onConnectionReady()));
    connect(m_socket, SIGNAL(authenticatedChanged()), this, SLOT(onAuthenticatedChanged()));
    connect(m_socket, SIGNAL(resultReceived(int,bool,QVariant,QVariantMap)),
            this, SLOT(onResultReceived(int,bool,QVariant,QVariantMap)));
    connect(m_socket, SIGNAL(eventReceived(int,QVariantMap)),
            this, SLOT(onEventReceived(int,QVariantMap)));
}

void LovelaceCoordinator::configure(const QString &baseUrl,
                                    const QString &accessToken,
                                    bool ignoreSslErrors)
{
    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_ignoreSslErrors = ignoreSslErrors;
}

bool LovelaceCoordinator::ready() const { return m_ready; }
bool LovelaceCoordinator::busy() const { return m_busy; }
bool LovelaceCoordinator::connected() const { return m_socket && m_socket->connected(); }
QString LovelaceCoordinator::lastError() const { return m_lastError; }
QVariantList LovelaceCoordinator::dashboards() const { return m_dashboards; }
QString LovelaceCoordinator::currentUrlPath() const { return m_currentUrlPath; }
QVariantMap LovelaceCoordinator::currentConfig() const { return m_currentConfig; }
QVariantList LovelaceCoordinator::views() const { return m_views; }
int LovelaceCoordinator::currentViewIndex() const { return m_currentViewIndex; }
QVariantMap LovelaceCoordinator::currentView() const
{
    if (m_currentViewIndex < 0 || m_currentViewIndex >= m_views.size())
        return QVariantMap();
    return m_views.at(m_currentViewIndex).toMap();
}
int LovelaceCoordinator::statesRevision() const { return m_statesRevision; }
QString LovelaceCoordinator::userId() const { return m_userId; }
bool LovelaceCoordinator::userIsAdmin() const { return m_userIsAdmin; }
QString LovelaceCoordinator::userName() const { return m_userName; }
QVariantList LovelaceCoordinator::areas() const { return m_areas; }
QVariantMap LovelaceCoordinator::energyPrefs() const { return m_energyPrefs; }
QString LovelaceCoordinator::pendingNavigate() const { return m_pendingNavigate; }
QString LovelaceCoordinator::pendingUrl() const { return m_pendingUrl; }
QString LovelaceCoordinator::pendingMoreInfo() const { return m_pendingMoreInfo; }
QString LovelaceCoordinator::pendingWebPath() const { return m_pendingWebPath; }

void LovelaceCoordinator::setCurrentUrlPath(const QString &path)
{
    QString next = path;
    if (next == QLatin1String("lovelace") || next == QLatin1String("null"))
        next.clear();
    if (m_currentUrlPath == next && m_configLoaded)
        return;
    m_configFallbackTried = true;
    m_pendingGenerated = false;
    m_currentUrlPath = next;
    emit currentUrlPathChanged();
    if (m_wantRunning && m_socket && m_socket->authenticated())
        requestConfig();
}

void LovelaceCoordinator::setCurrentViewIndex(int index)
{
    if (m_views.isEmpty()) {
        if (m_currentViewIndex != 0) {
            m_currentViewIndex = 0;
            emit currentViewIndexChanged();
            emit currentViewChanged();
        }
        return;
    }
    const int bounded = qBound(0, index, m_views.size() - 1);
    if (m_currentViewIndex == bounded)
        return;
    m_currentViewIndex = bounded;
    emit currentViewIndexChanged();
    emit currentViewChanged();
}

void LovelaceCoordinator::start()
{
    m_wantRunning = true;
    if (m_socket && m_socket->authenticated())
        subscribeAll();
}

void LovelaceCoordinator::stop()
{
    m_wantRunning = false;
    m_getStatesId = 0;
    m_subscribeStatesId = 0;
    m_subscribeLovelaceId = 0;
    m_dashboardsId = 0;
    m_configId = 0;
    setReady(false);
    m_statesLoaded = false;
    m_configLoaded = false;
    m_configFallbackTried = false;
    m_pendingGenerated = false;
}

void LovelaceCoordinator::refresh()
{
    if (m_wantRunning && m_socket && m_socket->authenticated())
        subscribeAll();
}

void LovelaceCoordinator::selectViewByPath(const QString &path)
{
    for (int i = 0; i < m_views.size(); ++i) {
        const QVariantMap view = m_views.at(i).toMap();
        if (view.value(QStringLiteral("path")).toString() == path) {
            setCurrentViewIndex(i);
            return;
        }
    }
}

void LovelaceCoordinator::onConnectionReady()
{
    emit connectedChanged();
    if (m_wantRunning)
        subscribeAll();
}

void LovelaceCoordinator::onAuthenticatedChanged()
{
    emit connectedChanged();
    if (!m_socket || !m_socket->authenticated()) {
        setReady(false);
        m_statesLoaded = false;
        m_configLoaded = false;
    }
}

void LovelaceCoordinator::subscribeAll()
{
    if (!m_socket || !m_socket->authenticated())
        return;
    m_configLoaded = false;
    m_configFallbackTried = false;
    m_pendingGenerated = false;
    setReady(false);
    setBusy(true);
    requestUser();
    requestStates();
    requestDashboards();
    requestAreas();
    fetchEnergyPrefs();

    QJsonObject subStates;
    subStates.insert(QStringLiteral("type"), QStringLiteral("subscribe_events"));
    subStates.insert(QStringLiteral("event_type"), QStringLiteral("state_changed"));
    m_subscribeStatesId = m_socket->sendCommand(subStates);

    QJsonObject subLovelace;
    subLovelace.insert(QStringLiteral("type"), QStringLiteral("subscribe_events"));
    subLovelace.insert(QStringLiteral("event_type"), QStringLiteral("lovelace_updated"));
    m_subscribeLovelaceId = m_socket->sendCommand(subLovelace);
}

void LovelaceCoordinator::requestDashboards()
{
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("lovelace/dashboards/list"));
    m_dashboardsId = m_socket->sendCommand(msg);
}

void LovelaceCoordinator::requestConfig()
{
    if (!m_socket || !m_socket->authenticated())
        return;
    setError(QString());
    setReady(false);
    m_configLoaded = false;
    m_pendingGenerated = false;
    setBusy(true);
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("lovelace/config"));
    if (!m_currentUrlPath.isEmpty())
        msg.insert(QStringLiteral("url_path"), m_currentUrlPath);
    m_configId = m_socket->sendCommand(msg);
}

void LovelaceCoordinator::requestStates()
{
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("get_states"));
    m_getStatesId = m_socket->sendCommand(msg);
}

void LovelaceCoordinator::requestUser()
{
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("auth/current_user"));
    m_userIdReq = m_socket->sendCommand(msg);
}

void LovelaceCoordinator::requestAreas()
{
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("config/area_registry/list"));
    m_areasId = m_socket->sendCommand(msg);
}

void LovelaceCoordinator::fetchEnergyPrefs()
{
    if (!m_socket || !m_socket->authenticated())
        return;
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("energy/get_prefs"));
    m_energyId = m_socket->sendCommand(msg);
}

void LovelaceCoordinator::onResultReceived(int id, bool success, const QVariant &result, const QVariantMap &error)
{
    if (id == 0)
        return;

    if (m_templateKeys.contains(id)) {
        const QString key = m_templateKeys.take(id);
        if (success) {
            const QString value = result.toString();
            m_templates.insert(key, value);
            emit templateReady(key, value);
        }
        return;
    }
    if (m_todoById.contains(id)) {
        const QString entityId = m_todoById.take(id);
        if (success) {
            m_todoItems.insert(entityId, variantListOf(result));
            emit todoReady(entityId);
        }
        return;
    }
    if (m_calendarById.contains(id)) {
        const QString entityId = m_calendarById.take(id);
        if (success) {
            m_calendarEvents.insert(entityId, variantListOf(result));
            emit calendarReady(entityId);
        }
        return;
    }

    if (id == m_getStatesId) {
        m_getStatesId = 0;
        if (success)
            applyStates(result);
        else
            setError(error.value(QStringLiteral("message")).toString());
        return;
    }
    if (id == m_dashboardsId) {
        m_dashboardsId = 0;
        if (success)
            applyDashboards(result);
        else
            applyDashboards(QVariantList());
        if (m_wantRunning && m_socket && m_socket->authenticated() && m_configId == 0 && !m_configLoaded)
            requestConfig();
        return;
    }
    if (id == m_configId) {
        m_configId = 0;
        if (success)
            applyConfig(result);
        else
            handleConfigFailure(error);
        return;
    }
    if (id == m_userIdReq) {
        m_userIdReq = 0;
        if (success)
            applyUser(result);
        return;
    }
    if (id == m_areasId) {
        m_areasId = 0;
        if (success)
            applyAreas(result);
        return;
    }
    if (id == m_energyId) {
        m_energyId = 0;
        if (success) {
            m_energyPrefs = result.toMap();
            emit energyPrefsChanged();
        }
        return;
    }
}

void LovelaceCoordinator::onEventReceived(int id, const QVariantMap &event)
{
    if (id == m_subscribeStatesId) {
        applyStateChanged(event);
        return;
    }
    if (id == m_subscribeLovelaceId) {
        const QVariantMap data = event.value(QStringLiteral("data")).toMap();
        const QString path = data.value(QStringLiteral("url_path")).toString();
        if (path.isEmpty() || path == m_currentUrlPath
                || (path == QLatin1String("lovelace") && m_currentUrlPath.isEmpty()))
            requestConfig();
        requestDashboards();
        return;
    }
    if (m_templateKeys.contains(id)) {
        const QString key = m_templateKeys.value(id);
        QString value = event.value(QStringLiteral("result")).toString();
        if (value.isEmpty())
            value = event.value(QStringLiteral("value")).toString();
        m_templates.insert(key, value);
        emit templateReady(key, value);
    }
}

void LovelaceCoordinator::applyStates(const QVariant &result)
{
    const QVariantList list = variantListOf(result);
    m_entities.clear();
    for (int i = 0; i < list.size(); ++i)
        applyStateObject(list.at(i).toMap());
    m_statesLoaded = true;
    ++m_statesRevision;
    emit statesRevisionChanged();
    if (m_pendingGenerated)
        applyGeneratedConfig();
    else if (m_configLoaded)
        setReady(true);
}

void LovelaceCoordinator::applyStateObject(const QVariantMap &state)
{
    const QString entityId = state.value(QStringLiteral("entity_id")).toString();
    if (entityId.isEmpty())
        return;
    m_entities.insert(entityId, state);
}

void LovelaceCoordinator::applyStateChanged(const QVariantMap &event)
{
    const QVariantMap data = event.value(QStringLiteral("data")).toMap();
    const QString entityId = data.value(QStringLiteral("entity_id")).toString();
    const QVariantMap newState = data.value(QStringLiteral("new_state")).toMap();
    if (entityId.isEmpty())
        return;
    if (newState.isEmpty())
        m_entities.remove(entityId);
    else
        m_entities.insert(entityId, newState);
    ++m_statesRevision;
    emit entityChanged(entityId);
    emit statesRevisionChanged();
}

void LovelaceCoordinator::applyDashboards(const QVariant &result)
{
    const QVariantList list = variantListOf(result);
    QVariantMap overview;
    overview.insert(QStringLiteral("id"), QStringLiteral("lovelace"));
    overview.insert(QStringLiteral("url_path"), QString());
    overview.insert(QStringLiteral("title"), QStringLiteral("Overview"));
    overview.insert(QStringLiteral("icon"), QStringLiteral("mdi:view-dashboard"));
    QVariantList withDefault;
    withDefault.append(overview);
    for (int i = 0; i < list.size(); ++i) {
        QVariantMap dash = list.at(i).toMap();
        dash.insert(QStringLiteral("url_path"), dashboardUrlPath(dash));
        if (dash.value(QStringLiteral("title")).toString().isEmpty()) {
            const QString path = dash.value(QStringLiteral("url_path")).toString();
            dash.insert(QStringLiteral("title"), path.isEmpty() ? QStringLiteral("Overview") : path);
        }
        withDefault.append(dash);
    }
    m_dashboards = withDefault;
    emit dashboardsChanged();
}

void LovelaceCoordinator::applyConfig(const QVariant &result)
{
    QVariantMap map = configMapFromResult(result);
    if (map.isEmpty() && result.type() == QVariant::List) {
        map.insert(QStringLiteral("views"), result.toList());
    }
    const QVariantList views = variantListOf(map.value(QStringLiteral("views")));
    if (map.isEmpty() || (map.contains(QStringLiteral("strategy")) && views.isEmpty())) {
        applyGeneratedConfig();
        return;
    }
    setError(QString());
    commitConfig(map);
    setBusy(false);
}

void LovelaceCoordinator::commitConfig(const QVariantMap &config)
{
    m_currentConfig = config;
    m_views = normalizeViews(m_currentConfig);
    if (m_currentViewIndex >= m_views.size())
        m_currentViewIndex = 0;
    m_configLoaded = true;
    m_pendingGenerated = false;
    emit currentConfigChanged();
    emit viewsChanged();
    emit currentViewChanged();
    if (m_statesLoaded)
        setReady(true);
}

void LovelaceCoordinator::handleConfigFailure(const QVariantMap &error)
{
    qWarning() << kClientName << "lovelace/config failed for"
               << (m_currentUrlPath.isEmpty() ? QStringLiteral("(default)") : m_currentUrlPath)
               << error;
    if (isConfigNotFound(error)) {
        if (tryFallbackDashboard())
            return;
        applyGeneratedConfig();
        return;
    }
    setBusy(false);
    setError(error.value(QStringLiteral("message")).toString());
}

bool LovelaceCoordinator::tryFallbackDashboard()
{
    if (m_configFallbackTried)
        return false;
    m_configFallbackTried = true;
    QString next;
    for (int i = 0; i < m_dashboards.size(); ++i) {
        const QString path = dashboardUrlPath(m_dashboards.at(i).toMap());
        if (!path.isEmpty()) {
            next = path;
            break;
        }
    }
    if (next.isEmpty() || next == m_currentUrlPath)
        return false;
    m_currentUrlPath = next;
    emit currentUrlPathChanged();
    requestConfig();
    return true;
}

void LovelaceCoordinator::applyGeneratedConfig()
{
    if (!m_statesLoaded) {
        m_pendingGenerated = true;
        setBusy(true);
        return;
    }
    m_pendingGenerated = false;

    QHash<QString, QStringList> byDomain;
    QHash<QString, QVariantMap>::const_iterator it = m_entities.constBegin();
    for (; it != m_entities.constEnd(); ++it) {
        const QString entityId = it.key();
        const QString domain = domainOfEntity(entityId);
        if (domain.isEmpty() || skipGeneratedDomain(domain))
            continue;
        byDomain[domain].append(entityId);
    }

    QVariantList cards;
    QStringList remaining = byDomain.keys();
    const QStringList order = generatedDomainOrder();
    for (int i = 0; i < order.size(); ++i) {
        const QString domain = order.at(i);
        QStringList ids = byDomain.take(domain);
        remaining.removeAll(domain);
        if (ids.isEmpty())
            continue;
        std::sort(ids.begin(), ids.end());
        QVariantMap heading;
        heading.insert(QStringLiteral("type"), QStringLiteral("heading"));
        heading.insert(QStringLiteral("heading"), headingForDomain(domain));
        cards.append(heading);
        for (int e = 0; e < ids.size(); ++e) {
            QVariantMap tile;
            tile.insert(QStringLiteral("type"), QStringLiteral("tile"));
            tile.insert(QStringLiteral("entity"), ids.at(e));
            cards.append(tile);
        }
    }
    remaining.sort();
    for (int i = 0; i < remaining.size(); ++i) {
        const QString domain = remaining.at(i);
        QStringList ids = byDomain.value(domain);
        if (ids.isEmpty())
            continue;
        std::sort(ids.begin(), ids.end());
        QVariantMap heading;
        heading.insert(QStringLiteral("type"), QStringLiteral("heading"));
        heading.insert(QStringLiteral("heading"), headingForDomain(domain));
        cards.append(heading);
        for (int e = 0; e < ids.size(); ++e) {
            QVariantMap tile;
            tile.insert(QStringLiteral("type"), QStringLiteral("tile"));
            tile.insert(QStringLiteral("entity"), ids.at(e));
            cards.append(tile);
        }
    }

    if (cards.isEmpty()) {
        QVariantMap heading;
        heading.insert(QStringLiteral("type"), QStringLiteral("heading"));
        heading.insert(QStringLiteral("heading"), QStringLiteral("No entities yet"));
        cards.append(heading);
    }

    QVariantMap section;
    section.insert(QStringLiteral("cards"), cards);
    QVariantMap view;
    view.insert(QStringLiteral("title"), QStringLiteral("Home"));
    view.insert(QStringLiteral("path"), QStringLiteral("home"));
    view.insert(QStringLiteral("type"), QStringLiteral("sections"));
    view.insert(QStringLiteral("sections"), QVariantList() << section);
    QVariantMap config;
    config.insert(QStringLiteral("views"), QVariantList() << view);

    setError(QString());
    commitConfig(config);
    setBusy(false);
}

void LovelaceCoordinator::applyUser(const QVariant &result)
{
    const QVariantMap user = result.toMap();
    m_userId = user.value(QStringLiteral("id")).toString();
    m_userName = user.value(QStringLiteral("name")).toString();
    m_userIsAdmin = user.value(QStringLiteral("is_admin")).toBool();
    emit userIdChanged();
}

void LovelaceCoordinator::applyAreas(const QVariant &result)
{
    m_areas = variantListOf(result);
    emit areasChanged();
}

QVariantList LovelaceCoordinator::normalizeViews(const QVariantMap &config) const
{
    QVariantList views = variantListOf(config.value(QStringLiteral("views")));
    QVariantList out;
    for (int i = 0; i < views.size(); ++i) {
        QVariantMap view = views.at(i).toMap();
        QString type = view.value(QStringLiteral("type")).toString();
        if (type.isEmpty())
            type = view.contains(QStringLiteral("sections"))
                    ? QStringLiteral("sections")
                    : QStringLiteral("masonry");
        view.insert(QStringLiteral("type"), type);
        if (view.value(QStringLiteral("path")).toString().isEmpty())
            view.insert(QStringLiteral("path"), QString::number(i));

        QVariantList sections = variantListOf(view.value(QStringLiteral("sections")));
        QVariantList decoratedSections;
        for (int s = 0; s < sections.size(); ++s) {
            QVariantMap section = sections.at(s).toMap();
            QVariantList cards = decorateCards(variantListOf(section.value(QStringLiteral("cards"))));
            const QString title = section.value(QStringLiteral("title")).toString();
            if (!title.isEmpty()) {
                QVariantMap heading;
                heading.insert(QStringLiteral("type"), QStringLiteral("heading"));
                heading.insert(QStringLiteral("heading"), title);
                heading.insert(QStringLiteral("_columns"), 12);
                heading.insert(QStringLiteral("_rows"), 1);
                cards.prepend(heading);
            }
            section.insert(QStringLiteral("cards"), cards);
            decoratedSections.append(section);
        }
        view.insert(QStringLiteral("sections"), decoratedSections);
        view.insert(QStringLiteral("cards"), decorateCards(variantListOf(view.value(QStringLiteral("cards")))));
        out.append(view);
    }
    return out;
}

QVariantMap LovelaceCoordinator::decorateCard(const QVariantMap &card) const
{
    QVariantMap out = card;
    out.insert(QStringLiteral("_columns"), gridColumnsOf(card));
    out.insert(QStringLiteral("_rows"), gridRowsOf(card));
    const QString type = card.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("grid")
            || type == QLatin1String("vertical-stack")
            || type == QLatin1String("horizontal-stack")) {
        out.insert(QStringLiteral("cards"), decorateCards(variantListOf(card.value(QStringLiteral("cards")))));
    }
    if (type == QLatin1String("conditional")) {
        const QVariantMap nested = card.value(QStringLiteral("card")).toMap();
        if (!nested.isEmpty())
            out.insert(QStringLiteral("card"), decorateCard(nested));
    }
    return out;
}

QVariantList LovelaceCoordinator::decorateCards(const QVariantList &cards) const
{
    QVariantList out;
    for (int i = 0; i < cards.size(); ++i)
        out.append(decorateCard(cards.at(i).toMap()));
    return out;
}

QVariantMap LovelaceCoordinator::entity(const QString &entityId) const
{
    return m_entities.value(entityId);
}

QString LovelaceCoordinator::entityState(const QString &entityId) const
{
    return m_entities.value(entityId).value(QStringLiteral("state")).toString();
}

QString LovelaceCoordinator::friendlyName(const QString &entityId, const QString &fallback) const
{
    const QVariantMap st = m_entities.value(entityId);
    const QString name = st.value(QStringLiteral("attributes")).toMap()
            .value(QStringLiteral("friendly_name")).toString();
    if (!name.isEmpty())
        return name;
    if (!fallback.isEmpty())
        return fallback;
    return entityId;
}

QString LovelaceCoordinator::entityIcon(const QString &entityId, const QString &fallback) const
{
    if (!fallback.isEmpty())
        return fallback;
    const QVariantMap attrs = m_entities.value(entityId).value(QStringLiteral("attributes")).toMap();
    const QString icon = attrs.value(QStringLiteral("icon")).toString();
    if (!icon.isEmpty())
        return icon;
    return defaultIconForDomain(domainOfEntity(entityId));
}

QString LovelaceCoordinator::domainOf(const QString &entityId) const
{
    return domainOfEntity(entityId);
}

bool LovelaceCoordinator::isOn(const QString &entityId) const
{
    const QString domain = domainOfEntity(entityId);
    const QString state = entityState(entityId);
    if (state == QLatin1String("unavailable") || state == QLatin1String("unknown"))
        return false;
    if (domain == QLatin1String("cover"))
        return state == QLatin1String("open") || state == QLatin1String("opening");
    if (domain == QLatin1String("lock"))
        return state == QLatin1String("unlocked");
    if (domain == QLatin1String("climate") || domain == QLatin1String("water_heater")
            || domain == QLatin1String("humidifier"))
        return state != QLatin1String("off");
    if (domain == QLatin1String("alarm_control_panel"))
        return state != QLatin1String("disarmed");
    if (domain == QLatin1String("media_player"))
        return state != QLatin1String("off") && state != QLatin1String("idle")
                && state != QLatin1String("standby");
    return state == QLatin1String("on") || state == QLatin1String("home")
            || state == QLatin1String("active") || state == QLatin1String("playing");
}

bool LovelaceCoordinator::isToggleable(const QString &entityId) const
{
    return domainIsToggleable(domainOfEntity(entityId));
}

bool LovelaceCoordinator::isAvailable(const QString &entityId) const
{
    const QString state = entityState(entityId);
    return state != QLatin1String("unavailable") && state != QLatin1String("unknown")
            && !state.isEmpty();
}

QVariant LovelaceCoordinator::attribute(const QString &entityId, const QString &key) const
{
    return m_entities.value(entityId).value(QStringLiteral("attributes")).toMap().value(key);
}

QString LovelaceCoordinator::formatState(const QString &entityId) const
{
    const QVariantMap st = m_entities.value(entityId);
    const QString state = st.value(QStringLiteral("state")).toString();
    const QVariantMap attrs = st.value(QStringLiteral("attributes")).toMap();
    const QString unit = attrs.value(QStringLiteral("unit_of_measurement")).toString();
    if (state == QLatin1String("unavailable"))
        return QStringLiteral("Unavailable");
    if (state == QLatin1String("unknown"))
        return QStringLiteral("Unknown");
    if (!unit.isEmpty())
        return state + QLatin1Char(' ') + unit;
    QString pretty = state;
    pretty.replace(QLatin1Char('_'), QLatin1Char(' '));
    if (!pretty.isEmpty())
        pretty[0] = pretty[0].toUpper();
    return pretty;
}

QString LovelaceCoordinator::areaName(const QString &areaId) const
{
    for (int i = 0; i < m_areas.size(); ++i) {
        const QVariantMap area = m_areas.at(i).toMap();
        if (area.value(QStringLiteral("area_id")).toString() == areaId
                || area.value(QStringLiteral("id")).toString() == areaId)
            return area.value(QStringLiteral("name")).toString();
    }
    return areaId;
}

QVariantList LovelaceCoordinator::areaEntities(const QString &areaId) const
{
    QVariantList out;
    QHash<QString, QVariantMap>::const_iterator it = m_entities.constBegin();
    for (; it != m_entities.constEnd(); ++it) {
        const QVariantMap attrs = it.value().value(QStringLiteral("attributes")).toMap();
        if (attrs.value(QStringLiteral("area_id")).toString() == areaId)
            out.append(it.key());
    }
    return out;
}

bool LovelaceCoordinator::isVisible(const QVariant &visibility) const
{
    const QVariantList conditions = variantListOf(visibility);
    if (conditions.isEmpty())
        return true;
    return evalConditions(conditions, true);
}

bool LovelaceCoordinator::cardVisible(const QVariantMap &card) const
{
    if (card.contains(QStringLiteral("visibility")))
        return isVisible(card.value(QStringLiteral("visibility")));
    const QString type = card.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("conditional"))
        return evalConditions(variantListOf(card.value(QStringLiteral("conditions"))), true);
    return true;
}

bool LovelaceCoordinator::evalConditions(const QVariantList &conditions, bool matchAll) const
{
    if (conditions.isEmpty())
        return true;
    bool any = false;
    for (int i = 0; i < conditions.size(); ++i) {
        QVariantMap condition = conditions.at(i).toMap();
        if (condition.isEmpty() && conditions.at(i).type() == QVariant::String) {
            condition.insert(QStringLiteral("entity"), conditions.at(i).toString());
            condition.insert(QStringLiteral("state"), QStringLiteral("on"));
        }
        const bool ok = evalCondition(condition);
        if (matchAll && !ok)
            return false;
        if (!matchAll && ok)
            return true;
        any = any || ok;
    }
    return matchAll ? true : any;
}

bool LovelaceCoordinator::evalCondition(const QVariantMap &condition) const
{
    QString type = condition.value(QStringLiteral("condition")).toString();
    if (type.isEmpty())
        type = condition.value(QStringLiteral("type")).toString();

    if (type == QLatin1String("and"))
        return evalConditions(variantListOf(condition.value(QStringLiteral("conditions"))), true);
    if (type == QLatin1String("or"))
        return evalConditions(variantListOf(condition.value(QStringLiteral("conditions"))), false);
    if (type == QLatin1String("not"))
        return !evalConditions(variantListOf(condition.value(QStringLiteral("conditions"))), true);

    if (type == QLatin1String("user")) {
        const QStringList users = stringListOf(condition.value(QStringLiteral("users")));
        return users.isEmpty() || users.contains(m_userId);
    }

    if (type == QLatin1String("screen"))
        return true;

    if (type == QLatin1String("numeric_state")) {
        const QString entityId = condition.value(QStringLiteral("entity")).toString();
        bool ok = false;
        const double value = entityState(entityId).toDouble(&ok);
        if (!ok)
            return false;
        if (condition.contains(QStringLiteral("above"))
                && value <= condition.value(QStringLiteral("above")).toDouble())
            return false;
        if (condition.contains(QStringLiteral("below"))
                && value >= condition.value(QStringLiteral("below")).toDouble())
            return false;
        return true;
    }

    if (type == QLatin1String("state") || type.isEmpty()) {
        const QString entityId = condition.value(QStringLiteral("entity")).toString();
        if (entityId.isEmpty())
            return true;
        const QString state = entityState(entityId);
        if (condition.contains(QStringLiteral("state_not"))) {
            const QStringList notStates = stringListOf(condition.value(QStringLiteral("state_not")));
            return !notStates.contains(state);
        }
        if (condition.contains(QStringLiteral("state"))) {
            const QStringList states = stringListOf(condition.value(QStringLiteral("state")));
            return states.contains(state);
        }
        return isOn(entityId);
    }

    if (type == QLatin1String("template")) {
        // Templates are rendered asynchronously; treat missing as visible.
        return true;
    }

    return true;
}

QVariantList LovelaceCoordinator::filterEntities(const QVariantMap &card) const
{
    QStringList entities = stringListOf(card.value(QStringLiteral("entities")));
    if (entities.isEmpty()) {
        const QString domain = card.value(QStringLiteral("domain")).toString();
        QHash<QString, QVariantMap>::const_iterator it = m_entities.constBegin();
        for (; it != m_entities.constEnd(); ++it) {
            if (domain.isEmpty() || domainOfEntity(it.key()) == domain)
                entities.append(it.key());
        }
        entities.sort();
    }
    QVariantList out;
    const QVariantList conditions = variantListOf(card.value(QStringLiteral("state_filter")).isValid()
            ? card.value(QStringLiteral("state_filter"))
            : card.value(QStringLiteral("conditions")));
    for (int i = 0; i < entities.size(); ++i) {
        const QString entityId = entities.at(i);
        if (conditions.isEmpty()) {
            out.append(entityId);
            continue;
        }
        bool match = false;
        for (int c = 0; c < conditions.size(); ++c) {
            QVariantMap cond = conditions.at(c).toMap();
            if (cond.isEmpty()) {
                cond.insert(QStringLiteral("state"), conditions.at(c).toString());
            }
            cond.insert(QStringLiteral("entity"), entityId);
            if (evalCondition(cond)) {
                match = true;
                break;
            }
        }
        if (match)
            out.append(entityId);
    }
    return out;
}

QString LovelaceCoordinator::defaultActionType(const QString &entityId, bool icon) const
{
    if (icon && isToggleable(entityId))
        return QStringLiteral("toggle");
    if (domainOfEntity(entityId) == QLatin1String("scene")
            || domainOfEntity(entityId) == QLatin1String("script")
            || domainOfEntity(entityId) == QLatin1String("button")
            || domainOfEntity(entityId) == QLatin1String("input_button"))
        return QStringLiteral("toggle");
    return QStringLiteral("more-info");
}

void LovelaceCoordinator::handleCardTap(const QVariantMap &card)
{
    QVariantMap action = card.value(QStringLiteral("tap_action")).toMap();
    const QString entityId = card.value(QStringLiteral("entity")).toString();
    if (action.isEmpty()) {
        action.insert(QStringLiteral("action"), defaultActionType(entityId, false));
    }
    performAction(action, entityId);
}

void LovelaceCoordinator::handleCardHold(const QVariantMap &card)
{
    QVariantMap action = card.value(QStringLiteral("hold_action")).toMap();
    const QString entityId = card.value(QStringLiteral("entity")).toString();
    if (action.isEmpty())
        action.insert(QStringLiteral("action"), QStringLiteral("more-info"));
    performAction(action, entityId);
}

void LovelaceCoordinator::handleCardDoubleTap(const QVariantMap &card)
{
    QVariantMap action = card.value(QStringLiteral("double_tap_action")).toMap();
    const QString entityId = card.value(QStringLiteral("entity")).toString();
    if (action.isEmpty())
        return;
    performAction(action, entityId);
}

void LovelaceCoordinator::performAction(const QVariantMap &action, const QString &defaultEntityId)
{
    QString type = action.value(QStringLiteral("action")).toString();
    if (type.isEmpty())
        type = QStringLiteral("more-info");
    if (type == QLatin1String("none") || type == QLatin1String("no-op"))
        return;

    QString entityId = action.value(QStringLiteral("entity")).toString();
    if (entityId.isEmpty())
        entityId = action.value(QStringLiteral("target")).toMap().value(QStringLiteral("entity_id")).toString();
    if (entityId.isEmpty())
        entityId = defaultEntityId;

    if (type == QLatin1String("toggle")) {
        toggle(entityId);
        return;
    }
    if (type == QLatin1String("more-info")) {
        openMoreInfo(entityId);
        return;
    }
    if (type == QLatin1String("navigate")) {
        const QString path = action.value(QStringLiteral("navigation_path")).toString();
        m_pendingNavigate = path;
        emit pendingNavigateChanged();
        return;
    }
    if (type == QLatin1String("url")) {
        m_pendingUrl = action.value(QStringLiteral("url_path")).toString();
        emit pendingUrlChanged();
        return;
    }
    if (type == QLatin1String("call-service") || type == QLatin1String("perform-action")) {
        QString domain = action.value(QStringLiteral("domain")).toString();
        QString service = action.value(QStringLiteral("service")).toString();
        if (service.isEmpty())
            service = action.value(QStringLiteral("perform_action")).toString();
        if (domain.isEmpty() && service.contains(QLatin1Char('.'))) {
            const int dot = service.indexOf(QLatin1Char('.'));
            domain = service.left(dot);
            service = service.mid(dot + 1);
        }
        QVariantMap data = action.value(QStringLiteral("service_data")).toMap();
        if (data.isEmpty())
            data = action.value(QStringLiteral("data")).toMap();
        callService(domain, service, data, entityId);
        return;
    }
    if (type == QLatin1String("assist")) {
        openWebPath(QStringLiteral("/assist"));
        return;
    }
}

void LovelaceCoordinator::toggle(const QString &entityId)
{
    if (entityId.isEmpty())
        return;
    const QString domain = domainOfEntity(entityId);
    if (domain == QLatin1String("scene") || domain == QLatin1String("script")
            || domain == QLatin1String("button") || domain == QLatin1String("input_button")) {
        callService(domain, QStringLiteral("turn_on"), QVariantMap(), entityId);
        return;
    }
    if (domain == QLatin1String("lock")) {
        callService(domain, isOn(entityId) ? QStringLiteral("lock") : QStringLiteral("unlock"),
                    QVariantMap(), entityId);
        return;
    }
    if (domain == QLatin1String("cover")) {
        callService(domain, isOn(entityId) ? QStringLiteral("close_cover") : QStringLiteral("open_cover"),
                    QVariantMap(), entityId);
        return;
    }
    if (domain == QLatin1String("valve")) {
        callService(domain, isOn(entityId) ? QStringLiteral("close_valve") : QStringLiteral("open_valve"),
                    QVariantMap(), entityId);
        return;
    }
    callService(domain, QStringLiteral("toggle"), QVariantMap(), entityId);
}

void LovelaceCoordinator::callService(const QString &domain,
                                      const QString &service,
                                      const QVariantMap &data,
                                      const QString &entityId)
{
    if (!m_socket || domain.isEmpty() || service.isEmpty())
        return;
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("call_service"));
    msg.insert(QStringLiteral("domain"), domain);
    msg.insert(QStringLiteral("service"), service);
    QVariantMap serviceData = data;
    if (!entityId.isEmpty() && !serviceData.contains(QStringLiteral("entity_id")))
        serviceData.insert(QStringLiteral("entity_id"), entityId);
    if (!serviceData.isEmpty())
        msg.insert(QStringLiteral("service_data"), QJsonObject::fromVariantMap(serviceData));
    if (!entityId.isEmpty()) {
        QJsonObject target;
        target.insert(QStringLiteral("entity_id"), entityId);
        msg.insert(QStringLiteral("target"), target);
    }
    m_socket->sendCommand(msg);
}

void LovelaceCoordinator::openMoreInfo(const QString &entityId)
{
    if (entityId.isEmpty())
        return;
    m_pendingMoreInfo = entityId;
    emit pendingMoreInfoChanged();
}

void LovelaceCoordinator::openWebPath(const QString &path)
{
    m_pendingWebPath = path;
    emit pendingWebPathChanged();
}

void LovelaceCoordinator::clearPendingNavigate()
{
    if (m_pendingNavigate.isEmpty())
        return;
    m_pendingNavigate.clear();
    emit pendingNavigateChanged();
}

void LovelaceCoordinator::clearPendingUrl()
{
    if (m_pendingUrl.isEmpty())
        return;
    m_pendingUrl.clear();
    emit pendingUrlChanged();
}

void LovelaceCoordinator::clearPendingMoreInfo()
{
    if (m_pendingMoreInfo.isEmpty())
        return;
    m_pendingMoreInfo.clear();
    emit pendingMoreInfoChanged();
}

void LovelaceCoordinator::clearPendingWebPath()
{
    if (m_pendingWebPath.isEmpty())
        return;
    m_pendingWebPath.clear();
    emit pendingWebPathChanged();
}

void LovelaceCoordinator::fetchHistory(const QStringList &entityIds, int hours)
{
    if (entityIds.isEmpty() || m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    const QDateTime start = QDateTime::currentDateTimeUtc().addSecs(-hours * 3600);
    QString path = QStringLiteral("/api/history/period/%1")
            .arg(start.toString(Qt::ISODate));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("filter_entity_id"), entityIds.join(QLatin1Char(',')));
    query.addQueryItem(QStringLiteral("minimal_response"), QStringLiteral("true"));
    query.addQueryItem(QStringLiteral("significant_changes_only"), QStringLiteral("false"));
    getJson(path + QLatin1Char('?') + query.toString(QUrl::FullyEncoded),
            QStringLiteral("history"), entityIds.join(QLatin1Char(',')));
}

void LovelaceCoordinator::fetchStatistics(const QStringList &entityIds)
{
    if (!m_socket || entityIds.isEmpty())
        return;
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("recorder/statistics_during_period"));
    msg.insert(QStringLiteral("start_time"),
               QDateTime::currentDateTimeUtc().addDays(-1).toString(Qt::ISODate));
    QJsonArray ids;
    for (int i = 0; i < entityIds.size(); ++i)
        ids.append(entityIds.at(i));
    msg.insert(QStringLiteral("statistic_ids"), ids);
    msg.insert(QStringLiteral("period"), QStringLiteral("hour"));
    m_socket->sendCommand(msg);
}

void LovelaceCoordinator::prefetchMedia(const QString &path)
{
    if (path.isEmpty())
        return;
    if (m_mediaCache.contains(path)) {
        emit mediaCached(path, m_mediaCache.value(path));
        return;
    }
    getMedia(QUrl(resolveMedia(path)), path);
}

QString LovelaceCoordinator::cachedMediaUrl(const QString &path) const
{
    return m_mediaCache.value(path);
}

QString LovelaceCoordinator::cameraPath(const QString &entityId) const
{
    if (entityId.isEmpty())
        return QString();
    return QStringLiteral("/api/camera_proxy/%1").arg(entityId);
}

QString LovelaceCoordinator::resolveMedia(const QString &path) const
{
    if (path.isEmpty())
        return QString();
    if (path.startsWith(QLatin1String("http://"))
            || path.startsWith(QLatin1String("https://"))
            || path.startsWith(QLatin1String("file://")))
        return path;
    QString base = m_baseUrl;
    if (base.endsWith(QLatin1Char('/')))
        base.chop(1);
    if (path.startsWith(QLatin1Char('/')))
        return base + path;
    return base + QLatin1Char('/') + path;
}

void LovelaceCoordinator::renderTemplate(const QString &templateText, const QString &key)
{
    if (!m_socket || templateText.isEmpty())
        return;
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("render_template"));
    msg.insert(QStringLiteral("template"), templateText);
    const int id = m_socket->sendCommand(msg);
    if (id)
        m_templateKeys.insert(id, key);
}

QString LovelaceCoordinator::templateValue(const QString &key) const
{
    return m_templates.value(key);
}

void LovelaceCoordinator::fetchCalendar(const QString &entityId)
{
    if (!m_socket || entityId.isEmpty())
        return;
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("calendar/events"));
    msg.insert(QStringLiteral("entity_id"), entityId);
    msg.insert(QStringLiteral("start"),
               QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    msg.insert(QStringLiteral("end"),
               QDateTime::currentDateTimeUtc().addDays(7).toString(Qt::ISODate));
    const int id = m_socket->sendCommand(msg);
    if (id)
        m_calendarById.insert(id, entityId);
}

void LovelaceCoordinator::fetchTodo(const QString &entityId)
{
    if (!m_socket || entityId.isEmpty())
        return;
    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("todo/item/list"));
    msg.insert(QStringLiteral("entity_id"), entityId);
    const int id = m_socket->sendCommand(msg);
    if (id)
        m_todoById.insert(id, entityId);
}

void LovelaceCoordinator::setTodoItem(const QString &entityId, const QString &item, bool checked)
{
    QVariantMap data;
    data.insert(QStringLiteral("item"), item);
    data.insert(QStringLiteral("status"),
                checked ? QStringLiteral("completed") : QStringLiteral("needs_action"));
    callService(QStringLiteral("todo"), QStringLiteral("update_item"), data, entityId);
}

QVariantList LovelaceCoordinator::calendarEvents(const QString &entityId) const
{
    return m_calendarEvents.value(entityId);
}

QVariantList LovelaceCoordinator::todoItems(const QString &entityId) const
{
    return m_todoItems.value(entityId);
}

void LovelaceCoordinator::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void LovelaceCoordinator::setReady(bool ready)
{
    if (m_ready == ready)
        return;
    m_ready = ready;
    emit readyChanged();
}

void LovelaceCoordinator::setError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

QUrl LovelaceCoordinator::apiUrl(const QString &path) const
{
    if (path.startsWith(QLatin1String("http://")) || path.startsWith(QLatin1String("https://")))
        return QUrl(path);
    QString base = m_baseUrl;
    if (base.endsWith(QLatin1Char('/')))
        base.chop(1);
    if (path.startsWith(QLatin1Char('/')))
        return QUrl(base + path);
    return QUrl(base + QLatin1Char('/') + path);
}

void LovelaceCoordinator::getJson(const QString &path, const QString &kind, const QString &tag)
{
    if (m_accessToken.isEmpty())
        return;
    QNetworkRequest request(apiUrl(path));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    QNetworkReply *reply = m_nam->get(request);
    reply->setProperty("kind", kind);
    reply->setProperty("tag", tag);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(reply, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

void LovelaceCoordinator::getMedia(const QUrl &url, const QString &tag, int redirects)
{
    if (!url.isValid() || tag.isEmpty())
        return;

    QNetworkRequest request(url);
    request.setRawHeader("Accept", "image/*,*/*;q=0.8");
    request.setRawHeader("User-Agent", kClientName);

    const QUrl homeAssistantUrl(m_baseUrl);
    const bool sameOrigin = url.scheme().compare(homeAssistantUrl.scheme(), Qt::CaseInsensitive) == 0
            && url.host().compare(homeAssistantUrl.host(), Qt::CaseInsensitive) == 0
            && url.port(url.scheme() == QLatin1String("https") ? 443 : 80)
               == homeAssistantUrl.port(homeAssistantUrl.scheme() == QLatin1String("https") ? 443 : 80);
    if (sameOrigin && !m_accessToken.isEmpty())
        request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());

    QNetworkReply *reply = m_nam->get(request);
    reply->setProperty("kind", QStringLiteral("media"));
    reply->setProperty("tag", tag);
    reply->setProperty("redirects", redirects);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(reply, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

void LovelaceCoordinator::postJson(const QString &path, const QJsonObject &body,
                                   const QString &kind, const QString &tag)
{
    if (m_accessToken.isEmpty())
        return;
    QNetworkRequest request(apiUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    QNetworkReply *reply = m_nam->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    reply->setProperty("kind", kind);
    reply->setProperty("tag", tag);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    connect(reply, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

void LovelaceCoordinator::onSslErrors(const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (m_ignoreSslErrors && reply)
        reply->ignoreSslErrors();
}

QString LovelaceCoordinator::mediaCachePath(const QString &path) const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
            + QStringLiteral("/hass-media");
    QDir().mkpath(dir);
    const QByteArray hash = QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1).toHex();
    return dir + QLatin1Char('/') + QString::fromLatin1(hash) + QStringLiteral(".png");
}

void LovelaceCoordinator::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;
    reply->deleteLater();
    const QString kind = reply->property("kind").toString();
    const QString tag = reply->property("tag").toString();
    const QByteArray data = reply->readAll();
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Helmsman lovelace:" << kind << "failed" << reply->errorString();
        return;
    }
    if (kind == QLatin1String("media")) {
        const QUrl redirect = reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
        if (redirect.isValid()) {
            const int redirects = reply->property("redirects").toInt();
            if (redirects >= 5) {
                qWarning() << "Helmsman lovelace: media redirect limit reached for" << tag;
                return;
            }
            getMedia(reply->url().resolved(redirect), tag, redirects + 1);
            return;
        }

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status != 0 && (status < 200 || status >= 300)) {
            qWarning() << "Helmsman lovelace: media HTTP" << status << "for" << tag;
            return;
        }

        const QImage image = QImage::fromData(data);
        if (image.isNull()) {
            qWarning() << "Helmsman lovelace: invalid image response for" << tag
                       << "content-type=" << reply->header(QNetworkRequest::ContentTypeHeader).toString()
                       << "bytes=" << data.size();
            return;
        }

        const QString filePath = mediaCachePath(tag);
        if (!image.save(filePath, "PNG")) {
            qWarning() << "Helmsman lovelace: failed to cache image for" << tag;
            return;
        }
        const QString url = QStringLiteral("file://") + filePath;
        m_mediaCache.insert(tag, url);
        emit mediaCached(tag, url);
        return;
    }
    if (kind == QLatin1String("history")) {
        const QJsonDocument doc = QJsonDocument::fromJson(data);
        const QJsonArray series = doc.array();
        for (int i = 0; i < series.size(); ++i) {
            const QJsonArray points = series.at(i).toArray();
            QVariantList out;
            QString entityId;
            for (int p = 0; p < points.size(); ++p) {
                const QJsonObject obj = points.at(p).toObject();
                if (entityId.isEmpty())
                    entityId = obj.value(QStringLiteral("entity_id")).toString();
                QVariantMap point;
                QString lastChanged = obj.value(QStringLiteral("last_changed")).toString();
                if (lastChanged.isEmpty())
                    lastChanged = obj.value(QStringLiteral("lu")).toString();
                point.insert(QStringLiteral("last_changed"), lastChanged);
                QString state = obj.value(QStringLiteral("state")).toString();
                if (state.isEmpty())
                    state = obj.value(QStringLiteral("s")).toString();
                point.insert(QStringLiteral("state"), state);
                out.append(point);
            }
            if (entityId.isEmpty() && i < tag.split(QLatin1Char(',')).size())
                entityId = tag.split(QLatin1Char(',')).at(i);
            emit historyReady(entityId, out);
        }
        return;
    }
}
