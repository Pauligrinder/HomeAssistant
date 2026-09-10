#include "hasscamerastream.h"

#include <QDir>
#include <QFile>
#include <QImage>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QUrl>
#include <QDebug>

namespace {

const char *kClientName = "Helmsman";
const QByteArray kJpegSoi("\xFF\xD8", 2);
const QByteArray kJpegEoi("\xFF\xD9", 2);

int contentLengthOf(const QByteArray &headers)
{
    const int idx = headers.toLower().indexOf("content-length:");
    if (idx < 0)
        return -1;
    const int start = idx + 15;
    const int end = headers.indexOf('\n', start);
    QByteArray value = headers.mid(start, end < 0 ? -1 : end - start).trimmed();
    bool ok = false;
    const int length = value.toInt(&ok);
    return (ok && length > 0) ? length : -1;
}

bool looksLikeHeaders(const QByteArray &headers)
{
    const QByteArray lower = headers.toLower();
    return lower.contains("content-type:") || lower.contains("content-length:");
}

} // namespace

HassCameraStream::HassCameraStream(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_reply(0)
    , m_ignoreSslErrors(false)
    , m_playing(false)
    , m_loading(false)
    , m_wantPlaying(false)
    , m_redirects(0)
    , m_slot(0)
    , m_generation(0)
    , m_frameWidth(0)
    , m_frameHeight(0)
{
    m_reconnectTimer.setSingleShot(true);
    m_reconnectTimer.setInterval(2000);
    connect(&m_reconnectTimer, SIGNAL(timeout()), this, SLOT(reconnect()));
}

HassCameraStream::~HassCameraStream()
{
    m_wantPlaying = false;
    abortReply();
}

void HassCameraStream::configure(const QString &baseUrl,
                                 const QString &accessToken,
                                 bool ignoreSslErrors)
{
    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_ignoreSslErrors = ignoreSslErrors;
    if (m_wantPlaying && !m_entityId.isEmpty())
        openStream();
}

QString HassCameraStream::entityId() const { return m_entityId; }
bool HassCameraStream::playing() const { return m_playing; }
bool HassCameraStream::loading() const { return m_loading; }
QString HassCameraStream::error() const { return m_error; }
QString HassCameraStream::frameUrl() const { return m_frameUrl; }
int HassCameraStream::frameWidth() const { return m_frameWidth; }
int HassCameraStream::frameHeight() const { return m_frameHeight; }

void HassCameraStream::start(const QString &entityId)
{
    if (entityId.isEmpty())
        return;
    if (m_wantPlaying && m_entityId == entityId && m_reply)
        return;

    const bool entityChanged = m_entityId != entityId;
    m_wantPlaying = true;
    if (entityChanged) {
        m_entityId = entityId;
        emit entityIdChanged();
        if (!m_frameUrl.isEmpty()) {
            m_frameUrl.clear();
            emit frameUrlChanged();
        }
        if (m_frameWidth != 0 || m_frameHeight != 0) {
            m_frameWidth = 0;
            m_frameHeight = 0;
            emit frameSizeChanged();
        }
    }
    setError(QString());
    openStream();
}

void HassCameraStream::stop()
{
    m_wantPlaying = false;
    m_reconnectTimer.stop();
    abortReply();
    m_buffer.clear();
    setPlaying(false);
    setLoading(false);
}

void HassCameraStream::restart()
{
    if (m_entityId.isEmpty())
        return;
    m_wantPlaying = true;
    setError(QString());
    openStream();
}

void HassCameraStream::openStream(int redirects)
{
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty() || m_entityId.isEmpty()) {
        setLoading(false);
        setPlaying(false);
        setError(QStringLiteral("Camera stream is not ready."));
        return;
    }
    openUrl(streamUrl(), redirects);
}

void HassCameraStream::openUrl(const QUrl &url, int redirects)
{
    abortReply();
    m_reconnectTimer.stop();
    m_buffer.clear();
    m_redirects = redirects;

    if (!url.isValid()) {
        setError(QStringLiteral("Invalid camera stream URL."));
        setLoading(false);
        return;
    }

    setLoading(m_frameUrl.isEmpty());
    QNetworkRequest request(url);
    request.setRawHeader("Accept", "multipart/x-mixed-replace,image/*,*/*;q=0.8");
    request.setRawHeader("User-Agent", kClientName);
    if (isSameOrigin(url) && !m_accessToken.isEmpty())
        request.setRawHeader("Authorization",
                             QByteArray("Bearer ") + m_accessToken.toUtf8());

    m_reply = m_nam->get(request);
    connect(m_reply, SIGNAL(readyRead()), this, SLOT(onReadyRead()));
    connect(m_reply, SIGNAL(finished()), this, SLOT(onFinished()));
    connect(m_reply, SIGNAL(sslErrors(QList<QSslError>)),
            this, SLOT(onSslErrors(QList<QSslError>)));
}

void HassCameraStream::abortReply()
{
    if (!m_reply)
        return;
    m_reply->disconnect(this);
    m_reply->abort();
    m_reply->deleteLater();
    m_reply = 0;
}

QUrl HassCameraStream::streamUrl() const
{
    QString base = m_baseUrl;
    if (base.endsWith(QLatin1Char('/')))
        base.chop(1);
    return QUrl(base + QStringLiteral("/api/camera_proxy_stream/") + m_entityId);
}

bool HassCameraStream::isSameOrigin(const QUrl &url) const
{
    const QUrl home(m_baseUrl);
    const int urlPort = url.port(url.scheme() == QLatin1String("https") ? 443 : 80);
    const int homePort = home.port(home.scheme() == QLatin1String("https") ? 443 : 80);
    return url.scheme().compare(home.scheme(), Qt::CaseInsensitive) == 0
            && url.host().compare(home.host(), Qt::CaseInsensitive) == 0
            && urlPort == homePort;
}

QString HassCameraStream::cacheDir() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
            + QStringLiteral("/hass-camera");
    QDir().mkpath(dir);
    return dir;
}

void HassCameraStream::onReadyRead()
{
    if (!m_reply)
        return;

    const QUrl redirect = m_reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
    if (redirect.isValid()) {
        if (m_redirects >= 5) {
            setError(QStringLiteral("Camera stream redirect limit reached."));
            stop();
            return;
        }
        const QUrl next = m_reply->url().resolved(redirect);
        openUrl(next, m_redirects + 1);
        return;
    }

    const int status = m_reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status != 0 && (status < 200 || status >= 300) && status != 301 && status != 302
            && status != 303 && status != 307 && status != 308) {
        return;
    }

    m_buffer.append(m_reply->readAll());
    processBuffer();
}

void HassCameraStream::onFinished()
{
    QNetworkReply *reply = m_reply;
    if (!reply)
        return;

    const QUrl redirect = reply->attribute(QNetworkRequest::RedirectionTargetAttribute).toUrl();
    if (redirect.isValid() && m_wantPlaying) {
        if (m_redirects >= 5) {
            setError(QStringLiteral("Camera stream redirect limit reached."));
            m_reply = 0;
            reply->deleteLater();
            setPlaying(false);
            setLoading(false);
            return;
        }
        const int nextRedirects = m_redirects + 1;
        const QUrl next = reply->url().resolved(redirect);
        m_reply = 0;
        reply->deleteLater();
        openUrl(next, nextRedirects);
        return;
    }

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError nerr = reply->error();
    const QString errorString = reply->errorString();
    m_reply = 0;
    reply->deleteLater();
    m_buffer.clear();
    setPlaying(false);
    setLoading(false);

    if (!m_wantPlaying)
        return;

    if (nerr == QNetworkReply::OperationCanceledError)
        return;

    if (status == 401 || status == 403) {
        setError(QStringLiteral("Camera stream was denied."));
        return;
    }
    if (status == 404) {
        setError(QStringLiteral("Camera stream was not found."));
        return;
    }
    if (nerr != QNetworkReply::NoError && m_frameUrl.isEmpty())
        setError(errorString);

    // Home Assistant closes idle MJPEG connections; keep the player going.
    m_reconnectTimer.start();
}

void HassCameraStream::onSslErrors(const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (m_ignoreSslErrors && reply)
        reply->ignoreSslErrors();
}

void HassCameraStream::reconnect()
{
    if (m_wantPlaying)
        openStream();
}

void HassCameraStream::processBuffer()
{
    if (m_buffer.size() > 2 * 1024 * 1024) {
        const int soi = m_buffer.indexOf(kJpegSoi);
        if (soi > 0)
            m_buffer.remove(0, soi);
        else
            m_buffer.clear();
    }

    while (true) {
        const int headerEnd = m_buffer.indexOf("\r\n\r\n");
        if (headerEnd >= 0) {
            const QByteArray headers = m_buffer.left(headerEnd);
            if (looksLikeHeaders(headers)) {
                const int length = contentLengthOf(headers);
                if (length > 0) {
                    const int dataStart = headerEnd + 4;
                    if (m_buffer.size() < dataStart + length)
                        return;
                    const QByteArray jpeg = m_buffer.mid(dataStart, length);
                    m_buffer.remove(0, dataStart + length);
                    if (m_buffer.startsWith("\r\n"))
                        m_buffer.remove(0, 2);
                    publishFrame(jpeg);
                    continue;
                }
            }
        }

        const int soi = m_buffer.indexOf(kJpegSoi);
        if (soi < 0) {
            if (m_buffer.size() > 16384)
                m_buffer = m_buffer.right(2);
            return;
        }
        if (soi > 0)
            m_buffer.remove(0, soi);
        const int eoi = m_buffer.indexOf(kJpegEoi, 2);
        if (eoi < 0)
            return;
        const QByteArray jpeg = m_buffer.left(eoi + 2);
        m_buffer.remove(0, eoi + 2);
        publishFrame(jpeg);
    }
}

void HassCameraStream::publishFrame(const QByteArray &jpeg)
{
    if (jpeg.size() < 24 || !jpeg.startsWith(kJpegSoi))
        return;

    m_slot = 1 - m_slot;
    const QString path = cacheDir()
            + (m_slot ? QStringLiteral("/frame-a.jpg") : QStringLiteral("/frame-b.jpg"));
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "Helmsman camera: cannot write frame" << path;
        return;
    }
    if (file.write(jpeg) != jpeg.size()) {
        qWarning() << "Helmsman camera: short write for frame" << path;
        return;
    }
    file.flush();
    file.close();

    if (m_frameWidth <= 0 || m_frameHeight <= 0) {
        const QImage image = QImage::fromData(jpeg, "JPEG");
        if (!image.isNull()) {
            m_frameWidth = image.width();
            m_frameHeight = image.height();
            emit frameSizeChanged();
        }
    }

    m_generation += 1;
    m_frameUrl = QStringLiteral("file://") + path
            + QLatin1Char('#') + QString::number(m_generation);
    emit frameUrlChanged();
    setError(QString());
    setLoading(false);
    setPlaying(true);
}

void HassCameraStream::setPlaying(bool playing)
{
    if (m_playing == playing)
        return;
    m_playing = playing;
    emit playingChanged();
}

void HassCameraStream::setLoading(bool loading)
{
    if (m_loading == loading)
        return;
    m_loading = loading;
    emit loadingChanged();
}

void HassCameraStream::setError(const QString &message)
{
    if (m_error == message)
        return;
    m_error = message;
    emit errorChanged();
}
