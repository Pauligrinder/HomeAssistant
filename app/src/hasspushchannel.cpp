#include "hasspushchannel.h"
#include "hasswebsocket.h"

#include <QJsonObject>
#include <QDebug>

HassPushChannel::HassPushChannel(QObject *parent)
    : QObject(parent)
    , m_socket(0)
    , m_wantRunning(false)
    , m_subscribed(false)
    , m_pushSubscriptionId(0)
{
}

HassPushChannel::~HassPushChannel()
{
    m_wantRunning = false;
}

bool HassPushChannel::connected() const
{
    return m_socket && m_socket->connected() && m_subscribed;
}

void HassPushChannel::setWebsocket(HassWebsocket *socket)
{
    if (m_socket == socket)
        return;

    if (m_socket) {
        disconnect(m_socket, 0, this, 0);
    }

    m_socket = socket;
    if (!m_socket)
        return;

    connect(m_socket, SIGNAL(connectionReady()), this, SLOT(onConnectionReady()));
    connect(m_socket, SIGNAL(authenticatedChanged()), this, SLOT(onAuthenticatedChanged()));
    connect(m_socket, SIGNAL(resultReceived(int,bool,QVariant,QVariantMap)),
            this, SLOT(onResultReceived(int,bool,QVariant,QVariantMap)));
    connect(m_socket, SIGNAL(eventReceived(int,QVariantMap)),
            this, SLOT(onEventReceived(int,QVariantMap)));
    connect(m_socket, SIGNAL(accessTokenStale()), this, SIGNAL(accessTokenStale()));
    connect(m_socket, SIGNAL(authenticationFailed(QString)),
            this, SIGNAL(authenticationFailed(QString)));
}

void HassPushChannel::configure(const QString &baseUrl,
                                const QString &accessToken,
                                const QDateTime &accessExpiresAt,
                                const QString &webhookId,
                                bool ignoreSslErrors)
{
    Q_UNUSED(baseUrl);
    Q_UNUSED(accessToken);
    Q_UNUSED(accessExpiresAt);
    Q_UNUSED(ignoreSslErrors);
    m_webhookId = webhookId;
    m_subscribed = false;
    m_pushSubscriptionId = 0;
    if (m_wantRunning && m_socket && m_socket->authenticated())
        subscribePushChannel();
}

void HassPushChannel::start()
{
    m_wantRunning = true;
    if (m_socket && m_socket->authenticated())
        subscribePushChannel();
}

void HassPushChannel::stop()
{
    m_wantRunning = false;
    m_subscribed = false;
    m_pushSubscriptionId = 0;
    emit connectedChanged();
}

void HassPushChannel::onConnectionReady()
{
    if (m_wantRunning)
        subscribePushChannel();
}

void HassPushChannel::onAuthenticatedChanged()
{
    if (!m_socket || !m_socket->authenticated()) {
        m_subscribed = false;
        m_pushSubscriptionId = 0;
        emit connectedChanged();
    }
}

void HassPushChannel::subscribePushChannel()
{
    if (!m_socket || m_webhookId.isEmpty() || !m_wantRunning)
        return;
    if (!m_socket->authenticated())
        return;

    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("mobile_app/push_notification_channel"));
    msg.insert(QStringLiteral("webhook_id"), m_webhookId);
    msg.insert(QStringLiteral("support_confirm"), true);
    m_pushSubscriptionId = m_socket->sendCommand(msg);
    qWarning() << "Helmsman push: subscribed channel id=" << m_pushSubscriptionId;
}

void HassPushChannel::confirmNotification(const QString &confirmId)
{
    if (!m_socket || confirmId.isEmpty() || m_webhookId.isEmpty())
        return;

    QJsonObject msg;
    msg.insert(QStringLiteral("type"), QStringLiteral("mobile_app/push_notification_confirm"));
    msg.insert(QStringLiteral("webhook_id"), m_webhookId);
    msg.insert(QStringLiteral("confirm_id"), confirmId);
    m_socket->sendCommand(msg);
}

void HassPushChannel::onResultReceived(int id, bool success, const QVariant &result, const QVariantMap &error)
{
    Q_UNUSED(result);
    if (id == 0 || id != m_pushSubscriptionId)
        return;
    if (success) {
        m_subscribed = true;
        qWarning() << "Helmsman push: subscribe ok id=" << id;
        emit connectedChanged();
    } else {
        m_subscribed = false;
        qWarning() << "Helmsman push: subscribe failed" << error;
        emit connectedChanged();
    }
}

void HassPushChannel::onEventReceived(int id, const QVariantMap &event)
{
    if (m_pushSubscriptionId == 0 || id != m_pushSubscriptionId)
        return;

    const QString messageText = event.value(QStringLiteral("message")).toString();
    QString title = event.value(QStringLiteral("title")).toString();
    if (title.isEmpty())
        title = QStringLiteral("Home Assistant");

    QVariantMap data = event.value(QStringLiteral("data")).toMap();
    qWarning() << "Helmsman push: notification" << title << messageText;

    const QString confirmId = event.value(QStringLiteral("hass_confirm_id")).toString();
    emit notificationReceived(title, messageText, data);
    if (!confirmId.isEmpty())
        confirmNotification(confirmId);
}
