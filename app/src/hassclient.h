#ifndef HASSCLIENT_H
#define HASSCLIENT_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantMap>
#include <QJsonObject>
#include <QDateTime>
#include <QSslError>
#include <QList>
#include <QUrlQuery>

class QNetworkAccessManager;
class QNetworkReply;
class QNetworkRequest;

class HassClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY loggedInChanged)
    Q_PROPERTY(bool needsOtp READ needsOtp NOTIFY needsOtpChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY errorMessageChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(bool useSsl READ useSsl WRITE setUseSsl NOTIFY useSslChanged)
    Q_PROPERTY(bool ignoreSslErrors READ ignoreSslErrors WRITE setIgnoreSslErrors NOTIFY ignoreSslErrorsChanged)
    Q_PROPERTY(QString username READ username NOTIFY usernameChanged)
    Q_PROPERTY(QString instanceName READ instanceName NOTIFY instanceNameChanged)
    Q_PROPERTY(QString haVersion READ haVersion NOTIFY haVersionChanged)
    Q_PROPERTY(QString otpHint READ otpHint NOTIFY otpHintChanged)
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY baseUrlChanged)

public:
    explicit HassClient(QObject *parent = nullptr);
    ~HassClient() override;

    QString appVersion() const;
    bool busy() const;
    bool connected() const;
    bool loggedIn() const;
    bool needsOtp() const;
    QString errorMessage() const;
    QString statusText() const;
    QString host() const;
    int port() const;
    bool useSsl() const;
    bool ignoreSslErrors() const;
    QString username() const;
    QString instanceName() const;
    QString haVersion() const;
    QString otpHint() const;
    QString baseUrl() const;

    void setHost(const QString &host);
    void setPort(int port);
    void setUseSsl(bool useSsl);
    void setIgnoreSslErrors(bool ignore);

public slots:
    void restoreSession();
    void connectToInstance(const QString &endpoint, bool useSsl, bool ignoreSslErrors);
    void login(const QString &username, const QString &password);
    void submitOtp(const QString &code);
    void logout();

signals:
    void busyChanged();
    void connectedChanged();
    void loggedInChanged();
    void needsOtpChanged();
    void errorMessageChanged();
    void statusTextChanged();
    void hostChanged();
    void portChanged();
    void useSslChanged();
    void ignoreSslErrorsChanged();
    void usernameChanged();
    void instanceNameChanged();
    void haVersionChanged();
    void otpHintChanged();
    void baseUrlChanged();
    void restoreFinished(bool loggedIn);
    void connectionSucceeded();
    void loginSucceeded();
    void otpRequired();
    void loginFailed(const QString &message);

private slots:
    void onReplyFinished();
    void onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors);

private:
    enum RequestKind {
        RequestNone,
        RequestProviders,
        RequestStartFlow,
        RequestSubmitFlow,
        RequestToken,
        RequestRefresh,
        RequestConfig,
        RequestRevoke
    };

    void setBusy(bool busy);
    void setError(const QString &message);
    void clearError();
    void setStatus(const QString &text);
    void setConnected(bool connected);
    void setLoggedIn(bool loggedIn);
    void setNeedsOtp(bool needsOtp);

    bool parseEndpoint(const QString &endpoint, QString *error);
    void rebuildBaseUrl();
    QUrl apiUrl(const QString &path) const;
    QString clientId() const;

    void get(const QString &path, RequestKind kind);
    void postJson(const QString &path, const QJsonObject &body, RequestKind kind);
    void postForm(const QString &path, const QUrlQuery &form, RequestKind kind);
    void watch(QNetworkReply *reply, RequestKind kind);

    void handleProviders(const QByteArray &data);
    void handleFlowStep(const QByteArray &data);
    void handleToken(const QByteArray &data, bool fromRefresh);
    void handleConfig(const QByteArray &data);
    void startLoginFlow();
    void submitFlow(const QJsonObject &fields);
    void exchangeCode(const QString &code);
    void fetchConfig();
    void persistSession();
    void clearPersistedTokens();
    void applyTokens(const QVariantMap &obj, bool keepRefreshIfMissing);

    QNetworkAccessManager *m_nam;
    RequestKind m_pendingKind;
    QNetworkReply *m_pendingReply;

    bool m_busy;
    bool m_connected;
    bool m_loggedIn;
    bool m_needsOtp;
    bool m_useSsl;
    bool m_ignoreSslErrors;
    int m_port;
    QString m_host;
    QString m_baseUrl;
    QString m_errorMessage;
    QString m_statusText;
    QString m_username;
    QString m_instanceName;
    QString m_haVersion;
    QString m_otpHint;
    QString m_flowId;
    QString m_authCode;
    QString m_accessToken;
    QString m_refreshToken;
    QDateTime m_accessExpiresAt;
    QString m_providerType;
    QVariant m_providerId;
};

#endif
