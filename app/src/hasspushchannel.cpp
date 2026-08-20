#include "hasspushchannel.h"

#include <QWebSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QUrl>
#include <QDebug>

HassPushChannel::HassPushChannel(QObject *parent)
    : QObject(parent)
    , m_socket(new QWebSocket(QString(), QWebSocketProtocol::VersionLatest, this))
    , m_ignoreSslErrors(false)
    , m_connected(false)
    , m_wantRunning(false)
    , m_authenticated(false)
    , m_nextId(1)
    , m_pushSubscriptionId(0)
    , m_reconnectAttempt(0)
{
    m_reconnectTimer.setSingleShot(true);
    connect(&m_reconnectTimer, SIGNAL(timeout()), this, SLOT(openSocket()));

    connect(m_socket, SIGNAL(connected()), this, SLOT(onConnected()));
    connect(m_socket, SIGNAL(disconnected()), this, SLOT(onDisconnected()));
    connect(m_socket, SIGNAL(textMessageReceived(QString)),
            this, SLOT(onTextMessageReceived(QString)));
    connect(m_socket, SIGNAL(error(QAbstractSocket::SocketError)),
            this, SLOT(onError(QAbstractSocket::SocketError)));
    connect(m_socket, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

HassPushChannel::~HassPushChannel()
{
    m_wantRunning = false;
    m_reconnectTimer.stop();
    m_socket->abort();
}

bool HassPushChannel::connected() const
{
    return m_connected;
}

void HassPushChannel::configure(const QString &baseUrl,
                                const QString &accessToken,
                                const QString &webhookId,
                                bool ignoreSslErrors)
{
    const bool changed = m_baseUrl != baseUrl
            || m_accessToken != accessToken
            || m_webhookId != webhookId
            || m_ignoreSslErrors != ignoreSslErrors;

    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_webhookId = webhookId;
    m_ignoreSslErrors = ignoreSslErrors;

    if (changed && m_wantRunning) {
        m_reconnectTimer.stop();
        if (m_socket->state() != QAbstractSocket::UnconnectedState)
            m_socket->abort();
        setConnected(false);
        openSocket();
    }
}

void HassPushChannel::start()
{
    m_wantRunning = true;
    openSocket();
}

void HassPushChannel::stop()
{
    m_wantRunning = false;
    m_reconnectTimer.stop();
    m_authenticated = false;
    m_pushSubscriptionId = 0;
    if (m_socket->state() != QAbstractSocket::UnconnectedState)
        m_socket->close();
    setConnected(false);
}

void HassPushChannel::openSocket()
{
    if (!m_wantRunning)
        return;
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty() || m_webhookId.isEmpty()) {
        qWarning() << "Helmsman push: missing baseUrl/token/webhook; not starting";
        return;
    }
    if (m_socket->state() == QAbstractSocket::ConnectedState
            || m_socket->state() == QAbstractSocket::ConnectingState) {
        return;
    }

    m_authenticated = false;
    m_pushSubscriptionId = 0;
    const QUrl url = websocketUrl();
    qWarning() << "Helmsman push: connecting to" << url.toString();
    m_socket->open(url);
}

void HassPushChannel::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    emit connectedChanged();
}

QUrl HassPushChannel::websocketUrl() const
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

int HassPushChannel::nextMessageId()
{
    return m_nextId++;
}

void HassPushChannel::sendJson(const QJsonObject &obj)
{
    const QByteArray payload = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_socket->sendTextMessage(QString::fromUtf8(payload));
}

void HassPushChannel::onConnected()
{
    qWarning() << "Helmsman push: socket connected, waiting for auth_required";
    m_reconnectAttempt = 0;
}

void HassPushChannel::onDisconnected()
{
    qWarning() << "Helmsman push: disconnected";
    m_authenticated = false;
    m_pushSubscriptionId = 0;
    setConnected(false);
    if (m_wantRunning)
        scheduleReconnect();
}

void HassPushChannel::onError(QAbstractSocket::SocketError error)
{
    Q_UNUSED(error);
    qWarning() << "Helmsman push: socket error" << m_socket->errorString();
}

void HassPushChannel::onSslErrors(const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    if (m_ignoreSslErrors)
        m_socket->ignoreSslErrors();
}

void HassPushChannel::scheduleReconnect()
{
    if (!m_wantRunning || m_reconnectTimer.isActive())
        return;

    ++m_reconnectAttempt;
    int delayMs = 1000;
    for (int i = 1; i < m_reconnectAttempt && delayMs < 30000; ++i)
        delayMs = qMin(30000, delayMs * 2);

    qWarning() << "Helmsman push: reconnect in" << delayMs << "ms";
    m_reconnectTimer.start(delayMs);
}

void HassPushChannel::subscribePushChannel()
{
    if (m_webhookId.isEmpty())
        return;

    m_pushSubscriptionId = nextMessageId();
    QJsonObject msg;
    msg.insert(QStringLiteral("id"), m_pushSubscriptionId);
    msg.insert(QStringLiteral("type"), QStringLiteral("mobile_app/push_notification_channel"));
    msg.insert(QStringLiteral("webhook_id"), m_webhookId);
    msg.insert(QStringLiteral("support_confirm"), true);
    sendJson(msg);
    qWarning() << "Helmsman push: subscribed channel id=" << m_pushSubscriptionId;
}

void HassPushChannel::confirmNotification(const QString &confirmId)
{
    if (confirmId.isEmpty() || m_webhookId.isEmpty())
        return;

    QJsonObject msg;
    msg.insert(QStringLiteral("id"), nextMessageId());
    msg.insert(QStringLiteral("type"), QStringLiteral("mobile_app/push_notification_confirm"));
    msg.insert(QStringLiteral("webhook_id"), m_webhookId);
    msg.insert(QStringLiteral("confirm_id"), confirmId);
    sendJson(msg);
}

void HassPushChannel::onTextMessageReceived(const QString &message)
{
    const QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    if (!doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    const QString type = obj.value(QStringLiteral("type")).toString();

    if (type == QLatin1String("auth_required")) {
        QJsonObject auth;
        auth.insert(QStringLiteral("type"), QStringLiteral("auth"));
        auth.insert(QStringLiteral("access_token"), m_accessToken);
        sendJson(auth);
        return;
    }

    if (type == QLatin1String("auth_ok")) {
        m_authenticated = true;
        setConnected(true);
        subscribePushChannel();
        return;
    }

    if (type == QLatin1String("auth_invalid")) {
        qWarning() << "Helmsman push: auth_invalid"
                   << obj.value(QStringLiteral("message")).toString();
        m_wantRunning = false;
        m_socket->close();
        setConnected(false);
        return;
    }

    if (type == QLatin1String("result")) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        const bool success = obj.value(QStringLiteral("success")).toBool();
        if (id == m_pushSubscriptionId) {
            if (success) {
                qWarning() << "Helmsman push: subscribe ok id=" << id;
            } else {
                qWarning() << "Helmsman push: subscribe failed"
                           << QJsonDocument(obj.value(QStringLiteral("error")).toObject()).toJson(QJsonDocument::Compact);
            }
        }
        return;
    }

    if (type == QLatin1String("event")) {
        const int id = obj.value(QStringLiteral("id")).toInt();
        if (m_pushSubscriptionId == 0 || id != m_pushSubscriptionId) {
            qWarning() << "Helmsman push: ignoring event id=" << id
                       << "expected=" << m_pushSubscriptionId;
            return;
        }

        const QJsonObject event = obj.value(QStringLiteral("event")).toObject();
        const QString messageText = event.value(QStringLiteral("message")).toString();
        QString title = event.value(QStringLiteral("title")).toString();
        if (title.isEmpty())
            title = QStringLiteral("Home Assistant");

        QVariantMap data;
        const QJsonValue dataVal = event.value(QStringLiteral("data"));
        if (dataVal.isObject())
            data = dataVal.toObject().toVariantMap();

        qWarning() << "Helmsman push: notification" << title << messageText;

        const QString confirmId = event.value(QStringLiteral("hass_confirm_id")).toString();
        emit notificationReceived(title, messageText, data);
        if (!confirmId.isEmpty())
            confirmNotification(confirmId);
    }
}
