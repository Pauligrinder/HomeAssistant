#include "hassclient.h"

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

namespace {

const char *kClientName = "Helmsman";

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

} // namespace

HassClient::HassClient(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_pendingKind(RequestNone)
    , m_pendingReply(nullptr)
    , m_busy(false)
    , m_connected(false)
    , m_loggedIn(false)
    , m_needsOtp(false)
    , m_useSsl(false)
    , m_ignoreSslErrors(false)
    , m_port(8123)
{
    connect(m_nam, SIGNAL(sslErrors(QNetworkReply*,QList<QSslError>)),
            this, SLOT(onSslErrors(QNetworkReply*,QList<QSslError>)));

    QSettings settings;
    m_host = settings.value(QStringLiteral("host")).toString();
    m_port = settings.value(QStringLiteral("port"), 8123).toInt();
    m_useSsl = settings.value(QStringLiteral("useSsl"), false).toBool();
    m_ignoreSslErrors = settings.value(QStringLiteral("ignoreSslErrors"), false).toBool();
    m_username = settings.value(QStringLiteral("username")).toString();
    m_refreshToken = settings.value(QStringLiteral("refreshToken")).toString();
    m_accessToken = settings.value(QStringLiteral("accessToken")).toString();
    m_accessExpiresAt = QDateTime::fromMSecsSinceEpoch(
                settings.value(QStringLiteral("accessExpiresAt"), 0).toLongLong());
    m_instanceName = settings.value(QStringLiteral("instanceName")).toString();
    m_haVersion = settings.value(QStringLiteral("haVersion")).toString();
    rebuildBaseUrl();
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
qint64 HassClient::accessExpiresAtMs() const { return m_accessExpiresAt.toMSecsSinceEpoch(); }

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

void HassClient::rebuildBaseUrl()
{
    QString host = m_host.trimmed();
    if (host.startsWith(QLatin1Char('[')) && host.endsWith(QLatin1Char(']')))
        host = host.mid(1, host.length() - 2);

    QUrl url;
    url.setScheme(m_useSsl ? QStringLiteral("https") : QStringLiteral("http"));
    url.setHost(host);
    const int defaultPort = m_useSsl ? 443 : 8123;
    if (m_port > 0 && m_port != defaultPort)
        url.setPort(m_port);
    else if (!m_useSsl && m_port == 8123)
        url.setPort(8123);

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
    QString url = m_baseUrl;
    if (!url.endsWith(QLatin1Char('/')))
        url.append(QLatin1Char('/'));
    return url;
}

bool HassClient::parseEndpoint(const QString &endpoint, QString *error)
{
    QString raw = endpoint.trimmed();
    if (raw.isEmpty()) {
        *error = QStringLiteral("Enter an IP address or hostname");
        return false;
    }

    bool ssl = m_useSsl;
    if (raw.startsWith(QStringLiteral("https://"), Qt::CaseInsensitive)) {
        ssl = true;
        raw = raw.mid(8);
    } else if (raw.startsWith(QStringLiteral("http://"), Qt::CaseInsensitive)) {
        ssl = false;
        raw = raw.mid(7);
    }

    if (raw.endsWith(QLatin1Char('/')))
        raw.chop(1);

    const int slash = raw.indexOf(QLatin1Char('/'));
    if (slash >= 0)
        raw = raw.left(slash);

    QString host;
    int port = 8123;

    if (raw.startsWith(QLatin1Char('['))) {
        const int close = raw.indexOf(QLatin1Char(']'));
        if (close < 0) {
            *error = QStringLiteral("Invalid IPv6 address");
            return false;
        }
        host = raw.mid(1, close - 1);
        if (close + 1 < raw.size() && raw.at(close + 1) == QLatin1Char(':'))
            port = raw.mid(close + 2).toInt();
    } else {
        const int colon = raw.lastIndexOf(QLatin1Char(':'));
        if (colon > 0 && raw.indexOf(QLatin1Char(':')) == colon) {
            host = raw.left(colon);
            port = raw.mid(colon + 1).toInt();
        } else {
            host = raw;
        }
    }

    if (host.isEmpty() || port <= 0 || port > 65535) {
        *error = QStringLiteral("Could not parse host or port");
        return false;
    }

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
    if (kind == RequestConfig && !m_accessToken.isEmpty())
        request.setRawHeader("Authorization",
                             QByteArray("Bearer ") + m_accessToken.toUtf8());
    watch(m_nam->get(request), kind);
}

void HassClient::postJson(const QString &path, const QJsonObject &body, RequestKind kind)
{
    QNetworkRequest request(apiUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
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
    if (m_ignoreSslErrors)
        reply->ignoreSslErrors();
}

void HassClient::restoreSession()
{
    clearError();
    if (m_refreshToken.isEmpty() || m_host.isEmpty()) {
        setStatus(QStringLiteral("Not connected"));
        emit restoreFinished(false);
        return;
    }

    setStatus(QStringLiteral("Restoring session..."));
    QUrlQuery form;
    form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    form.addQueryItem(QStringLiteral("refresh_token"), m_refreshToken);
    form.addQueryItem(QStringLiteral("client_id"), clientId());
    postForm(QStringLiteral("/auth/token"), form, RequestRefresh, false);
}

void HassClient::connectToInstance(const QString &endpoint, bool useSsl, bool ignoreSslErrors)
{
    clearError();
    setLoggedIn(false);
    setNeedsOtp(false);
    setConnected(false);
    m_flowId.clear();
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

    setIgnoreSslErrors(ignoreSslErrors);
    setUseSsl(useSsl);

    QString parseError;
    if (!parseEndpoint(endpoint, &parseError)) {
        setError(parseError);
        emit loginFailed(parseError);
        return;
    }

    // parseEndpoint may override SSL if the user pasted a full URL.
    Q_UNUSED(useSsl);

    QSettings settings;
    settings.setValue(QStringLiteral("host"), m_host);
    settings.setValue(QStringLiteral("port"), m_port);
    settings.setValue(QStringLiteral("useSsl"), m_useSsl);
    settings.setValue(QStringLiteral("ignoreSslErrors"), m_ignoreSslErrors);

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
    clearPersistedTokens();
    setLoggedIn(false);
    setNeedsOtp(false);
    setConnected(false);
    setStatus(QStringLiteral("Signed out"));
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

void HassClient::persistSession()
{
    QSettings settings;
    settings.setValue(QStringLiteral("host"), m_host);
    settings.setValue(QStringLiteral("port"), m_port);
    settings.setValue(QStringLiteral("useSsl"), m_useSsl);
    settings.setValue(QStringLiteral("ignoreSslErrors"), m_ignoreSslErrors);
    settings.setValue(QStringLiteral("username"), m_username);
    settings.setValue(QStringLiteral("refreshToken"), m_refreshToken);
    settings.setValue(QStringLiteral("accessToken"), m_accessToken);
    settings.setValue(QStringLiteral("accessExpiresAt"), m_accessExpiresAt.toMSecsSinceEpoch());
    settings.setValue(QStringLiteral("instanceName"), m_instanceName);
    settings.setValue(QStringLiteral("haVersion"), m_haVersion);
}

void HassClient::clearPersistedTokens()
{
    QSettings settings;
    settings.remove(QStringLiteral("refreshToken"));
    settings.remove(QStringLiteral("accessToken"));
    settings.remove(QStringLiteral("accessExpiresAt"));
}

void HassClient::applyTokens(const QVariantMap &obj, bool keepRefreshIfMissing)
{
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
    } else if (!keepRefreshIfMissing && !m_refreshToken.isEmpty()) {
        m_refreshToken.clear();
        emit refreshTokenChanged();
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
        setError(message);
        setStatus(QStringLiteral("Connection failed"));
        if (kind == RequestRefresh)
            emit restoreFinished(false);
        else
            emit loginFailed(message);
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
            setError(message);
            if (kind == RequestRefresh) {
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
            emit loginSucceeded();
            emit restoreFinished(true);
            return;
        }
        handleConfig(data);
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
        setError(message);
        if (fromRefresh)
            emit restoreFinished(false);
        else
            emit loginFailed(message);
        return;
    }

    applyTokens(jsonObjectToMap(doc.object()), fromRefresh);
    if (m_accessToken.isEmpty()) {
        setBusy(false);
        const QString message = QStringLiteral("No access token in response");
        setError(message);
        if (fromRefresh)
            emit restoreFinished(false);
        else
            emit loginFailed(message);
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
    setStatus(m_instanceName.isEmpty()
              ? QStringLiteral("Signed in")
              : QStringLiteral("Signed in to %1").arg(m_instanceName));
    emit loginSucceeded();
    emit restoreFinished(true);
}
