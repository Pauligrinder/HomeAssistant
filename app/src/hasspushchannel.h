#ifndef HASSPUSHCHANNEL_H
#define HASSPUSHCHANNEL_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QDateTime>
#include <QVariant>

class HassWebsocket;

class HassPushChannel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    explicit HassPushChannel(QObject *parent = nullptr);
    ~HassPushChannel() override;

    bool connected() const;
    void setWebsocket(HassWebsocket *socket);

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
    void onConnectionReady();
    void onResultReceived(int id, bool success, const QVariant &result, const QVariantMap &error);
    void onEventReceived(int id, const QVariantMap &event);
    void onAuthenticatedChanged();

private:
    void subscribePushChannel();
    void confirmNotification(const QString &confirmId);

    HassWebsocket *m_socket;
    QString m_webhookId;
    bool m_wantRunning;
    bool m_subscribed;
    int m_pushSubscriptionId;
};

#endif
