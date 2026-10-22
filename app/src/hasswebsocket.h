#ifndef HASSWEBSOCKET_H
#define HASSWEBSOCKET_H

#include <QObject>
#include <QString>
#include <QByteArray>
#include <QVariant>
#include <QVariantMap>
#include <QJsonObject>
#include <QDateTime>
#include <QTimer>
#include <QAbstractSocket>
#include <QList>
#include <QSslError>
#include <QUrl>

class QTcpSocket;
class QThread;

// Lives on the IO thread. Socket open/close and SSL teardown can block for a
// long time when the network path is gone; that must not be the GUI thread.
//
// Custom handshake (not QWebSocket): Sailfish Qt 5.6 always sends
// Host: name:443 which breaks reverse proxies that ACL on the bare hostname.
// Browsers / WebView omit the default port; we match that and set Origin.
class HassWsTransport : public QObject
{
    Q_OBJECT
public:
    explicit HassWsTransport(QObject *parent = 0);

public slots:
    void openUrl(QUrl url, bool ignoreSsl, int epoch);
    void closeSocket();
    void sendText(QString text);

signals:
    void opened(int epoch);
    void closed(int epoch);
    void textReceived(const QString &message);
    void errorText(const QString &error);

private slots:
    void onTcpConnected();
    void onEncrypted();
    void onDisconnected();
    void onReadyRead();
    void onError(QAbstractSocket::SocketError error);
    void onSslErrors(const QList<QSslError> &errors);

private:
    void bindSocket(bool ssl);
    void destroySocket();
    void failHandshake(const QString &message);
    void sendHandshake();
    bool consumeHandshake();
    void consumeFrames();
    QByteArray encodeTextFrame(const QByteArray &payload) const;
    static QString hostHeader(const QUrl &url);
    static QString originHeader(const QUrl &wsUrl);
    static QByteArray makeWsKey();

    QTcpSocket *m_socket;
    QUrl m_url;
    QByteArray m_buffer;
    QByteArray m_wsKey;
    QByteArray m_fragment;
    bool m_ignoreSsl;
    bool m_handshakeDone;
    bool m_closing;
    bool m_fragmentOpcodeText;
    int m_epoch;
};

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
    // Handshake / transport failed before auth (proxy 404, TLS, timeout, …).
    void connectionFailed(const QString &message);
    void connectionReady();
    void resultReceived(int id, bool success, const QVariant &result, const QVariantMap &error);
    void eventReceived(int id, const QVariantMap &event);

private slots:
    void onConnected(int epoch);
    void onDisconnected(int epoch);
    void onTextMessageReceived(const QString &message);
    void onTransportError(const QString &error);
    void openSocket();
    void sendPing();
    void onPongTimeout();
    void onConnectTimeout();
    void reapSocket();

private:
    void setConnected(bool connected);
    void setAuthenticated(bool authenticated);
    void sendJson(const QJsonObject &obj);
    void startKeepalive();
    void stopKeepalive();
    void scheduleReconnect();
    void startIo();
    void bindTransport();
    void detachStuckIo();
    bool accessTokenFresh() const;
    QUrl websocketUrl() const;
    int nextMessageId();

    HassWsTransport *m_transport;
    QThread *m_io;
    QTimer m_reconnectTimer;
    QTimer m_connectTimer;
    QTimer m_pingTimer;
    QTimer m_pongTimer;
    QString m_baseUrl;
    QString m_accessToken;
    QDateTime m_accessExpiresAt;
    bool m_ignoreSslErrors;
    bool m_connected;
    bool m_wantRunning;
    bool m_authenticated;
    bool m_opening;
    int m_epoch;
    int m_nextId;
    int m_pendingPingId;
    int m_reconnectAttempt;
};

#endif
