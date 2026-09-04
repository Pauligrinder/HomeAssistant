#ifndef HASSWEBSOCKET_H
#define HASSWEBSOCKET_H

#include <QObject>
#include <QString>
#include <QVariant>
#include <QVariantMap>
#include <QJsonObject>
#include <QDateTime>
#include <QTimer>
#include <QAbstractSocket>
#include <QList>
#include <QSslError>

class QWebSocket;
class QUrl;

// General Home Assistant /api/websocket client. One authenticated socket is
// shared by push notifications and the native Lovelace dashboard.
class HassWebsocket : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool authenticated READ authenticated NOTIFY authenticatedChanged)

public:
    explicit HassWebsocket(QObject *parent = nullptr);
    ~HassWebsocket() override;

    bool connected() const;
    bool authenticated() const;

    void configure(const QString &baseUrl,
                   const QString &accessToken,
                   const QDateTime &accessExpiresAt,
                   bool ignoreSslErrors);
    void start();
    void stop();

    // Adds id and sends. Returns 0 if the socket is not authenticated.
    int sendCommand(QJsonObject payload);

signals:
    void connectedChanged();
    void authenticatedChanged();
    void accessTokenStale();
    void authenticationFailed(const QString &message);
    void connectionReady();
    void resultReceived(int id, bool success, const QVariant &result, const QVariantMap &error);
    void eventReceived(int id, const QVariantMap &event);

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
    void setAuthenticated(bool authenticated);
    void sendJson(const QJsonObject &obj);
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
    bool m_ignoreSslErrors;
    bool m_connected;
    bool m_wantRunning;
    bool m_authenticated;
    int m_nextId;
    int m_pendingPingId;
    int m_reconnectAttempt;
};

#endif
