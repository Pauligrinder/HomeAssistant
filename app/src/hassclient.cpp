#include "hassclient.h"
#include "hasspushchannel.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QSettings>
#include <QUrl>
#include <QDebug>
#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QUuid>
#include <QSysInfo>
#include <QHostInfo>
#include <QTimer>

namespace {

const char *kClientName = "Helmsman";
const int kDefaultHttpPort = 80;
const int kDefaultHttpsPort = 443;

QString canonicalClientId(const QString &baseUrl)
{
    QString url = baseUrl.trimmed();
    if (url.isEmpty())
        return QString();
    if (!url.endsWith(QLatin1Char('/')))
        url.append(QLatin1Char('/'));
    return url;
}

// Ensure instance URLs always carry an explicit scheme so switching between
// http (LAN) and https (remote) cannot inherit the previous useSsl flag.
QString normalizeInstanceUrl(const QString &input, bool defaultSsl)
{
    QString value = input.trimmed();
    if (value.isEmpty())
        return value;
    if (value.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive)
            || value.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)) {
        return value;
    }
    return (defaultSsl ? QStringLiteral("https://") : QStringLiteral("http://")) + value;
}

QString jsonErrorMessage(const QByteArray &data, const QString &fallback)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject())
        return fallback;
    const QJsonObject obj = doc.object();
    if (obj.contains(QStringLiteral("error_description")))
        return obj.value(QStringLiteral("error_description")).toString();
    if (obj.contains(QStringLiteral("message")))
        return obj.value(QStringLiteral("message")).toString();
    if (obj.contains(QStringLiteral("error"))) {
        const QJsonValue err = obj.value(QStringLiteral("error"));
        if (err.isString())
            return err.toString();
    }
    return fallback;
}

QVariantMap jsonObjectToMap(const QJsonObject &obj)
{
    QVariantMap map;
    for (auto it = obj.begin(); it != obj.end(); ++it)
        map.insert(it.key(), it.value().toVariant());
    return map;
}

bool parseEndpointSpec(const QString &endpoint, bool defaultSsl,
                       bool *ssl, QString *host, int *port, QString *error)
{
    QString raw = endpoint.trimmed();
    if (raw.isEmpty()) {
        *error = QStringLiteral("Enter an IP address or hostname");
        return false;
    }

    bool useSsl = defaultSsl;
    if (raw.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive)) {
        useSsl = true;
        raw = raw.mid(8);
    } else if (raw.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)) {
        useSsl = false;
        raw = raw.mid(7);
    }

    if (raw.endsWith(QLatin1Char('/')))
        raw.chop(1);

    const int slash = raw.indexOf(QLatin1Char('/'));
    if (slash >= 0)
        raw = raw.left(slash);

    QString parsedHost;
    int parsedPort = useSsl ? kDefaultHttpsPort : kDefaultHttpPort;

    if (raw.startsWith(QLatin1Char('['))) {
        const int close = raw.indexOf(QLatin1Char(']'));
        if (close < 0) {
            *error = QStringLiteral("Invalid IPv6 address");
            return false;
        }
        parsedHost = raw.mid(1, close - 1);
        if (close + 1 < raw.size() && raw.at(close + 1) == QLatin1Char(':'))
            parsedPort = raw.mid(close + 2).toInt();
    } else {
        const int colon = raw.lastIndexOf(QLatin1Char(':'));
        if (colon > 0 && raw.indexOf(QLatin1Char(':')) == colon) {
            parsedHost = raw.left(colon);
            parsedPort = raw.mid(colon + 1).toInt();
        } else {
            parsedHost = raw;
        }
    }

    if (parsedHost.isEmpty() || parsedPort <= 0 || parsedPort > 65535) {
        *error = QStringLiteral("Could not parse host or port");
        return false;
    }

    *ssl = useSsl;
    *host = parsedHost;
    *port = parsedPort;
    return true;
}

QUrl endpointSpecToUrl(bool ssl, const QString &host, int port, const QString &path)
{
    QUrl url;
    url.setScheme(ssl ? QStringLiteral("https") : QStringLiteral("http"));
    url.setHost(host);
    const int defaultPort = ssl ? kDefaultHttpsPort : kDefaultHttpPort;
    if (port > 0 && port != defaultPort)
        url.setPort(port);
    url.setPath(path);
    return url;
}

QString sessionFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/session.json");
}

QString cacheDirectory()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    return dir;
}

QString snapshotMetaPath()
{
    return cacheDirectory() + QStringLiteral("/dashboard-snapshot.url");
}

} // namespace

HassClient::HassClient(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_pushChannel(new HassPushChannel(this))
    , m_pendingKind(RequestNone)
    , m_pendingReply(nullptr)
    , m_busy(false)
    , m_connected(false)
    , m_loggedIn(false)
    , m_needsOtp(false)
    , m_useSsl(false)
    , m_ignoreSslErrors(false)
    , m_usingInternalUrl(true)
    , m_restoringSession(false)
    , m_testingConnection(false)
    , m_testIgnoreSslErrors(false)
    , m_pendingPushAfterRefresh(false)
    , m_pushAuthRetries(0)
    , m_port(kDefaultHttpPort)
    , m_testReply(nullptr)
{
    m_endpointDebounceTimer.setSingleShot(true);
    m_endpointDebounceTimer.setInterval(1500);
    connect(&m_endpointDebounceTimer, SIGNAL(timeout()),
            this, SLOT(onEndpointDebounceTimeout()));

    connect(m_nam, SIGNAL(sslErrors(QNetworkReply*,QList<QSslError>)),
            this, SLOT(onSslErrors(QNetworkReply*,QList<QSslError>)));
    connect(m_pushChannel, SIGNAL(connectedChanged()),
            this, SLOT(onPushConnectedChanged()));
    connect(m_pushChannel, SIGNAL(authenticationFailed(QString)),
            this, SLOT(onPushAuthenticationFailed(QString)));
    connect(m_pushChannel, SIGNAL(notificationReceived(QString,QString,QVariantMap)),
            this, SLOT(onPushNotificationReceived(QString,QString,QVariantMap)));

    m_authClientId = QString();
    loadSession();
}

HassClient::~HassClient()
{
}

QString HassClient::appVersion() const
{
    return QStringLiteral(APP_VERSION);
}

bool HassClient::busy() const { return m_busy; }
bool HassClient::connected() const { return m_connected; }
bool HassClient::loggedIn() const { return m_loggedIn; }
bool HassClient::needsOtp() const { return m_needsOtp; }
QString HassClient::errorMessage() const { return m_errorMessage; }
QString HassClient::statusText() const { return m_statusText; }
QString HassClient::host() const { return m_host; }
int HassClient::port() const { return m_port; }
bool HassClient::useSsl() const { return m_useSsl; }
bool HassClient::ignoreSslErrors() const { return m_ignoreSslErrors; }
QString HassClient::username() const { return m_username; }
QString HassClient::instanceName() const { return m_instanceName; }
QString HassClient::haVersion() const { return m_haVersion; }
QString HassClient::otpHint() const { return m_otpHint; }
QString HassClient::baseUrl() const { return m_baseUrl; }
QString HassClient::accessToken() const { return m_accessToken; }
QString HassClient::refreshToken() const { return m_refreshToken; }
QString HassClient::authClientId() const { return clientId(); }
qint64 HassClient::accessExpiresAtMs() const { return m_accessExpiresAt.toMSecsSinceEpoch(); }
bool HassClient::restoringSession() const { return m_restoringSession; }
bool HassClient::testingConnection() const { return m_testingConnection; }
QString HassClient::internalUrl() const { return m_internalUrl; }
QString HassClient::externalUrl() const { return m_externalUrl; }
QString HassClient::homeWifiSsid() const { return m_homeWifiSsid; }
QString HassClient::currentWifiSsid() const { return m_currentWifiSsid; }
bool HassClient::usingInternalUrl() const { return m_usingInternalUrl; }
QString HassClient::webhookId() const { return m_webhookId; }
QString HassClient::deviceName() const { return m_deviceName; }
bool HassClient::mobileAppRegistered() const { return !m_webhookId.isEmpty(); }
bool HassClient::pushConnected() const { return m_pushChannel && m_pushChannel->connected(); }

QString HassClient::dashboardSnapshotPath() const
{
    return cacheDirectory() + QStringLiteral("/dashboard-snapshot.png");
}

void HassClient::rememberDashboardSnapshot(const QString &baseUrl)
{
    QSaveFile file(snapshotMetaPath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return;
    file.write(baseUrl.toUtf8());
    file.commit();
}

bool HassClient::dashboardSnapshotMatches(const QString &baseUrl) const
{
    if (baseUrl.isEmpty() || !QFile::exists(dashboardSnapshotPath()))
        return false;
    QFile file(snapshotMetaPath());
    if (!file.open(QIODevice::ReadOnly))
        return false;
    return QString::fromUtf8(file.readAll()).trimmed() == baseUrl.trimmed();
}

void HassClient::clearDashboardSnapshot()
{
    QFile::remove(dashboardSnapshotPath());
    QFile::remove(snapshotMetaPath());
}

void HassClient::setHost(const QString &host)
{
    if (m_host == host)
        return;
    m_host = host;
    rebuildBaseUrl();
    emit hostChanged();
}

void HassClient::setPort(int port)
{
    if (m_port == port)
        return;
    m_port = port;
    rebuildBaseUrl();
    emit portChanged();
}

void HassClient::setUseSsl(bool useSsl)
{
    if (m_useSsl == useSsl)
        return;
    m_useSsl = useSsl;
    rebuildBaseUrl();
    emit useSslChanged();
}

void HassClient::setIgnoreSslErrors(bool ignore)
{
    if (m_ignoreSslErrors == ignore)
        return;
    m_ignoreSslErrors = ignore;
    emit ignoreSslErrorsChanged();
    if (m_loggedIn)
        startPushChannel();
}

void HassClient::setInternalUrl(const QString &url)
{
    if (m_internalUrl == url)
        return;
    m_internalUrl = url;
    emit internalUrlChanged();
}

void HassClient::setExternalUrl(const QString &url)
{
    if (m_externalUrl == url)
        return;
    m_externalUrl = url;
    emit externalUrlChanged();
}

void HassClient::setHomeWifiSsid(const QString &ssid)
{
    if (m_homeWifiSsid == ssid)
        return;
    m_homeWifiSsid = ssid;
    emit homeWifiSsidChanged();
}

void HassClient::setUsingInternalUrl(bool usingInternal)
{
    if (m_usingInternalUrl == usingInternal)
        return;
    m_usingInternalUrl = usingInternal;
    emit usingInternalUrlChanged();
}

void HassClient::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void HassClient::setError(const QString &message)
{
    if (m_errorMessage != message) {
        m_errorMessage = message;
        emit errorMessageChanged();
    }
}

void HassClient::clearError()
{
    setError(QString());
}

void HassClient::setStatus(const QString &text)
{
    if (m_statusText == text)
        return;
    m_statusText = text;
    emit statusTextChanged();
}

void HassClient::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    emit connectedChanged();
}

void HassClient::setLoggedIn(bool loggedIn)
{
    if (m_loggedIn == loggedIn)
        return;
    m_loggedIn = loggedIn;
    emit loggedInChanged();
}

void HassClient::setNeedsOtp(bool needsOtp)
{
    if (m_needsOtp == needsOtp)
        return;
    m_needsOtp = needsOtp;
    emit needsOtpChanged();
}

void HassClient::setRestoringSession(bool restoring)
{
    if (m_restoringSession == restoring)
        return;
    m_restoringSession = restoring;
    emit restoringSessionChanged();
}

void HassClient::rebuildBaseUrl()
{
    QString host = m_host.trimmed();
    if (host.startsWith(QLatin1Char('[')) && host.endsWith(QLatin1Char(']')))
        host = host.mid(1, host.length() - 2);

    QUrl url;
    url.setScheme(m_useSsl ? QStringLiteral("https") : QStringLiteral("http"));
    url.setHost(host);
    const int defaultPort = m_useSsl ? kDefaultHttpsPort : kDefaultHttpPort;
    if (m_port > 0 && m_port != defaultPort)
        url.setPort(m_port);

    const QString next = url.toString();
    if (m_baseUrl == next)
        return;
    m_baseUrl = next;
    emit baseUrlChanged();
}

QUrl HassClient::apiUrl(const QString &path) const
{
    QUrl url(m_baseUrl);
    url.setPath(path);
    return url;
}

QString HassClient::clientId() const
{
    if (!m_authClientId.isEmpty())
        return m_authClientId;
    return canonicalClientId(m_baseUrl);
}

void HassClient::loadSession()
{
    const QString path = sessionFilePath();
    QFile file(path);
    QJsonObject obj;

    if (file.exists() && file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject())
            obj = doc.object();
    }

    QSettings legacy;

    // Migrate from older QSettings-based storage if needed.
    if (obj.isEmpty()) {
        if (!legacy.value(QStringLiteral("refreshToken")).toString().isEmpty()
                || !legacy.value(QStringLiteral("host")).toString().isEmpty()) {
            obj.insert(QStringLiteral("host"), legacy.value(QStringLiteral("host")).toString());
            obj.insert(QStringLiteral("port"), legacy.value(QStringLiteral("port"), kDefaultHttpPort).toInt());
            obj.insert(QStringLiteral("useSsl"), legacy.value(QStringLiteral("useSsl"), false).toBool());
            obj.insert(QStringLiteral("ignoreSslErrors"),
                       legacy.value(QStringLiteral("ignoreSslErrors"), false).toBool());
            obj.insert(QStringLiteral("username"), legacy.value(QStringLiteral("username")).toString());
            obj.insert(QStringLiteral("refreshToken"),
                       legacy.value(QStringLiteral("refreshToken")).toString());
            obj.insert(QStringLiteral("accessToken"),
                       legacy.value(QStringLiteral("accessToken")).toString());
            obj.insert(QStringLiteral("accessExpiresAt"),
                       legacy.value(QStringLiteral("accessExpiresAt"), 0).toLongLong());
            obj.insert(QStringLiteral("instanceName"),
                       legacy.value(QStringLiteral("instanceName")).toString());
            obj.insert(QStringLiteral("haVersion"),
                       legacy.value(QStringLiteral("haVersion")).toString());
            obj.insert(QStringLiteral("internalUrl"),
                       legacy.value(QStringLiteral("internalUrl")).toString());
            obj.insert(QStringLiteral("externalUrl"),
                       legacy.value(QStringLiteral("externalUrl")).toString());
            obj.insert(QStringLiteral("homeWifiSsid"),
                       legacy.value(QStringLiteral("homeWifiSsid")).toString());
            obj.insert(QStringLiteral("authClientId"),
                       legacy.value(QStringLiteral("authClientId")).toString());
        }
    }

    m_host = obj.value(QStringLiteral("host")).toString();
    m_port = obj.value(QStringLiteral("port")).toInt();
    if (m_port <= 0)
        m_port = kDefaultHttpPort;
    m_useSsl = obj.value(QStringLiteral("useSsl")).toBool();
    m_ignoreSslErrors = obj.value(QStringLiteral("ignoreSslErrors")).toBool();
    m_username = obj.value(QStringLiteral("username")).toString();
    m_refreshToken = obj.value(QStringLiteral("refreshToken")).toString();
    m_accessToken = obj.value(QStringLiteral("accessToken")).toString();
    m_accessExpiresAt = QDateTime::fromMSecsSinceEpoch(
                obj.value(QStringLiteral("accessExpiresAt")).toVariant().toLongLong(),
                Qt::UTC);
    m_instanceName = obj.value(QStringLiteral("instanceName")).toString();
    m_haVersion = obj.value(QStringLiteral("haVersion")).toString();
    m_internalUrl = obj.value(QStringLiteral("internalUrl")).toString();
    m_externalUrl = obj.value(QStringLiteral("externalUrl")).toString();
    m_homeWifiSsid = obj.value(QStringLiteral("homeWifiSsid")).toString();
    m_authClientId = obj.value(QStringLiteral("authClientId")).toString();
    m_deviceId = obj.value(QStringLiteral("deviceId")).toString();
    m_deviceName = obj.value(QStringLiteral("deviceName")).toString();
    m_webhookId = obj.value(QStringLiteral("webhookId")).toString();
    m_webhookSecret = obj.value(QStringLiteral("webhookSecret")).toString();
    m_cloudhookUrl = obj.value(QStringLiteral("cloudhookUrl")).toString();
    m_remoteUiUrl = obj.value(QStringLiteral("remoteUiUrl")).toString();

    m_internalUrl = normalizeInstanceUrl(m_internalUrl, false);
    m_externalUrl = normalizeInstanceUrl(m_externalUrl, true);

    rebuildBaseUrl();

    if (m_authClientId.isEmpty())
        m_authClientId = canonicalClientId(m_baseUrl);

    ensureDeviceId();
    ensureDeviceName();

    if (m_internalUrl.isEmpty() && !m_host.isEmpty())
        m_internalUrl = m_baseUrl;

    // Recover a refresh token left only in legacy QSettings.
    if (m_refreshToken.isEmpty()) {
        const QString legacyRefresh = legacy.value(QStringLiteral("refreshToken")).toString();
        if (!legacyRefresh.isEmpty())
            m_refreshToken = legacyRefresh;
    }
    if (m_accessToken.isEmpty()) {
        const QString legacyAccess = legacy.value(QStringLiteral("accessToken")).toString();
        if (!legacyAccess.isEmpty())
            m_accessToken = legacyAccess;
    }

    qWarning() << "Helmsman: session loaded from" << path
               << "host=" << m_host
               << "refreshLen=" << m_refreshToken.size()
               << "clientId=" << m_authClientId;

    if (!m_refreshToken.isEmpty() || !m_host.isEmpty())
        persistSession();
}

bool HassClient::parseEndpoint(const QString &endpoint, QString *error)
{
    bool ssl = m_useSsl;
    QString host;
    int port = kDefaultHttpPort;
    if (!parseEndpointSpec(endpoint, m_useSsl, &ssl, &host, &port, error))
        return false;

    setUseSsl(ssl);
    setHost(host);
    setPort(port);
    rebuildBaseUrl();
    return true;
}

void HassClient::watch(QNetworkReply *reply, RequestKind kind, bool busy)
{
    if (m_pendingReply) {
        m_pendingReply->disconnect(this);
        m_pendingReply->abort();
        m_pendingReply->deleteLater();
    }
    m_pendingKind = kind;
    m_pendingReply = reply;
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    if (busy)
        setBusy(true);
}

void HassClient::get(const QString &path, RequestKind kind)
{
    QNetworkRequest request(apiUrl(path));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    if (!m_accessToken.isEmpty()
            && (kind == RequestConfig || kind == RequestMobileRegister)) {
        request.setRawHeader("Authorization",
                             QByteArray("Bearer ") + m_accessToken.toUtf8());
    }
    watch(m_nam->get(request), kind);
}

void HassClient::postJson(const QString &path, const QJsonObject &body, RequestKind kind)
{
    QNetworkRequest request(apiUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    if (!m_accessToken.isEmpty()
            && (kind == RequestConfig || kind == RequestMobileRegister)) {
        request.setRawHeader("Authorization",
                             QByteArray("Bearer ") + m_accessToken.toUtf8());
    }
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    watch(m_nam->post(request, payload), kind);
}

void HassClient::postForm(const QString &path, const QUrlQuery &form, RequestKind kind, bool busy)
{
    QNetworkRequest request(apiUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    watch(m_nam->post(request, form.toString(QUrl::FullyEncoded).toUtf8()), kind, busy);
}

void HassClient::onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    if (reply == m_testReply && m_testIgnoreSslErrors)
        reply->ignoreSslErrors();
    else if (m_ignoreSslErrors)
        reply->ignoreSslErrors();
}

void HassClient::cancelRestore()
{
    if (m_pendingReply) {
        m_pendingReply->disconnect(this);
        m_pendingReply->abort();
        m_pendingReply->deleteLater();
        m_pendingReply = nullptr;
        m_pendingKind = RequestNone;
    }
    m_pendingPushAfterRefresh = false;
    setBusy(false);
    setRestoringSession(false);
    setStatus(QStringLiteral("Restore cancelled"));
}

void HassClient::testEndpoint(const QString &endpoint, bool ignoreSslErrors)
{
    if (m_testReply) {
        m_testReply->disconnect(this);
        m_testReply->abort();
        m_testReply->deleteLater();
        m_testReply = nullptr;
    }

    const QString normalized = normalizeInstanceUrl(endpoint, endpoint.startsWith(
            QStringLiteral("https://"), Qt::CaseInsensitive));

    QString parseError;
    bool ssl = false;
    QString host;
    int port = kDefaultHttpPort;
    if (!parseEndpointSpec(normalized, false, &ssl, &host, &port, &parseError)) {
        emit connectionTestFinished(endpoint, false, parseError);
        return;
    }

    m_testEndpoint = endpoint;
    m_testIgnoreSslErrors = ignoreSslErrors;

    QNetworkRequest request(endpointSpecToUrl(ssl, host, port,
                                              QStringLiteral("/auth/providers")));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);

    m_testingConnection = true;
    emit testingConnectionChanged();

    m_testReply = m_nam->get(request);
    connect(m_testReply, SIGNAL(finished()), this, SLOT(onTestReplyFinished()));
}

void HassClient::onTestReplyFinished()
{
    QNetworkReply *reply = m_testReply;
    if (!reply)
        return;

    m_testReply = nullptr;
    const QString endpoint = m_testEndpoint;
    m_testEndpoint.clear();
    m_testingConnection = false;
    emit testingConnectionChanged();

    const QByteArray data = reply->readAll();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError netError = reply->error();
    const QString netErrorString = reply->errorString();
    reply->deleteLater();

    if (netError != QNetworkReply::NoError && status == 0) {
        emit connectionTestFinished(endpoint, false,
                                    QStringLiteral("Could not reach server (%1)").arg(netErrorString));
        return;
    }

    if (status == 200) {
        emit connectionTestFinished(endpoint, true,
                                    QStringLiteral("OK — Home Assistant responded"));
        return;
    }

    emit connectionTestFinished(endpoint, false,
                                jsonErrorMessage(data,
                                                 QStringLiteral("Unexpected response (HTTP %1)")
                                                 .arg(status)));
}

void HassClient::restoreSession()
{
    clearError();
    // Apply endpoint selection immediately; cancel any pending Wi‑Fi debounce.
    m_endpointDebounceTimer.stop();

    // Pick http vs https endpoint from the configured URLs before refreshing.
    // Without this, a previous external https session can leave useSsl=true and
    // break restore on a plain http LAN address.
    if (!m_internalUrl.isEmpty() || !m_externalUrl.isEmpty())
        selectEndpointForWifi(m_currentWifiSsid);

    if (m_refreshToken.isEmpty() || m_host.isEmpty()) {
        setRestoringSession(false);
        setStatus(m_refreshToken.isEmpty()
                  ? QStringLiteral("Not connected")
                  : QStringLiteral("Saved session is incomplete"));
        emit restoreFinished(false);
        return;
    }

    setRestoringSession(true);

    // Reuse a still-valid access token without hitting the network.
    const qint64 msLeft = QDateTime::currentDateTimeUtc().msecsTo(m_accessExpiresAt.toUTC());
    if (!m_accessToken.isEmpty() && msLeft > 60 * 1000) {
        setConnected(true);
        setStatus(QStringLiteral("Restoring session..."));
        fetchConfig();
        return;
    }

    setStatus(QStringLiteral("Restoring session..."));
    QUrlQuery form;
    form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    form.addQueryItem(QStringLiteral("refresh_token"), m_refreshToken);
    form.addQueryItem(QStringLiteral("client_id"), clientId());
    postForm(QStringLiteral("/auth/token"), form, RequestRefresh, false);
}

void HassClient::connectToConfiguredInstance()
{
    m_endpointDebounceTimer.stop();
    if (!m_internalUrl.isEmpty() || !m_externalUrl.isEmpty())
        selectEndpointForWifi(m_currentWifiSsid);

    QString endpoint = m_baseUrl;
    if (endpoint.isEmpty() && !m_internalUrl.isEmpty())
        endpoint = m_internalUrl;
    else if (endpoint.isEmpty() && !m_externalUrl.isEmpty())
        endpoint = m_externalUrl;

    if (endpoint.isEmpty()) {
        const QString message = QStringLiteral("Configure an internal or external URL first");
        setError(message);
        emit loginFailed(message);
        return;
    }

    connectToInstance(endpoint, m_useSsl, m_ignoreSslErrors);
}

void HassClient::connectToInstance(const QString &endpoint, bool useSsl, bool ignoreSslErrors)
{
    clearError();
    setRestoringSession(false);
    setLoggedIn(false);
    setNeedsOtp(false);
    setConnected(false);
    m_flowId.clear();

    // Keep the saved refresh token on disk until a new login succeeds or the
    // user explicitly signs out. Clearing + persistConnectionSettings here was
    // wiping sessions whenever Connect was tapped during restore.
    if (!m_accessToken.isEmpty()) {
        m_accessToken.clear();
        emit accessTokenChanged();
    }
    if (m_accessExpiresAt.isValid()) {
        m_accessExpiresAt = QDateTime();
        emit accessExpiresAtChanged();
    }

    setIgnoreSslErrors(ignoreSslErrors);
    setUseSsl(useSsl);

    const QString previousHost = m_host;

    QString parseError;
    if (!parseEndpoint(endpoint, &parseError)) {
        setError(parseError);
        emit loginFailed(parseError);
        return;
    }

    // parseEndpoint may override SSL if the user pasted a full URL.
    Q_UNUSED(useSsl);

    // New interactive login should bind tokens to this instance URL.
    m_authClientId = canonicalClientId(m_baseUrl);

    // Switching instances invalidates the previous mobile_app registration.
    if (!previousHost.isEmpty() && previousHost.compare(m_host, Qt::CaseInsensitive) != 0)
        clearMobileRegistration();

    if (m_internalUrl.isEmpty())
        setInternalUrl(m_baseUrl);
    persistConnectionSettings();

    setStatus(QStringLiteral("Contacting %1...").arg(m_baseUrl));
    get(QStringLiteral("/auth/providers"), RequestProviders);
}

void HassClient::login(const QString &username, const QString &password)
{
    clearError();
    setNeedsOtp(false);
    if (!m_connected) {
        const QString message = QStringLiteral("Connect to a Home Assistant instance first");
        setError(message);
        emit loginFailed(message);
        return;
    }
    if (username.trimmed().isEmpty() || password.isEmpty()) {
        const QString message = QStringLiteral("Username and password are required");
        setError(message);
        emit loginFailed(message);
        return;
    }

    m_username = username.trimmed();
    emit usernameChanged();

    QJsonObject fields;
    fields.insert(QStringLiteral("username"), m_username);
    fields.insert(QStringLiteral("password"), password);
    fields.insert(QStringLiteral("client_id"), clientId());
    setStatus(QStringLiteral("Signing in..."));
    submitFlow(fields);
}

void HassClient::submitOtp(const QString &code)
{
    clearError();
    const QString trimmed = code.trimmed();
    if (trimmed.isEmpty()) {
        const QString message = QStringLiteral("Enter the verification code");
        setError(message);
        emit loginFailed(message);
        return;
    }
    QJsonObject fields;
    fields.insert(QStringLiteral("code"), trimmed);
    fields.insert(QStringLiteral("client_id"), clientId());
    setStatus(QStringLiteral("Verifying code..."));
    submitFlow(fields);
}

void HassClient::logout()
{
    if (!m_refreshToken.isEmpty() && !m_baseUrl.isEmpty()) {
        QUrlQuery form;
        form.addQueryItem(QStringLiteral("token"), m_refreshToken);
        postForm(QStringLiteral("/auth/revoke"), form, RequestRevoke);
    } else {
        setBusy(false);
    }

    if (!m_accessToken.isEmpty()) {
        m_accessToken.clear();
        emit accessTokenChanged();
    }
    if (!m_refreshToken.isEmpty()) {
        m_refreshToken.clear();
        emit refreshTokenChanged();
    }
    if (m_accessExpiresAt.isValid()) {
        m_accessExpiresAt = QDateTime();
        emit accessExpiresAtChanged();
    }
    m_flowId.clear();
    m_authCode.clear();
    m_pendingPushAfterRefresh = false;
    m_pushAuthRetries = 0;
    m_endpointDebounceTimer.stop();
    stopPushChannel();
    clearPersistedTokens();
    clearDashboardSnapshot();
    setLoggedIn(false);
    setNeedsOtp(false);
    setConnected(false);
    setStatus(QStringLiteral("Signed out"));
}

void HassClient::persistConnectionSettings()
{
    persistSession();
}

void HassClient::persistSession()
{
    if (m_authClientId.isEmpty())
        m_authClientId = canonicalClientId(m_baseUrl);

    QJsonObject obj;
    obj.insert(QStringLiteral("host"), m_host);
    obj.insert(QStringLiteral("port"), m_port);
    obj.insert(QStringLiteral("useSsl"), m_useSsl);
    obj.insert(QStringLiteral("ignoreSslErrors"), m_ignoreSslErrors);
    obj.insert(QStringLiteral("internalUrl"), m_internalUrl);
    obj.insert(QStringLiteral("externalUrl"), m_externalUrl);
    obj.insert(QStringLiteral("homeWifiSsid"), m_homeWifiSsid);
    obj.insert(QStringLiteral("authClientId"), m_authClientId);
    obj.insert(QStringLiteral("username"), m_username);
    obj.insert(QStringLiteral("refreshToken"), m_refreshToken);
    obj.insert(QStringLiteral("accessToken"), m_accessToken);
    obj.insert(QStringLiteral("accessExpiresAt"),
               static_cast<double>(m_accessExpiresAt.toMSecsSinceEpoch()));
    obj.insert(QStringLiteral("instanceName"), m_instanceName);
    obj.insert(QStringLiteral("haVersion"), m_haVersion);
    obj.insert(QStringLiteral("deviceId"), m_deviceId);
    obj.insert(QStringLiteral("deviceName"), m_deviceName);
    obj.insert(QStringLiteral("webhookId"), m_webhookId);
    obj.insert(QStringLiteral("webhookSecret"), m_webhookSecret);
    obj.insert(QStringLiteral("cloudhookUrl"), m_cloudhookUrl);
    obj.insert(QStringLiteral("remoteUiUrl"), m_remoteUiUrl);

    const QString path = sessionFilePath();
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "Helmsman: failed to open session file for writing:" << path << file.errorString();
        setError(QStringLiteral("Could not save session"));
        return;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    if (!file.commit()) {
        qWarning() << "Helmsman: failed to commit session file:" << path << file.errorString();
        setError(QStringLiteral("Could not save session"));
        return;
    }

    // Mirror into QSettings as a backup under Sailjail.
    QSettings legacy;
    legacy.setValue(QStringLiteral("host"), m_host);
    legacy.setValue(QStringLiteral("port"), m_port);
    legacy.setValue(QStringLiteral("useSsl"), m_useSsl);
    legacy.setValue(QStringLiteral("ignoreSslErrors"), m_ignoreSslErrors);
    legacy.setValue(QStringLiteral("internalUrl"), m_internalUrl);
    legacy.setValue(QStringLiteral("externalUrl"), m_externalUrl);
    legacy.setValue(QStringLiteral("homeWifiSsid"), m_homeWifiSsid);
    legacy.setValue(QStringLiteral("authClientId"), m_authClientId);
    legacy.setValue(QStringLiteral("username"), m_username);
    legacy.setValue(QStringLiteral("refreshToken"), m_refreshToken);
    legacy.setValue(QStringLiteral("accessToken"), m_accessToken);
    legacy.setValue(QStringLiteral("accessExpiresAt"), m_accessExpiresAt.toMSecsSinceEpoch());
    legacy.setValue(QStringLiteral("instanceName"), m_instanceName);
    legacy.setValue(QStringLiteral("haVersion"), m_haVersion);
    legacy.setValue(QStringLiteral("deviceId"), m_deviceId);
    legacy.setValue(QStringLiteral("deviceName"), m_deviceName);
    legacy.setValue(QStringLiteral("webhookId"), m_webhookId);
    legacy.setValue(QStringLiteral("webhookSecret"), m_webhookSecret);
    legacy.setValue(QStringLiteral("cloudhookUrl"), m_cloudhookUrl);
    legacy.setValue(QStringLiteral("remoteUiUrl"), m_remoteUiUrl);
    legacy.sync();

    qWarning() << "Helmsman: session saved to" << path
               << "refreshLen=" << m_refreshToken.size()
               << "clientId=" << m_authClientId
               << "webhook=" << (!m_webhookId.isEmpty());
}

void HassClient::clearPersistedTokens()
{
    m_accessToken.clear();
    m_refreshToken.clear();
    m_accessExpiresAt = QDateTime();
    persistSession();

    QSettings legacy;
    legacy.remove(QStringLiteral("refreshToken"));
    legacy.remove(QStringLiteral("accessToken"));
    legacy.remove(QStringLiteral("accessExpiresAt"));
    legacy.sync();
}

void HassClient::saveConnectionSettings(const QString &internalUrl,
                                        const QString &externalUrl,
                                        const QString &homeWifiSsid,
                                        bool ignoreSslErrors)
{
    setInternalUrl(normalizeInstanceUrl(internalUrl, false));
    setExternalUrl(normalizeInstanceUrl(externalUrl, true));
    setHomeWifiSsid(homeWifiSsid.trimmed());
    setIgnoreSslErrors(ignoreSslErrors);
    persistConnectionSettings();
    selectEndpointForWifi(m_currentWifiSsid);
}

void HassClient::updateCurrentWifiSsid(const QString &ssid)
{
    if (m_currentWifiSsid != ssid) {
        m_currentWifiSsid = ssid;
        emit currentWifiSsidChanged();
    }
    // Debounce endpoint switches — ConnMan can flap briefly when joining Wi‑Fi
    // or switching between mobile data and WLAN.
    m_pendingEndpointSsid = ssid;
    m_endpointDebounceTimer.start();
}

void HassClient::onEndpointDebounceTimeout()
{
    selectEndpointForWifi(m_pendingEndpointSsid);
}

bool HassClient::accessTokenStillFresh(int minSecondsLeft) const
{
    if (m_accessToken.isEmpty() || !m_accessExpiresAt.isValid())
        return false;
    const qint64 msLeft = QDateTime::currentDateTimeUtc().msecsTo(m_accessExpiresAt.toUTC());
    return msLeft > static_cast<qint64>(minSecondsLeft) * 1000;
}

void HassClient::refreshAccessToken()
{
    if (m_refreshToken.isEmpty() || m_host.isEmpty())
        return;

    QUrlQuery form;
    form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    form.addQueryItem(QStringLiteral("refresh_token"), m_refreshToken);
    form.addQueryItem(QStringLiteral("client_id"), clientId());
    postForm(QStringLiteral("/auth/token"), form, RequestRefresh, false);
}

void HassClient::reconnectPushAfterEndpointChange()
{
    // Always stop first so we do not authenticate against the previous URL
    // (or with a soon-to-expire token) — that shows up in HA as login failures.
    stopPushChannel();

    if (!m_loggedIn || m_webhookId.isEmpty())
        return;

    if (accessTokenStillFresh(120)) {
        startPushChannel();
        return;
    }

    if (m_refreshToken.isEmpty()) {
        qWarning() << "Helmsman: endpoint switched but no refresh token; push left stopped";
        return;
    }

    qWarning() << "Helmsman: refreshing access token after endpoint switch to" << m_baseUrl;
    m_pendingPushAfterRefresh = true;
    refreshAccessToken();
}

bool HassClient::selectEndpointForWifi(const QString &ssid)
{
    const bool ssidKnown = !ssid.trimmed().isEmpty();
    const bool onHomeWifi = ssidKnown
            && !m_homeWifiSsid.isEmpty()
            && ssid.compare(m_homeWifiSsid, Qt::CaseInsensitive) == 0;

    // Prefer the configured URL that matches current Wi‑Fi. When the SSID is
    // still unknown (startup / ConnMan lag), keep the last selected endpoint
    // instead of jumping to external HTTPS while the phone may still be on LAN.
    QString chosen;
    bool defaultSsl = false;
    if (onHomeWifi && !m_internalUrl.isEmpty()) {
        chosen = m_internalUrl;
        defaultSsl = false;
    } else if (ssidKnown && !m_externalUrl.isEmpty()) {
        chosen = m_externalUrl;
        defaultSsl = true;
    } else if (!ssidKnown) {
        if (m_usingInternalUrl && !m_internalUrl.isEmpty()) {
            chosen = m_internalUrl;
            defaultSsl = false;
        } else if (!m_usingInternalUrl && !m_externalUrl.isEmpty()) {
            chosen = m_externalUrl;
            defaultSsl = true;
        } else if (!m_internalUrl.isEmpty()) {
            chosen = m_internalUrl;
            defaultSsl = false;
        } else {
            chosen = m_externalUrl;
            defaultSsl = true;
        }
    } else if (!m_internalUrl.isEmpty()) {
        chosen = m_internalUrl;
        defaultSsl = false;
    } else {
        return false;
    }

    if (chosen.isEmpty())
        return false;

    // Re-normalize so scheme (http vs https) always comes from the URL itself.
    chosen = normalizeInstanceUrl(chosen, defaultSsl);

    QString parseError;
    const QString previousBase = m_baseUrl;
    const bool previousInternal = m_usingInternalUrl;
    if (!parseEndpoint(chosen, &parseError)) {
        setError(parseError);
        return false;
    }

    const QString internalNorm = normalizeInstanceUrl(m_internalUrl, false);
    setUsingInternalUrl(!internalNorm.isEmpty() && chosen == internalNorm);
    persistConnectionSettings();
    if (m_loggedIn && previousBase != m_baseUrl)
        reconnectPushAfterEndpointChange();
    return previousBase != m_baseUrl || previousInternal != m_usingInternalUrl;
}

void HassClient::startLoginFlow()
{
    QJsonArray handler;
    handler.append(m_providerType);
    if (m_providerId.isValid() && !m_providerId.isNull())
        handler.append(QJsonValue::fromVariant(m_providerId));
    else
        handler.append(QJsonValue::Null);

    QJsonObject body;
    body.insert(QStringLiteral("client_id"), clientId());
    body.insert(QStringLiteral("redirect_uri"), clientId());
    body.insert(QStringLiteral("handler"), handler);

    setStatus(QStringLiteral("Starting login..."));
    postJson(QStringLiteral("/auth/login_flow"), body, RequestStartFlow);
}

void HassClient::submitFlow(const QJsonObject &fields)
{
    if (m_flowId.isEmpty()) {
        const QString message = QStringLiteral("Login flow is not ready");
        setError(message);
        emit loginFailed(message);
        return;
    }
    postJson(QStringLiteral("/auth/login_flow/") + m_flowId, fields, RequestSubmitFlow);
}

void HassClient::exchangeCode(const QString &code)
{
    QUrlQuery form;
    form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("authorization_code"));
    form.addQueryItem(QStringLiteral("code"), code);
    form.addQueryItem(QStringLiteral("client_id"), clientId());
    setStatus(QStringLiteral("Fetching tokens..."));
    postForm(QStringLiteral("/auth/token"), form, RequestToken);
}

void HassClient::fetchConfig()
{
    get(QStringLiteral("/api/config"), RequestConfig);
}

void HassClient::applyTokens(const QVariantMap &obj, bool keepRefreshIfMissing)
{
    Q_UNUSED(keepRefreshIfMissing);
    const QString access = obj.value(QStringLiteral("access_token")).toString();
    if (m_accessToken != access) {
        m_accessToken = access;
        emit accessTokenChanged();
    }
    const QString refresh = obj.value(QStringLiteral("refresh_token")).toString();
    if (!refresh.isEmpty()) {
        if (m_refreshToken != refresh) {
            m_refreshToken = refresh;
            emit refreshTokenChanged();
        }
    } else {
        // Never drop a known refresh token just because a response omitted it.
        qWarning() << "Helmsman: token response missing refresh_token; keeping existing token";
    }

    const int expiresIn = obj.value(QStringLiteral("expires_in")).toInt();
    const QDateTime nextExpiresAt = QDateTime::currentDateTimeUtc().addSecs(expiresIn > 0 ? expiresIn : 1800);
    if (m_accessExpiresAt != nextExpiresAt) {
        m_accessExpiresAt = nextExpiresAt;
        emit accessExpiresAtChanged();
    }
}

void HassClient::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    const RequestKind kind = m_pendingKind;
    if (reply == m_pendingReply) {
        m_pendingReply = nullptr;
        m_pendingKind = RequestNone;
    }

    const QByteArray data = reply->readAll();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError netError = reply->error();
    const QString netErrorString = reply->errorString();
    reply->deleteLater();

    if (kind == RequestRevoke) {
        setBusy(false);
        return;
    }

    if (netError != QNetworkReply::NoError && status == 0) {
        setBusy(false);
        const QString message = QStringLiteral("Could not reach %1 (%2)")
                .arg(m_baseUrl, netErrorString);
        if (kind == RequestRefresh && m_pendingPushAfterRefresh) {
            m_pendingPushAfterRefresh = false;
            qWarning() << "Helmsman: endpoint-switch token refresh unreachable:" << message;
            return;
        }
        setError(message);
        setStatus(QStringLiteral("Connection failed"));
        if (kind == RequestRefresh) {
            // Keep tokens on transient network errors so a later launch can retry.
            const qint64 msLeft = QDateTime::currentDateTimeUtc().msecsTo(m_accessExpiresAt.toUTC());
            if (!m_accessToken.isEmpty() && msLeft > 0) {
                setConnected(true);
                setLoggedIn(true);
                setRestoringSession(false);
                emit loginSucceeded();
                emit restoreFinished(true);
            } else {
                setRestoringSession(false);
                emit restoreFinished(false);
            }
        } else {
            emit loginFailed(message);
        }
        return;
    }

    if (kind == RequestProviders) {
        if (status != 200) {
            setBusy(false);
            const QString message = jsonErrorMessage(
                        data, QStringLiteral("This does not look like a Home Assistant instance"));
            setError(message);
            setStatus(QStringLiteral("Connection failed"));
            emit loginFailed(message);
            return;
        }
        handleProviders(data);
        return;
    }

    if (kind == RequestStartFlow || kind == RequestSubmitFlow) {
        if (status != 200) {
            setBusy(false);
            const QString message = jsonErrorMessage(data, QStringLiteral("Login request failed"));
            setError(message);
            emit loginFailed(message);
            return;
        }
        handleFlowStep(data);
        return;
    }

    if (kind == RequestToken || kind == RequestRefresh) {
        if (status != 200) {
            setBusy(false);
            const QString message = jsonErrorMessage(data, QStringLiteral("Token request failed"));
            if (kind == RequestRefresh && m_pendingPushAfterRefresh) {
                // Background refresh after Wi‑Fi/endpoint switch — do not tear down
                // the session or spam the UI. Leave push stopped rather than
                // reconnecting with a token HA already rejected.
                m_pendingPushAfterRefresh = false;
                qWarning() << "Helmsman: endpoint-switch token refresh failed:" << message;
                return;
            }
            setError(message);
            if (kind == RequestRefresh) {
                // Keep tokens so the user can retry. Wiping here forced a full
                // password login whenever HA was briefly unreachable or the
                // client_id did not match yet after an app update.
                setStatus(QStringLiteral("Could not restore session — tap Retry restore"));
                setRestoringSession(false);
                emit restoreFinished(false);
            } else {
                emit loginFailed(message);
            }
            return;
        }
        handleToken(data, kind == RequestRefresh);
        return;
    }

    if (kind == RequestConfig) {
        if (status != 200) {
            setBusy(false);
            const QString message = jsonErrorMessage(data, QStringLiteral("Logged in, but config could not be loaded"));
            setError(message);
            // Tokens are still valid.
            setLoggedIn(true);
            setConnected(true);
            setRestoringSession(false);
            emit loginSucceeded();
            emit restoreFinished(true);
            ensureMobileAppRegistration();
            return;
        }
        handleConfig(data);
        return;
    }

    if (kind == RequestMobileRegister) {
        setBusy(false);
        if (status != 200 && status != 201) {
            const QString message = jsonErrorMessage(
                        data, QStringLiteral("Mobile app registration failed"));
            qWarning() << "Helmsman: mobile_app registration failed" << status << message;
            return;
        }
        handleMobileRegistration(data);
        return;
    }

    setBusy(false);
}

void HassClient::handleProviders(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    QJsonArray providers;
    if (doc.isArray()) {
        providers = doc.array();
    } else if (doc.isObject()) {
        providers = doc.object().value(QStringLiteral("providers")).toArray();
    }

    if (providers.isEmpty()) {
        setBusy(false);
        const QString message = QStringLiteral("No login providers on this instance");
        setError(message);
        emit loginFailed(message);
        return;
    }

    QJsonObject chosen;
    for (const QJsonValue &value : providers) {
        const QJsonObject obj = value.toObject();
        if (obj.value(QStringLiteral("type")).toString() == QLatin1String("homeassistant")) {
            chosen = obj;
            break;
        }
    }
    if (chosen.isEmpty())
        chosen = providers.at(0).toObject();

    m_providerType = chosen.value(QStringLiteral("type")).toString();
    if (m_providerType.isEmpty())
        m_providerType = QStringLiteral("homeassistant");
    if (chosen.contains(QStringLiteral("id")) && !chosen.value(QStringLiteral("id")).isNull())
        m_providerId = chosen.value(QStringLiteral("id")).toVariant();
    else
        m_providerId = QVariant();

    setConnected(true);
    setStatus(QStringLiteral("Connected to %1").arg(m_baseUrl));
    startLoginFlow();
}

void HassClient::handleFlowStep(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        setBusy(false);
        const QString message = QStringLiteral("Unexpected login response");
        setError(message);
        emit loginFailed(message);
        return;
    }

    const QJsonObject obj = doc.object();
    const QString type = obj.value(QStringLiteral("type")).toString();
    m_flowId = obj.value(QStringLiteral("flow_id")).toString();

    if (type == QLatin1String("abort")) {
        setBusy(false);
        const QString reason = obj.value(QStringLiteral("reason")).toString();
        const QString message = reason.isEmpty()
                ? QStringLiteral("Login was aborted")
                : QStringLiteral("Login aborted: %1").arg(reason);
        setError(message);
        emit loginFailed(message);
        return;
    }

    if (type == QLatin1String("create_entry")) {
        const QString code = obj.value(QStringLiteral("result")).toString();
        if (code.isEmpty()) {
            setBusy(false);
            const QString message = QStringLiteral("Login succeeded but no authorization code was returned");
            setError(message);
            emit loginFailed(message);
            return;
        }
        exchangeCode(code);
        return;
    }

    if (type != QLatin1String("form")) {
        setBusy(false);
        const QString message = QStringLiteral("Unsupported login step: %1").arg(type);
        setError(message);
        emit loginFailed(message);
        return;
    }

    const QJsonObject errors = obj.value(QStringLiteral("errors")).toObject();
    if (!errors.isEmpty()) {
        setBusy(false);
        QString message = errors.value(QStringLiteral("base")).toString();
        if (message == QLatin1String("invalid_auth"))
            message = QStringLiteral("Invalid username or password");
        else if (message == QLatin1String("invalid_code"))
            message = QStringLiteral("Invalid verification code");
        else if (message.isEmpty())
            message = QStringLiteral("Login failed");
        setError(message);
        emit loginFailed(message);
        return;
    }

    const QString stepId = obj.value(QStringLiteral("step_id")).toString();

    if (stepId == QLatin1String("select_mfa_module") || stepId == QLatin1String("select")) {
        QString moduleId;
        const QJsonArray schema = obj.value(QStringLiteral("data_schema")).toArray();
        for (const QJsonValue &fieldVal : schema) {
            const QJsonObject field = fieldVal.toObject();
            const QJsonArray options = field.value(QStringLiteral("options")).toArray();
            for (const QJsonValue &opt : options) {
                QString id;
                if (opt.isArray() && opt.toArray().size() >= 1)
                    id = opt.toArray().at(0).toString();
                else if (opt.isString())
                    id = opt.toString();
                if (id.contains(QStringLiteral("totp"), Qt::CaseInsensitive) || moduleId.isEmpty())
                    moduleId = id;
            }
            const QString name = field.value(QStringLiteral("name")).toString();
            if (!moduleId.isEmpty() && !name.isEmpty()) {
                QJsonObject fields;
                fields.insert(name, moduleId);
                fields.insert(QStringLiteral("client_id"), clientId());
                submitFlow(fields);
                return;
            }
        }
        setBusy(false);
        const QString message = QStringLiteral("Could not select a two-step verification method");
        setError(message);
        emit loginFailed(message);
        return;
    }

    if (stepId == QLatin1String("mfa") || stepId.contains(QStringLiteral("mfa"))) {
        setBusy(false);
        setNeedsOtp(true);
        const QJsonObject placeholders = obj.value(QStringLiteral("description_placeholders")).toObject();
        QString hint = placeholders.value(QStringLiteral("name")).toString();
        if (hint.isEmpty())
            hint = QStringLiteral("Enter the 6-digit code from your authenticator app");
        else
            hint = QStringLiteral("Enter the code from %1").arg(hint);
        if (m_otpHint != hint) {
            m_otpHint = hint;
            emit otpHintChanged();
        }
        setStatus(QStringLiteral("Two-step verification required"));
        emit otpRequired();
        return;
    }

    // init / username+password form
    setBusy(false);
    setStatus(QStringLiteral("Connected. Sign in to continue."));
    emit connectionSucceeded();
}

void HassClient::handleToken(const QByteArray &data, bool fromRefresh)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        setBusy(false);
        const QString message = QStringLiteral("Malformed token response");
        if (fromRefresh && m_pendingPushAfterRefresh) {
            m_pendingPushAfterRefresh = false;
            qWarning() << "Helmsman: endpoint-switch token refresh malformed";
            return;
        }
        setError(message);
        if (fromRefresh) {
            setRestoringSession(false);
            emit restoreFinished(false);
        } else
            emit loginFailed(message);
        return;
    }

    applyTokens(jsonObjectToMap(doc.object()), true);
    if (m_accessToken.isEmpty()) {
        setBusy(false);
        const QString message = QStringLiteral("No access token in response");
        if (fromRefresh && m_pendingPushAfterRefresh) {
            m_pendingPushAfterRefresh = false;
            qWarning() << "Helmsman: endpoint-switch token refresh missing access_token";
            return;
        }
        setError(message);
        if (fromRefresh) {
            setRestoringSession(false);
            emit restoreFinished(false);
        } else
            emit loginFailed(message);
        return;
    }

    if (m_authClientId.isEmpty())
        m_authClientId = canonicalClientId(m_baseUrl);

    // Quiet path: refresh only so the push channel can reconnect after an
    // internal↔external switch (or after auth_invalid). Skip config reload.
    if (fromRefresh && m_pendingPushAfterRefresh) {
        m_pendingPushAfterRefresh = false;
        setBusy(false);
        setConnected(true);
        persistSession();
        qWarning() << "Helmsman: access token refreshed for" << m_baseUrl;
        startPushChannel();
        return;
    }

    setConnected(true);
    persistSession();
    setStatus(QStringLiteral("Loading instance..."));
    fetchConfig();
}

void HassClient::handleConfig(const QByteArray &data)
{
    setBusy(false);
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (doc.isObject()) {
        const QJsonObject obj = doc.object();
        const QString name = obj.value(QStringLiteral("location_name")).toString();
        const QString version = obj.value(QStringLiteral("version")).toString();
        if (m_instanceName != name) {
            m_instanceName = name;
            emit instanceNameChanged();
        }
        if (m_haVersion != version) {
            m_haVersion = version;
            emit haVersionChanged();
        }
    }
    persistSession();
    setNeedsOtp(false);
    setLoggedIn(true);
    setConnected(true);
    setRestoringSession(false);
    setStatus(m_instanceName.isEmpty()
              ? QStringLiteral("Signed in")
              : QStringLiteral("Signed in to %1").arg(m_instanceName));
    emit loginSucceeded();
    emit restoreFinished(true);
    ensureMobileAppRegistration();
}

void HassClient::ensureDeviceId()
{
    if (!m_deviceId.isEmpty())
        return;
    m_deviceId = QUuid::createUuid().toString();
    m_deviceId.remove(QLatin1Char('{'));
    m_deviceId.remove(QLatin1Char('}'));
}

void HassClient::ensureDeviceName()
{
    if (!m_deviceName.isEmpty())
        return;

    QString host = QHostInfo::localHostName().trimmed();
    if (host.isEmpty() || host == QLatin1String("localhost"))
        host = QStringLiteral("Sailfish");
    m_deviceName = QStringLiteral("Helmsman (%1)").arg(host);
    emit deviceNameChanged();
}

void HassClient::ensureMobileAppRegistration()
{
    if (!m_loggedIn || m_accessToken.isEmpty())
        return;

    if (!m_webhookId.isEmpty()) {
        startPushChannel();
        return;
    }

    registerMobileApp();
}

void HassClient::registerMobileApp()
{
    ensureDeviceId();
    ensureDeviceName();

    QJsonObject appData;
    appData.insert(QStringLiteral("push_websocket_channel"), true);

    QJsonObject body;
    body.insert(QStringLiteral("device_id"), m_deviceId);
    body.insert(QStringLiteral("app_id"), QStringLiteral("harbour.helmsman"));
    body.insert(QStringLiteral("app_name"), QStringLiteral("Helmsman"));
    body.insert(QStringLiteral("app_version"), appVersion());
    body.insert(QStringLiteral("device_name"), m_deviceName);
    body.insert(QStringLiteral("manufacturer"), QStringLiteral("Jolla"));
    body.insert(QStringLiteral("model"), QSysInfo::prettyProductName());
    body.insert(QStringLiteral("os_name"), QStringLiteral("Sailfish OS"));
    body.insert(QStringLiteral("os_version"), QSysInfo::productVersion());
    body.insert(QStringLiteral("supports_encryption"), false);
    body.insert(QStringLiteral("app_data"), appData);

    qWarning() << "Helmsman: registering mobile_app as" << m_deviceName;
    postJson(QStringLiteral("/api/mobile_app/registrations"), body, RequestMobileRegister);
}

void HassClient::handleMobileRegistration(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        qWarning() << "Helmsman: malformed mobile_app registration response";
        return;
    }

    const QJsonObject obj = doc.object();
    const QString webhook = obj.value(QStringLiteral("webhook_id")).toString();
    if (webhook.isEmpty()) {
        qWarning() << "Helmsman: registration response missing webhook_id";
        return;
    }

    const bool wasRegistered = !m_webhookId.isEmpty();
    m_webhookId = webhook;
    m_webhookSecret = obj.value(QStringLiteral("secret")).toString();
    m_cloudhookUrl = obj.value(QStringLiteral("cloudhook_url")).toString();
    m_remoteUiUrl = obj.value(QStringLiteral("remote_ui_url")).toString();
    persistSession();
    if (!wasRegistered)
        emit mobileAppRegisteredChanged();
    emit webhookIdChanged();
    qWarning() << "Helmsman: mobile_app registered, webhook set";
    startPushChannel();
}

void HassClient::clearMobileRegistration()
{
    const bool hadWebhook = !m_webhookId.isEmpty();
    m_webhookId.clear();
    m_webhookSecret.clear();
    m_cloudhookUrl.clear();
    m_remoteUiUrl.clear();
    if (hadWebhook) {
        emit webhookIdChanged();
        emit mobileAppRegisteredChanged();
    }
}

void HassClient::startPushChannel()
{
    if (!m_pushChannel || m_webhookId.isEmpty() || m_accessToken.isEmpty() || m_baseUrl.isEmpty())
        return;
    m_pushChannel->configure(m_baseUrl, m_accessToken, m_webhookId, m_ignoreSslErrors);
    m_pushChannel->start();
}

void HassClient::stopPushChannel()
{
    if (m_pushChannel)
        m_pushChannel->stop();
}

void HassClient::onPushConnectedChanged()
{
    if (m_pushChannel && m_pushChannel->connected())
        m_pushAuthRetries = 0;
    emit pushConnectedChanged();
}

void HassClient::onPushAuthenticationFailed(const QString &message)
{
    qWarning() << "Helmsman: push authentication failed:" << message;
    if (!m_loggedIn || m_refreshToken.isEmpty())
        return;
    if (m_pushAuthRetries >= 1) {
        qWarning() << "Helmsman: not retrying push auth again until next successful connect";
        return;
    }
    if (m_pendingPushAfterRefresh) {
        qWarning() << "Helmsman: token refresh already in flight after push auth failure";
        return;
    }

    ++m_pushAuthRetries;
    m_pendingPushAfterRefresh = true;
    qWarning() << "Helmsman: refreshing access token after push auth_invalid";
    refreshAccessToken();
}

void HassClient::onPushNotificationReceived(const QString &title,
                                            const QString &message,
                                            const QVariantMap &data)
{
    emit notificationReceived(title, message, data);
}
