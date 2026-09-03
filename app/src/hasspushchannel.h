#ifndef HASSPUSHCHANNEL_H
#define HASSPUSHCHANNEL_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QTimer>
#include <QDateTime>
#include <QAbstractSocket>
#include <QList>
#include <QSslError>

class QWebSocket;
class QJsonObject;
class QUrl;

class HassPushChannel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    explicit HassPushChannel(QObject *parent = nullptr);
    ~HassPushChannel() override;

    bool connected() const;

public slots:
    void configure(const QString &baseUrl,
                   const QString &accessToken,
                   const QDateTime &accessExpiresAt,
                   const QString &webhookId,
                   bool ignoreSslErrors);
    void start();
    void stop();

signals:
    void connectedChanged();
    void accessTokenStale();
    void authenticationFailed(const QString &message);
    void notificationReceived(const QString &title,
                              const QString &message,
                              const QVariantMap &data);

private slots:
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &message);
    void onError(QAbstractSocket::SocketError error);
    void onSslErrors(const QList<QSslError> &errors);
    void openSocket();
    void sendPing();
    void onPongTimeout();

private:
    void setConnected(bool connected);
    void sendJson(const QJsonObject &obj);
    void subscribePushChannel();
    void confirmNotification(const QString &confirmId);
    void startKeepalive();
    void stopKeepalive();
    void scheduleReconnect();
    bool accessTokenFresh() const;
    QUrl websocketUrl() const;
    int nextMessageId();

    QWebSocket *m_socket;
    QTimer m_reconnectTimer;
    QTimer m_pingTimer;
    QTimer m_pongTimer;
    QString m_baseUrl;
    QString m_accessToken;
    QDateTime m_accessExpiresAt;
    QString m_webhookId;
    bool m_ignoreSslErrors;
    bool m_connected;
    bool m_wantRunning;
    bool m_authenticated;
    int m_nextId;
    int m_pushSubscriptionId;
    int m_pendingPingId;
    int m_reconnectAttempt;
};

#endif
