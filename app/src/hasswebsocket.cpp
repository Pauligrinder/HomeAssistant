#include "hasswebsocket.h"

#include <QTcpSocket>
#include <QSslSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QDebug>
#include <QStringList>
#include <QThread>
#include <QMetaObject>
#include <QNetworkProxy>
#include <QCryptographicHash>
#include <QUuid>

namespace {

const qint64 kMinTokenFreshMs = 120 * 1000;
const int kPingIntervalMs = 120 * 1000;
const int kPongTimeoutMs = 15000;
const int kConnectTimeoutMs = 12000;
const char kWsAcceptMagic[] = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

} // namespace

HassWsTransport::HassWsTransport(QObject *parent)
    : QObject(parent)
    , m_socket(0)
    , m_ignoreSsl(false)
    , m_handshakeDone(false)
    , m_closing(false)
    , m_fragmentOpcodeText(false)
    , m_epoch(0)
{
}

void HassWsTransport::openUrl(QUrl url, bool ignoreSsl, int epoch)
{
    m_ignoreSsl = ignoreSsl;
    m_epoch = epoch;
    m_url = url;
    m_handshakeDone = false;
    m_closing = false;
    m_buffer.clear();
    m_fragment.clear();
    m_wsKey.clear();
    destroySocket();

    const bool ssl = url.scheme().compare(QLatin1String("wss"), Qt::CaseInsensitive) == 0;
    const int port = url.port(ssl ? 443 : 80);
    qWarning() << "Helmsman ws: io open" << url.toString()
               << "Host=" << hostHeader(url)
               << "Origin=" << originHeader(url);

    if (ssl) {
        QSslSocket *sslSock = new QSslSocket(this);
        sslSock->setProxy(QNetworkProxy::NoProxy);
        m_socket = sslSock;
        bindSocket(true);
        sslSock->connectToHostEncrypted(url.host(), static_cast<quint16>(port));
    } else {
        QTcpSocket *tcp = new QTcpSocket(this);
        tcp->setProxy(QNetworkProxy::NoProxy);
        m_socket = tcp;
        bindSocket(false);
        tcp->connectToHost(url.host(), static_cast<quint16>(port));
    }
}

void HassWsTransport::closeSocket()
{
    m_closing = true;
    destroySocket();
}

void HassWsTransport::sendText(QString text)
{
    if (!m_socket || !m_handshakeDone
            || m_socket->state() != QAbstractSocket::ConnectedState)
        return;
    m_socket->write(encodeTextFrame(text.toUtf8()));
}

void HassWsTransport::bindSocket(bool ssl)
{
    if (!m_socket)
        return;
    if (ssl) {
        QSslSocket *sslSock = qobject_cast<QSslSocket *>(m_socket);
        if (sslSock) {
            connect(sslSock, SIGNAL(encrypted()), this, SLOT(onEncrypted()));
            connect(sslSock, SIGNAL(sslErrors(QList<QSslError>)),
                    this, SLOT(onSslErrors(QList<QSslError>)));
        }
    } else {
        connect(m_socket, SIGNAL(connected()), this, SLOT(onTcpConnected()));
    }
    connect(m_socket, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    connect(m_socket, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
    connect(m_socket, SIGNAL(error(QAbstractSocket::SocketError)),
            this, SLOT(onError(QAbstractSocket::SocketError)));
}

void HassWsTransport::destroySocket()
{
    if (!m_socket)
        return;
    QTcpSocket *old = m_socket;
    m_socket = 0;
    m_handshakeDone = false;
    m_buffer.clear();
    m_fragment.clear();
    old->disconnect(this);
    old->setParent(0);
    old->abort();
    old->deleteLater();
}

void HassWsTransport::onTcpConnected()
{
    sendHandshake();
}

void HassWsTransport::onEncrypted()
{
    sendHandshake();
}

void HassWsTransport::onDisconnected()
{
    const bool wasOpen = m_handshakeDone;
    m_handshakeDone = false;
    m_buffer.clear();
    if (wasOpen || !m_closing)
        emit closed(m_epoch);
}

void HassWsTransport::onReadyRead()
{
    if (!m_socket)
        return;
    m_buffer.append(m_socket->readAll());
    if (!m_handshakeDone) {
        if (!consumeHandshake())
            return;
    }
    if (m_handshakeDone)
        consumeFrames();
}

void HassWsTransport::onError(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error);
    if (m_closing || m_handshakeDone)
        return;
    emit errorText(m_socket ? m_socket->errorString() : QStringLiteral("no socket"));
}

void HassWsTransport::onSslErrors(const QList<QSslError> &errors)
{
    QStringList texts;
    for (int i = 0; i < errors.size(); ++i)
        texts.append(errors.at(i).errorString());
    qWarning() << "Helmsman ws: TLS error" << texts.join(QStringLiteral("; "))
               << "ignore=" << m_ignoreSsl;
    QSslSocket *sslSock = qobject_cast<QSslSocket *>(m_socket);
    if (m_ignoreSsl && sslSock)
        sslSock->ignoreSslErrors();
}

void HassWsTransport::failHandshake(const QString &message)
{
    qWarning() << "Helmsman ws: handshake failed" << message;
    emit errorText(message);
    m_closing = true;
    if (m_socket)
        m_socket->abort();
}

void HassWsTransport::sendHandshake()
{
    if (!m_socket || m_handshakeDone)
        return;

    m_wsKey = makeWsKey();
    QString path = m_url.path(QUrl::FullyEncoded);
    if (path.isEmpty())
        path = QStringLiteral("/");
    if (m_url.hasQuery())
        path += QLatin1Char('?') + m_url.query(QUrl::FullyEncoded);

    const QString host = hostHeader(m_url);
    const QString origin = originHeader(m_url);

    QByteArray req;
    req += "GET ";
    req += path.toUtf8();
    req += " HTTP/1.1\r\n";
    req += "Host: ";
    req += host.toUtf8();
    req += "\r\n";
    req += "Upgrade: websocket\r\n";
    req += "Connection: Upgrade\r\n";
    req += "Sec-WebSocket-Key: ";
    req += m_wsKey;
    req += "\r\n";
    req += "Sec-WebSocket-Version: 13\r\n";
    if (!origin.isEmpty()) {
        req += "Origin: ";
        req += origin.toUtf8();
        req += "\r\n";
    }
    req += "\r\n";
    m_socket->write(req);
}

bool HassWsTransport::consumeHandshake()
{
    const int sep = m_buffer.indexOf("\r\n\r\n");
    if (sep < 0) {
        if (m_buffer.size() > 65536) {
            failHandshake(QStringLiteral("WebSocket handshake response too large"));
            return false;
        }
        return false;
    }

    const QByteArray headerBlock = m_buffer.left(sep);
    m_buffer.remove(0, sep + 4);

    const QList<QByteArray> lines = headerBlock.split('\n');
    if (lines.isEmpty()) {
        failHandshake(QStringLiteral("Empty WebSocket handshake response"));
        return false;
    }

    QByteArray statusLine = lines.at(0).trimmed();
    if (statusLine.endsWith('\r'))
        statusLine.chop(1);

    // HTTP/1.1 101 Switching Protocols
    const QList<QByteArray> statusParts = statusLine.split(' ');
    int code = 0;
    if (statusParts.size() >= 2)
        code = statusParts.at(1).toInt();

    QByteArray accept;
    QByteArray server;
    for (int i = 1; i < lines.size(); ++i) {
        QByteArray line = lines.at(i).trimmed();
        if (line.endsWith('\r'))
            line.chop(1);
        const int colon = line.indexOf(':');
        if (colon <= 0)
            continue;
        const QByteArray name = line.left(colon).trimmed().toLower();
        const QByteArray value = line.mid(colon + 1).trimmed();
        if (name == "sec-websocket-accept")
            accept = value;
        else if (name == "server")
            server = value;
    }

    if (code != 101) {
        QString message = QStringLiteral("WebSocket handshake HTTP %1").arg(code);
        if (!server.isEmpty())
            message += QStringLiteral(" (Server: %1)").arg(QString::fromUtf8(server));
        if (code == 404) {
            message = QStringLiteral(
                "WebSocket returned 404. Is Home Assistant reachable at "
                "/api/websocket behind your reverse proxy?");
            if (!server.isEmpty())
                message += QStringLiteral(" Server=%1").arg(QString::fromUtf8(server));
        }
        // Drop any HTML body so it is not misread as frames / status lines.
        m_buffer.clear();
        failHandshake(message);
        return false;
    }

    QCryptographicHash hash(QCryptographicHash::Sha1);
    hash.addData(m_wsKey);
    hash.addData(kWsAcceptMagic);
    const QByteArray expected = hash.result().toBase64();
    if (!accept.isEmpty() && accept != expected) {
        failHandshake(QStringLiteral("WebSocket Sec-WebSocket-Accept mismatch"));
        return false;
    }

    m_handshakeDone = true;
    qWarning() << "Helmsman ws: handshake 101 ok";
    emit opened(m_epoch);
    return true;
}

void HassWsTransport::consumeFrames()
{
    while (true) {
        if (m_buffer.size() < 2)
            return;

        const quint8 b0 = static_cast<quint8>(m_buffer.at(0));
        const quint8 b1 = static_cast<quint8>(m_buffer.at(1));
        const bool fin = (b0 & 0x80) != 0;
        const int opcode = b0 & 0x0f;
        const bool masked = (b1 & 0x80) != 0;
        quint64 payloadLen = b1 & 0x7f;
        int headerLen = 2;

        if (payloadLen == 126) {
            if (m_buffer.size() < 4)
                return;
            payloadLen = (static_cast<quint8>(m_buffer.at(2)) << 8)
                    | static_cast<quint8>(m_buffer.at(3));
            headerLen = 4;
        } else if (payloadLen == 127) {
            if (m_buffer.size() < 10)
                return;
            payloadLen = 0;
            for (int i = 0; i < 8; ++i) {
                payloadLen <<= 8;
                payloadLen |= static_cast<quint8>(m_buffer.at(2 + i));
            }
            headerLen = 10;
        }

        if (masked)
            headerLen += 4;

        if (payloadLen > 8 * 1024 * 1024) {
            failHandshake(QStringLiteral("WebSocket frame too large"));
            return;
        }

        if (static_cast<quint64>(m_buffer.size()) < static_cast<quint64>(headerLen) + payloadLen)
            return;

        QByteArray maskKey;
        if (masked)
            maskKey = m_buffer.mid(headerLen - 4, 4);

        QByteArray payload = m_buffer.mid(headerLen, static_cast<int>(payloadLen));
        m_buffer.remove(0, headerLen + static_cast<int>(payloadLen));

        if (masked) {
            for (int i = 0; i < payload.size(); ++i)
                payload[i] = char(payload.at(i) ^ maskKey.at(i % 4));
        }

        switch (opcode) {
        case 0x0: { // continuation
            m_fragment.append(payload);
            if (fin) {
                const QByteArray message = m_fragment;
                m_fragment.clear();
                if (m_fragmentOpcodeText)
                    emit textReceived(QString::fromUtf8(message));
            }
            break;
        }
        case 0x1: { // text
            if (!fin) {
                m_fragmentOpcodeText = true;
                m_fragment = payload;
            } else {
                emit textReceived(QString::fromUtf8(payload));
            }
            break;
        }
        case 0x2: { // binary — unused by HA API
            if (!fin) {
                m_fragmentOpcodeText = false;
                m_fragment = payload;
            }
            break;
        }
        case 0x8: { // close
            m_closing = true;
            if (m_socket)
                m_socket->disconnectFromHost();
            break;
        }
        case 0x9: { // ping — reply pong
            if (!m_socket)
                break;
            QByteArray frame;
            frame.append(char(0x8a));
            const int len = payload.size();
            if (len < 126) {
                frame.append(char(0x80 | len));
            } else {
                frame.append(char(0x80 | 126));
                frame.append(char((len >> 8) & 0xff));
                frame.append(char(len & 0xff));
            }
            const QByteArray key = QUuid::createUuid().toRfc4122().left(4);
            frame.append(key);
            for (int i = 0; i < len; ++i)
                frame.append(char(payload.at(i) ^ key.at(i % 4)));
            m_socket->write(frame);
            break;
        }
        case 0xa: // pong
            break;
        default:
            break;
        }
    }
}

QByteArray HassWsTransport::encodeTextFrame(const QByteArray &payload) const
{
    QByteArray frame;
    frame.append(char(0x81));
    const int len = payload.size();
    if (len < 126) {
        frame.append(char(0x80 | len));
    } else if (len <= 0xffff) {
        frame.append(char(0x80 | 126));
        frame.append(char((len >> 8) & 0xff));
        frame.append(char(len & 0xff));
    } else {
        frame.append(char(0x80 | 127));
        for (int i = 7; i >= 0; --i)
            frame.append(char((quint64(len) >> (8 * i)) & 0xff));
    }
    const QByteArray key = QUuid::createUuid().toRfc4122().left(4);
    frame.append(key);
    for (int i = 0; i < len; ++i)
        frame.append(char(payload.at(i) ^ key.at(i % 4)));
    return frame;
}

QString HassWsTransport::hostHeader(const QUrl &url)
{
    QString host = url.host();
    if (host.contains(QLatin1Char(':')))
        host = QLatin1Char('[') + host + QLatin1Char(']');
    // Omit default ports — matches browsers; Qt 5.6 QWebSocket always appended them.
    const int port = url.port();
    if (port != -1)
        host += QLatin1Char(':') + QString::number(port);
    return host;
}

QString HassWsTransport::originHeader(const QUrl &wsUrl)
{
    QUrl origin;
    if (wsUrl.scheme().compare(QLatin1String("wss"), Qt::CaseInsensitive) == 0)
        origin.setScheme(QStringLiteral("https"));
    else
        origin.setScheme(QStringLiteral("http"));
    origin.setHost(wsUrl.host());
    if (wsUrl.port() != -1)
        origin.setPort(wsUrl.port());
    return origin.toString(QUrl::RemovePath | QUrl::RemoveQuery | QUrl::RemoveFragment);
}

QByteArray HassWsTransport::makeWsKey()
{
    return QUuid::createUuid().toRfc4122().toBase64();
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
    return msLeft > kMinTokenFreshMs;
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
    if (!m_opening)
        return;
    m_opening = false;
    m_connectTimer.stop();
    qWarning() << "Helmsman ws: socket error" << error;

    QString message = error;
    if (error.contains(QStringLiteral("404"), Qt::CaseInsensitive)
            || error.contains(QStringLiteral("Not Found"), Qt::CaseInsensitive)) {
        if (!error.startsWith(QStringLiteral("WebSocket returned 404"))) {
            message = QStringLiteral(
                "WebSocket returned 404. Is Home Assistant reachable at "
                "/api/websocket behind your reverse proxy?");
        }
    } else if (error.contains(QStringLiteral("403"), Qt::CaseInsensitive)
               || error.contains(QStringLiteral("Forbidden"), Qt::CaseInsensitive)) {
        message = QStringLiteral(
            "WebSocket returned 403. Check reverse-proxy and Home Assistant access.");
    }
    emit connectionFailed(message);

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
    m_opening = false;
    emit connectionFailed(QStringLiteral("WebSocket connect timed out."));
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
