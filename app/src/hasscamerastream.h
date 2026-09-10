#ifndef HASSCAMERASTREAM_H
#define HASSCAMERASTREAM_H

#include <QByteArray>
#include <QObject>
#include <QSslError>
#include <QString>
#include <QTimer>
#include <QUrl>
#include <QList>

class QNetworkAccessManager;
class QNetworkReply;

// Live camera player for the native more-info page. Home Assistant serves
// cameras as a multipart MJPEG stream at /api/camera_proxy_stream/{entity};
// this class keeps that connection open and writes each JPEG so QML can
// show it as video.
class HassCameraStream : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString entityId READ entityId NOTIFY entityIdChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(QString frameUrl READ frameUrl NOTIFY frameUrlChanged)
    Q_PROPERTY(int frameWidth READ frameWidth NOTIFY frameSizeChanged)
    Q_PROPERTY(int frameHeight READ frameHeight NOTIFY frameSizeChanged)

public:
    explicit HassCameraStream(QObject *parent = 0);
    ~HassCameraStream() override;

    void configure(const QString &baseUrl,
                   const QString &accessToken,
                   bool ignoreSslErrors);

    QString entityId() const;
    bool playing() const;
    bool loading() const;
    QString error() const;
    QString frameUrl() const;
    int frameWidth() const;
    int frameHeight() const;

public slots:
    void start(const QString &entityId);
    void stop();
    void restart();

signals:
    void entityIdChanged();
    void playingChanged();
    void loadingChanged();
    void errorChanged();
    void frameUrlChanged();
    void frameSizeChanged();

private slots:
    void onReadyRead();
    void onFinished();
    void onSslErrors(const QList<QSslError> &errors);
    void reconnect();

private:
    void openStream(int redirects = 0);
    void openUrl(const QUrl &url, int redirects);
    void abortReply();
    void processBuffer();
    void publishFrame(const QByteArray &jpeg);
    void setPlaying(bool playing);
    void setLoading(bool loading);
    void setError(const QString &message);
    QUrl streamUrl() const;
    bool isSameOrigin(const QUrl &url) const;
    QString cacheDir() const;

    QNetworkAccessManager *m_nam;
    QNetworkReply *m_reply;
    QTimer m_reconnectTimer;
    QString m_baseUrl;
    QString m_accessToken;
    QString m_entityId;
    QString m_error;
    QString m_frameUrl;
    QByteArray m_buffer;
    bool m_ignoreSslErrors;
    bool m_playing;
    bool m_loading;
    bool m_wantPlaying;
    int m_redirects;
    int m_slot;
    int m_generation;
    int m_frameWidth;
    int m_frameHeight;
};

#endif
