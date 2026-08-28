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
#include <QTimer>

#include "sensorcoordinator.h"
#include "widgetcoordinator.h"

class QNetworkAccessManager;
class QNetworkReply;
class QNetworkRequest;
class HassPushChannel;

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
    Q_PROPERTY(QString accessToken READ accessToken NOTIFY accessTokenChanged)
    Q_PROPERTY(QString refreshToken READ refreshToken NOTIFY refreshTokenChanged)
    Q_PROPERTY(QString authClientId READ authClientId CONSTANT)
    Q_PROPERTY(qint64 accessExpiresAtMs READ accessExpiresAtMs NOTIFY accessExpiresAtChanged)
    Q_PROPERTY(bool restoringSession READ restoringSession NOTIFY restoringSessionChanged)
    Q_PROPERTY(bool testingConnection READ testingConnection NOTIFY testingConnectionChanged)
    Q_PROPERTY(QString internalUrl READ internalUrl WRITE setInternalUrl NOTIFY internalUrlChanged)
    Q_PROPERTY(QString externalUrl READ externalUrl WRITE setExternalUrl NOTIFY externalUrlChanged)
    Q_PROPERTY(QString homeWifiSsid READ homeWifiSsid WRITE setHomeWifiSsid NOTIFY homeWifiSsidChanged)
    Q_PROPERTY(QString currentWifiSsid READ currentWifiSsid NOTIFY currentWifiSsidChanged)
    Q_PROPERTY(bool usingInternalUrl READ usingInternalUrl NOTIFY usingInternalUrlChanged)
    Q_PROPERTY(QString webhookId READ webhookId NOTIFY webhookIdChanged)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY deviceNameChanged)
    Q_PROPERTY(bool mobileAppRegistered READ mobileAppRegistered NOTIFY mobileAppRegisteredChanged)
    Q_PROPERTY(bool pushConnected READ pushConnected NOTIFY pushConnectedChanged)
    Q_PROPERTY(QString dashboardSnapshotPath READ dashboardSnapshotPath CONSTANT)
    Q_PROPERTY(SensorCoordinator *sensors READ sensors CONSTANT)
    Q_PROPERTY(WidgetCoordinator *widget READ widget CONSTANT)

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
    QString accessToken() const;
    QString refreshToken() const;
    QString authClientId() const;
    qint64 accessExpiresAtMs() const;
    bool restoringSession() const;
    bool testingConnection() const;
    QString internalUrl() const;
    QString externalUrl() const;
    QString homeWifiSsid() const;
    QString currentWifiSsid() const;
    bool usingInternalUrl() const;
    QString webhookId() const;
    QString deviceName() const;
    bool mobileAppRegistered() const;
    bool pushConnected() const;
    QString dashboardSnapshotPath() const;
    SensorCoordinator *sensors() const;
    WidgetCoordinator *widget() const;

    void setHost(const QString &host);
    void setPort(int port);
    void setUseSsl(bool useSsl);
    void setIgnoreSslErrors(bool ignore);
    void setInternalUrl(const QString &url);
    void setExternalUrl(const QString &url);
    void setHomeWifiSsid(const QString &ssid);

public slots:
    void restoreSession();
    void cancelRestore();
    void testEndpoint(const QString &endpoint, bool ignoreSslErrors);
    void connectToInstance(const QString &endpoint, bool useSsl, bool ignoreSslErrors);
    void connectToConfiguredInstance();
    void login(const QString &username, const QString &password);
    void submitOtp(const QString &code);
    void logout();
    void saveConnectionSettings(const QString &internalUrl,
                                const QString &externalUrl,
                                const QString &homeWifiSsid,
                                bool ignoreSslErrors);
    void updateNetworkState(bool wifiReady, bool wifiConnected, const QString &ssid);
    void applyEndpointNow();
    void refreshAccessToken();
    void rememberDashboardSnapshot(const QString &baseUrl);
    bool dashboardSnapshotMatches(const QString &baseUrl) const;
    void clearDashboardSnapshot();
    void notifyAppForegrounded();
    void notifyDashboardReady();

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
    void accessTokenChanged();
    void refreshTokenChanged();
    void accessExpiresAtChanged();
    void restoringSessionChanged();
    void testingConnectionChanged();
    void internalUrlChanged();
    void externalUrlChanged();
    void homeWifiSsidChanged();
    void currentWifiSsidChanged();
    void usingInternalUrlChanged();
    void webhookIdChanged();
    void deviceNameChanged();
    void mobileAppRegisteredChanged();
    void pushConnectedChanged();
    void restoreFinished(bool loggedIn);
    void connectionTestFinished(const QString &endpoint, bool success, const QString &message);
    void connectionSucceeded();
    void loginSucceeded();
    void otpRequired();
    void loginFailed(const QString &message);
    void notificationReceived(const QString &title,
                              const QString &message,
                              const QVariantMap &data);

private slots:
    void onReplyFinished();
    void onTestReplyFinished();
    void onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors);
    void onPushConnectedChanged();
    void onAccessTokenStale();
    void onPushAuthenticationFailed(const QString &message);
    void onTokenRefreshTimeout();
    void onPushNotificationReceived(const QString &title,
                                    const QString &message,
                                    const QVariantMap &data);
    void onEndpointDebounceTimeout();
    void onSensorStartTimeout();
    void onWidgetStartTimeout();
    void configureWidget();
    void syncWidgetRunning();

private:
    enum RequestKind {
        RequestNone,
        RequestProviders,
        RequestStartFlow,
        RequestSubmitFlow,
        RequestToken,
        RequestRefresh,
        RequestConfig,
        RequestRevoke,
        RequestMobileRegister
    };

    enum NetworkState {
        NetworkUnknown,  // ConnMan has not reported yet
        NetworkNoWifi,   // mobile data or no connectivity at all
        NetworkWifi
    };

    void setBusy(bool busy);
    void setError(const QString &message);
    void clearError();
    void setStatus(const QString &text);
    void setConnected(bool connected);
    void setLoggedIn(bool loggedIn);
    void setNeedsOtp(bool needsOtp);
    void setRestoringSession(bool restoring);

    bool parseEndpoint(const QString &endpoint, QString *error);
    void rebuildBaseUrl();
    void persistConnectionSettings();
    void setUsingInternalUrl(bool usingInternal);
    QUrl apiUrl(const QString &path) const;
    QString clientId() const;

    void get(const QString &path, RequestKind kind);
    void postJson(const QString &path, const QJsonObject &body, RequestKind kind);
    void postForm(const QString &path, const QUrlQuery &form, RequestKind kind, bool busy = true);
    void watch(QNetworkReply *reply, RequestKind kind, bool busy = true);

    void handleProviders(const QByteArray &data);
    void handleFlowStep(const QByteArray &data);
    void handleToken(const QByteArray &data, bool fromRefresh);
    void handleConfig(const QByteArray &data);
    void handleMobileRegistration(const QByteArray &data);
    void startLoginFlow();
    void submitFlow(const QJsonObject &fields);
    void exchangeCode(const QString &code);
    void fetchConfig();
    void ensureDeviceId();
    void ensureDeviceName();
    void ensureMobileAppRegistration();
    void registerMobileApp();
    void startPushChannel();
    void stopPushChannel();
    void clearMobileRegistration();
    void configureSensors();
    void scheduleSensorStart(int delayMs);
    void startSensors();
    void stopSensors();
    void scheduleWidgetStart(int delayMs);
    void startWidget();
    void stopWidget();
    void loadSession();
    void persistSession();
    void clearPersistedTokens();
    void applyTokens(const QVariantMap &obj, bool keepRefreshIfMissing);
    void reconnectPushAfterEndpointChange();
    void commitNetworkState();
    bool selectEndpointForNetwork();
    void scheduleTokenRefresh();
    bool startQuietTokenRefresh();
    bool accessTokenStillFresh(int minSecondsLeft = 120) const;

    QNetworkAccessManager *m_nam;
    HassPushChannel *m_pushChannel;
    SensorCoordinator *m_sensors;
    WidgetCoordinator *m_widget;
    RequestKind m_pendingKind;
    QNetworkReply *m_pendingReply;
    QTimer m_endpointDebounceTimer;
    QTimer m_tokenRefreshTimer;
    QTimer m_sensorStartTimer;
    QTimer m_widgetStartTimer;

    bool m_busy;
    bool m_connected;
    bool m_loggedIn;
    bool m_needsOtp;
    bool m_useSsl;
    bool m_ignoreSslErrors;
    bool m_usingInternalUrl;
    bool m_restoringSession;
    bool m_testingConnection;
    bool m_testIgnoreSslErrors;
    bool m_pendingPushAfterRefresh;
    NetworkState m_networkState;
    NetworkState m_pendingNetworkState;
    int m_pushAuthRetries;
    int m_pushRefreshFailures;
    int m_port;
    QNetworkReply *m_testReply;
    QString m_testEndpoint;
    QString m_host;
    QString m_baseUrl;
    QString m_internalUrl;
    QString m_externalUrl;
    QString m_homeWifiSsid;
    QString m_currentWifiSsid;
    QString m_pendingWifiSsid;
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
    QString m_authClientId;
    QDateTime m_accessExpiresAt;
    QString m_providerType;
    QVariant m_providerId;
    QString m_deviceId;
    QString m_deviceName;
    QString m_webhookId;
    QString m_webhookSecret;
    QString m_cloudhookUrl;
    QString m_remoteUiUrl;
};

#endif
