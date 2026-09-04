#include "hasswebsocket.h"

#include <QWebSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QUrl>
#include <QDebug>

namespace {

const qint64 kMinTokenLifetimeMs = 120 * 1000;
const int kPingIntervalMs = 120 * 1000;
const int kPongTimeoutMs = 15000;

} // namespace

HassWebsocket::HassWebsocket(QObject *parent)
    : QObject(parent)
    , m_socket(new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this))
    , m_ignoreSslErrors(false)
    , m_connected(false)
    , m_wantRunning(false)
    , m_authenticated(false)
    , m_nextId(1)
    , m_pendingPingId(0)
    , m_reconnectAttempt(0)
{
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, SIGNAL(timeout()), this, SLOT(openSocket()));

    m_pingTimer.setInterval(kPingIntervalMs);
    connect(&m_pingTimer, SIGNAL(timeout()), this, SLOT(sendPing()));
    m_pongTimer.setSingleShot(true);
    m_pongTimer.setInterval(kPongTimeoutMs);
    connect(&m_pongTimer, SIGNAL(timeout()), this, SLOT(onPongTimeout()));

    connect(m_socket, SIGNAL(connected()), this, SLOT(onConnected()));
    connect(m_socket, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    connect(m_socket, SIGNAL(textMessageReceived(QString)),
            this, SLOT(onTextMessageReceived(QString)));
    connect(m_socket, SIGNAL(error(QAbstractSocket::SocketError)),
            this, SLOT(onError(QAbstractSocket::SocketError)));
    connect(m_socket, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

HassWebsocket::~HassWebsocket()
{
    m_wantRunning = false;
    m_reconnectTimer.stop();
    stopKeepalive();
    m_socket->abort();
}

bool HassWebsocket::connected() const
{
    return m_connected;
}

bool HassWebsocket::authenticated() const
{
    return m_authenticated;
}

void HassWebsocket::configure(const QString &baseUrl,
                              const QString &accessToken,
                              const QDateTime &accessExpiresAt,
                              bool ignoreSslErrors)
{
    const bool endpointChanged = m_baseUrl != baseUrl
            || m_ignoreSslErrors != ignoreSslErrors;

    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_accessExpiresAt = accessExpiresAt;
    m_ignoreSslErrors = ignoreSslErrors;

    if (endpointChanged && m_wantRunning) {
        m_reconnectTimer.stop();
        stopKeepalive();
        m_reconnectAttempt = 0;
        if (m_socket->state() != QAbstractSocket::UnconnectedState)
            m_socket->abort();
        setAuthenticated(false);
        setConnected(false);
        openSocket();
    }
}

void HassWebsocket::start()
{
    const bool wasRunning = m_wantRunning;
    m_wantRunning = true;
    if (!wasRunning)
        m_reconnectAttempt = 0;
    openSocket();
}

void HassWebsocket::stop()
{
    m_wantRunning = false;
    m_reconnectTimer.stop();
    stopKeepalive();
    setAuthenticated(false);
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->close();
    setConnected(false);
}

int HassWebsocket::sendCommand(QJsonObject payload)
{
    if (!m_authenticated || m_socket->state() != QAbstractSocket::ConnectedState)
        return 0;
    const int id = nextMessageId();
    payload.insert(QStringLiteral("id"), id);
    sendJson(payload);
    return id;
}

bool HassWebsocket::accessTokenFresh() const
{
    if (m_accessToken.isEmpty())
        return false;
    if (!m_accessExpiresAt.isValid())
        return false;
    const qint64 msLeft = QDateTime::currentDateTimeUtc().msecsTo(m_accessExpiresAt.toUTC());
    return msLeft > kMinTokenLifetimeMs;
}

void HassWebsocket::openSocket()
{
    if (!m_wantRunning)
        return;
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty()) {
        qWarning() << "Helmsman ws: missing baseUrl/token; not starting";
        return;
    }
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        return;

    if (!accessTokenFresh()) {
        qWarning() << "Helmsman ws: access token expired; asking for a refresh before connecting";
        emit accessTokenStale();
        return;
    }

    m_reconnectTimer.stop();
    stopKeepalive();
    setAuthenticated(false);
    const QUrl url = websocketUrl();
    qWarning() << "Helmsman ws: connecting to" << url.toString();
    m_socket->open(url);
}

void HassWebsocket::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    emit connectedChanged();
}

void HassWebsocket::setAuthenticated(bool authenticated)
{
    if (m_authenticated == authenticated)
        return;
    m_authenticated = authenticated;
    emit authenticatedChanged();
}

QUrl HassWebsocket::websocketUrl() const
{
    QUrl url(m_baseUrl);
    const QString scheme = url.scheme().toLower();
    if (scheme == QLatin1String("https"))
        url.setScheme(QStringLiteral("wss"));
    else
        url.setScheme(QStringLiteral("ws"));
    url.setPath(QStringLiteral("/api/websocket"));
    url.setQuery(QString());
    url.setFragment(QString());
    return url;
}

int HassWebsocket::nextMessageId()
{
    return m_nextId++;
}

void HassWebsocket::sendJson(const QJsonObject &obj)
{
    const QByteArray payload = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->sendTextMessage(QString::fromUtf8(payload));
}

void HassWebsocket::onConnected()
{
    qWarning() << "Helmsman ws: socket connected, waiting for auth_required";
    m_reconnectAttempt = 0;
}

void HassWebsocket::onDisconnected()
{
    qWarning() << "Helmsman ws: disconnected";
    stopKeepalive();
    setAuthenticated(false);
    setConnected(false);
    if (m_wantRunning) {
        if (!accessTokenFresh()) {
            emit accessTokenStale();
            return;
        }
        scheduleReconnect();
    }
}

void HassWebsocket::onError(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error);
    qWarning() << "Helmsman ws: socket error" << m_socket->errorString();
}

void HassWebsocket::onSslErrors(const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    if (m_ignoreSslErrors)
        m_socket->ignoreSslErrors();
}

void HassWebsocket::scheduleReconnect()
{
    if (!m_wantRunning || m_reconnectTimer.isActive())
        return;

    ++m_reconnectAttempt;
    int delayMs = 1000;
    for (int i = 1; i < m_reconnectAttempt && delayMs < 30000; ++i)
        delayMs = qMin(30000, delayMs * 2);

    qWarning() << "Helmsman ws: reconnect in" << delayMs << "ms";
    m_reconnectTimer.start(delayMs);
}

void HassWebsocket::startKeepalive()
{
    m_pendingPingId = 0;
    m_pongTimer.stop();
    m_pingTimer.start();
    sendPing();
}

void HassWebsocket::stopKeepalive()
{
    m_pingTimer.stop();
    m_pongTimer.stop();
    m_pendingPingId = 0;
}

void HassWebsocket::sendPing()
{
    if (!m_authenticated || m_socket->state() != QAbstractSocket::ConnectedState)
        return;
    if (m_pongTimer.isActive())
        return;

    m_pendingPingId = nextMessageId();
    QJsonObject msg;
    msg.insert(QStringLiteral("id"), m_pendingPingId);
    msg.insert(QStringLiteral("type"), QStringLiteral("ping"));
    sendJson(msg);
    m_pongTimer.start();
}

void HassWebsocket::onPongTimeout()
{
    qWarning() << "Helmsman ws: ping timeout; reconnecting";
    m_pendingPingId = 0;
    stopKeepalive();
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->abort();
}

void HassWebsocket::onTextMessageReceived(const QString &message)
{
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    const QString type = obj.value(QStringLiteral("type")).toString();

    if (type == QLatin1String("auth_required")) {
        if (!accessTokenFresh()) {
            qWarning() << "Helmsman ws: token expired before auth handshake";
            m_socket->close();
            emit accessTokenStale();
            return;
        }
        QJsonObject auth;
        auth.insert(QStringLiteral("type"), QStringLiteral("auth"));
        auth.insert(QStringLiteral("access_token"), m_accessToken);
        sendJson(auth);
        return;
    }

    if (type == QLatin1String("auth_ok")) {
        setAuthenticated(true);
        setConnected(true);
        startKeepalive();
        emit connectionReady();
        return;
    }

    if (type == QLatin1String("auth_invalid")) {
        const QString messageText = obj.value(QStringLiteral("message")).toString();
        qWarning() << "Helmsman ws: auth_invalid" << messageText;
        m_wantRunning = false;
        m_reconnectTimer.stop();
        stopKeepalive();
        m_socket->close();
        setAuthenticated(false);
        setConnected(false);
        emit authenticationFailed(messageText);
        return;
    }

    if (type == QLatin1String("pong")) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        if (m_pendingPingId != 0 && id == m_pendingPingId) {
            m_pendingPingId = 0;
            m_pongTimer.stop();
        }
        return;
    }

    if (type == QLatin1String("ping")) {
        QJsonObject pong;
        pong.insert(QStringLiteral("id"), obj.value(QStringLiteral("id")));
        pong.insert(QStringLiteral("type"), QStringLiteral("pong"));
        sendJson(pong);
        return;
    }

    if (type == QLatin1String("result")) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        const bool success = obj.value(QStringLiteral("success")).toBool();
        const QVariant result = obj.value(QStringLiteral("result")).toVariant();
        QVariantMap error;
        if (!success && obj.value(QStringLiteral("error")).isObject())
            error = obj.value(QStringLiteral("error")).toObject().toVariantMap();
        emit resultReceived(id, success, result, error);
        return;
    }

    if (type == QLatin1String("event")) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        const QJsonValue eventVal = obj.value(QStringLiteral("event"));
        QVariantMap event;
        if (eventVal.isObject())
            event = eventVal.toObject().toVariantMap();
        else
            event.insert(QStringLiteral("value"), eventVal.toVariant());
        emit eventReceived(id, event);
    }
}
