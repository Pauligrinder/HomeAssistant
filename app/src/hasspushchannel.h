#ifndef HASSPUSHCHANNEL_H
#define HASSPUSHCHANNEL_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QTimer>
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
                   const QString &webhookId,
                   bool ignoreSslErrors);
    void start();
    void stop();

signals:
    void connectedChanged();
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

private:
    void setConnected(bool connected);
    void sendJson(const QJsonObject &obj);
    void subscribePushChannel();
    void confirmNotification(const QString &confirmId);
    void scheduleReconnect();
    QUrl websocketUrl() const;
    int nextMessageId();

    QWebSocket *m_socket;
    QTimer m_reconnectTimer;
    QString m_baseUrl;
    QString m_accessToken;
    QString m_webhookId;
    bool m_ignoreSslErrors;
    bool m_connected;
    bool m_wantRunning;
    bool m_authenticated;
    int m_nextId;
    int m_pushSubscriptionId;
    int m_reconnectAttempt;
};

#endif
