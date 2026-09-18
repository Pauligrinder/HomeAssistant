#include "hasswebsocket.h"

#include <QWebSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QDebug>
#include <QStringList>
#include <QThread>
#include <QMetaObject>
#include <QNetworkProxy>

namespace {

const qint64 kMinTokenLifetimeMs = 120 * 1000;
const int kPingIntervalMs = 120 * 1000;
const int kPongTimeoutMs = 15000;
const int kConnectTimeoutMs = 12000;

} // namespace

HassWsTransport::HassWsTransport(QObject *parent)
    : QObject(parent)
    , m_socket(0)
    , m_ignoreSsl(false)
    , m_epoch(0)
{
}

void HassWsTransport::openUrl(QUrl url, bool ignoreSsl, int epoch)
{
    m_ignoreSsl = ignoreSsl;
    m_epoch = epoch;
    destroySocket();
    m_socket = new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this);
    m_socket->setProxy(QNetworkProxy::NoProxy);
    bindSocket();
    qWarning() << "Helmsman ws: io open" << url.toString();
    m_socket->open(url);
}

void HassWsTransport::closeSocket()
{
    destroySocket();
}

void HassWsTransport::sendText(QString text)
{
    if (!m_socket || m_socket->state() != QAbstractSocket::ConnectedState)
        return;
    m_socket->sendTextMessage(text);
}

void HassWsTransport::bindSocket()
{
    if (!m_socket)
        return;
    connect(m_socket, SIGNAL(connected()), this, SLOT(onConnected()));
    connect(m_socket, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    connect(m_socket, SIGNAL(textMessageReceived(QString)),
            this, SLOT(onTextMessageReceived(QString)));
    connect(m_socket, SIGNAL(error(QAbstractSocket::SocketError)),
            this, SLOT(onError(QAbstractSocket::SocketError)));
    connect(m_socket, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

void HassWsTransport::destroySocket()
{
    if (!m_socket)
        return;
    QWebSocket *old = m_socket;
    m_socket = 0;
    old->disconnect(this);
    old->setParent(0);
    old->abort();
    old->deleteLater();
}

void HassWsTransport::onConnected()
{
    emit opened(m_epoch);
}

void HassWsTransport::onDisconnected()
{
    emit closed(m_epoch);
}

void HassWsTransport::onTextMessageReceived(const QString &message)
{
    emit textReceived(message);
}

void HassWsTransport::onError(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error);
    emit errorText(m_socket ? m_socket->errorString() : QStringLiteral("no socket"));
}

void HassWsTransport::onSslErrors(const QList<QSslError> &errors)
{
    QStringList texts;
    for (int i = 0; i < errors.size(); ++i)
        texts.append(errors.at(i).errorString());
    qWarning() << "Helmsman ws: TLS error" << texts.join(QStringLiteral("; "))
               << "ignore=" << m_ignoreSsl;
    if (m_ignoreSsl && m_socket)
        m_socket->ignoreSslErrors();
}

HassWebsocket::HassWebsocket(QObject *parent)
    : QObject(parent)
    , m_transport(0)
    , m_io(0)
    , m_ignoreSslErrors(false)
    , m_connected(false)
    , m_wantRunning(false)
    , m_authenticated(false)
    , m_opening(false)
    , m_epoch(0)
    , m_nextId(1)
    , m_pendingPingId(0)
    , m_reconnectAttempt(0)
{
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, SIGNAL(timeout()), this, SLOT(openSocket()));

    m_connectTimer.setSingleShot(true);
    m_connectTimer.setInterval(kConnectTimeoutMs);
    connect(&m_connectTimer, SIGNAL(timeout()), this, SLOT(onConnectTimeout()));

    m_pingTimer.setInterval(kPingIntervalMs);
    connect(&m_pingTimer, SIGNAL(timeout()), this, SLOT(sendPing()));
    m_pongTimer.setSingleShot(true);
    m_pongTimer.setInterval(kPongTimeoutMs);
    connect(&m_pongTimer, SIGNAL(timeout()), this, SLOT(onPongTimeout()));

    startIo();
}

HassWebsocket::~HassWebsocket()
{
    m_wantRunning = false;
    m_reconnectTimer.stop();
    m_connectTimer.stop();
    stopKeepalive();
    if (m_transport) {
        disconnect(m_transport, 0, this, 0);
        QMetaObject::invokeMethod(m_transport, "closeSocket", Qt::QueuedConnection);
        m_transport->deleteLater();
        m_transport = 0;
    }
    if (m_io) {
        m_io->quit();
        if (!m_io->wait(1500)) {
            qWarning() << "Helmsman ws: io thread still closing a socket; leaking it";
            m_io->setParent(0);
            connect(m_io, SIGNAL(finished()), m_io, SLOT(deleteLater()));
            m_io = 0;
        }
    }
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
        m_connectTimer.stop();
        stopKeepalive();
        m_reconnectAttempt = 0;
        m_opening = false;
        setAuthenticated(false);
        setConnected(false);
        reapSocket();
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
    m_connectTimer.stop();
    stopKeepalive();
    m_opening = false;
    setAuthenticated(false);
    setConnected(false);
    reapSocket();
}

int HassWebsocket::sendCommand(QJsonObject payload)
{
    if (!m_authenticated || !m_transport)
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
    if (m_opening)
        return;
    if (!m_transport)
        startIo();
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
    m_opening = true;
    m_connectTimer.start();
    ++m_epoch;
    QMetaObject::invokeMethod(m_transport, "openUrl", Qt::QueuedConnection,
                              Q_ARG(QUrl, url), Q_ARG(bool, m_ignoreSslErrors),
                              Q_ARG(int, m_epoch));
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

void HassWebsocket::startIo()
{
    if (m_io && m_io->isRunning() && m_transport)
        return;

    m_io = new QThread(this);
    m_io->setObjectName(QStringLiteral("hass-ws-io"));
    m_transport = new HassWsTransport;
    m_transport->moveToThread(m_io);
    bindTransport();
    m_io->start();
}

void HassWebsocket::bindTransport()
{
    if (!m_transport)
        return;
    connect(m_transport, SIGNAL(opened(int)), this, SLOT(onConnected(int)), Qt::QueuedConnection);
    connect(m_transport, SIGNAL(closed(int)), this, SLOT(onDisconnected(int)), Qt::QueuedConnection);
    connect(m_transport, SIGNAL(textReceived(QString)),
            this, SLOT(onTextMessageReceived(QString)), Qt::QueuedConnection);
    connect(m_transport, SIGNAL(errorText(QString)),
            this, SLOT(onTransportError(QString)), Qt::QueuedConnection);
}

void HassWebsocket::detachStuckIo()
{
    qWarning() << "Helmsman ws: detaching stuck io thread";
    ++m_epoch;
    if (m_transport) {
        disconnect(m_transport, 0, this, 0);
        m_transport->deleteLater();
        m_transport = 0;
    }
    if (m_io) {
        m_io->setParent(0);
        connect(m_io, SIGNAL(finished()), m_io, SLOT(deleteLater()));
        m_io->quit();
        m_io = 0;
    }
    m_opening = false;
    startIo();
}

void HassWebsocket::reapSocket()
{
    m_connectTimer.stop();
    stopKeepalive();
    m_opening = false;
    ++m_epoch;
    m_nextId = 1;
    m_pendingPingId = 0;
    if (!m_transport)
        return;
    QMetaObject::invokeMethod(m_transport, "closeSocket", Qt::QueuedConnection);
}

void HassWebsocket::sendJson(const QJsonObject &obj)
{
    if (!m_transport)
        return;
    const QByteArray payload = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    QMetaObject::invokeMethod(m_transport, "sendText", Qt::QueuedConnection,
                              Q_ARG(QString, QString::fromUtf8(payload)));
}

void HassWebsocket::onConnected(int epoch)
{
    if (epoch != m_epoch)
        return;
    m_connectTimer.stop();
    m_opening = false;
    qWarning() << "Helmsman ws: socket connected, waiting for auth_required";
    m_reconnectAttempt = 0;
}

void HassWebsocket::onDisconnected(int epoch)
{
    if (epoch != m_epoch)
        return;
    m_connectTimer.stop();
    m_opening = false;
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

void HassWebsocket::onTransportError(const QString &error)
{
    qWarning() << "Helmsman ws: socket error" << error;
    if (!m_opening)
        return;
    m_opening = false;
    m_connectTimer.stop();
    if (m_wantRunning)
        scheduleReconnect();
}

void HassWebsocket::scheduleReconnect()
{
    if (!m_wantRunning || m_reconnectTimer.isActive())
        return;

    ++m_reconnectAttempt;
    int delayMs = 2000;
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
    if (!m_transport || !m_authenticated)
        return;
    if (m_pongTimer.isActive())
        return;

    m_pendingPingId = nextMessageId();
    QJsonObject msg;
    msg.insert(QStringLiteral("id"), m_pendingPingId);
    msg.insert(QStringLiteral("type"), QStringLiteral("ping"));
    sendJson(msg);
    m_pongTimer.start();
    qWarning() << "Helmsman ws: ping id=" << m_pendingPingId;
}

void HassWebsocket::onPongTimeout()
{
    qWarning() << "Helmsman ws: ping timeout; reconnecting";
    m_pendingPingId = 0;
    stopKeepalive();
    if (!m_wantRunning)
        return;
    reapSocket();
    scheduleReconnect();
}

void HassWebsocket::onConnectTimeout()
{
    qWarning() << "Helmsman ws: connect timed out";
    if (!m_wantRunning)
        return;
    // open() is blocked on the IO thread. Queued closeSocket would never run,
    // so abandon that thread and talk to a new one.
    detachStuckIo();
    scheduleReconnect();
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
            QTimer::singleShot(0, this, SLOT(reapSocket()));
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
        m_connectTimer.stop();
        stopKeepalive();
        m_opening = false;
        setAuthenticated(false);
        setConnected(false);
        QTimer::singleShot(0, this, SLOT(reapSocket()));
        emit authenticationFailed(messageText);
        return;
    }

    if (type == QLatin1String("pong")) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        if (m_pendingPingId != 0 && id == m_pendingPingId) {
            m_pendingPingId = 0;
            m_pongTimer.stop();
            qWarning() << "Helmsman ws: pong id=" << id;
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
