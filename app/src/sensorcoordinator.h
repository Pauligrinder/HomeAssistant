#ifndef SENSORCOORDINATOR_H
#define SENSORCOORDINATOR_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <QJsonObject>
#include <QJsonArray>
#include <QTimer>
#include <QDateTime>
#include <QSslError>
#include <QList>

class QNetworkAccessManager;
class QNetworkReply;

// Registers and updates mobile_app sensors over the HA webhook, matching
// Android companion unique_ids. Home Assistant enable/disable is the source
// of truth (get_config + is_disabled on updates).
class SensorCoordinator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList sensorStatuses READ sensorStatuses NOTIFY sensorStatusesChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(bool locationReporting READ locationReporting NOTIFY locationReportingChanged)
    Q_PROPERTY(bool locationEnabled READ locationEnabled WRITE setLocationEnabled NOTIFY locationEnabledChanged)
    Q_PROPERTY(int locationPreset READ locationPreset WRITE setLocationPreset NOTIFY locationPresetChanged)
    Q_PROPERTY(int locationStaleMinutes READ locationStaleMinutes WRITE setLocationStaleMinutes NOTIFY locationStaleMinutesChanged)
    Q_PROPERTY(bool homeOnInternal READ homeOnInternal WRITE setHomeOnInternal NOTIFY homeOnInternalChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString lastLocationText READ lastLocationText NOTIFY lastLocationTextChanged)

public:
    explicit SensorCoordinator(QObject *parent = nullptr);

    QVariantList sensorStatuses() const;
    bool active() const;
    bool locationReporting() const;
    bool locationEnabled() const;
    int locationPreset() const;
    int locationStaleMinutes() const;
    bool homeOnInternal() const;
    QString lastError() const;
    QString lastLocationText() const;

    // Called by HassClient when webhook credentials / base URL change.
    void configure(const QString &webhookId,
                   const QString &cloudhookUrl,
                   const QString &remoteUiUrl,
                   const QString &baseUrl,
                   bool ignoreSslErrors);
    void start();
    void stop();

public slots:
    void updateBattery(int levelPercent, bool charging, const QString &state, const QString &chargerType);
    void updateWifi(const QString &ssid, bool connected);
    void updateLocation(double latitude, double longitude, double accuracyMeters, int batteryPercent);
    void setUsingInternalUrl(bool usingInternal);
    void setSensorEnabled(const QString &uniqueId, bool enabled);
    void setLocationEnabled(bool enabled);
    void setLocationPreset(int preset);
    void setLocationStaleMinutes(int minutes);
    void setHomeOnInternal(bool enabled);
    void refreshLocation();
    void onAppForegrounded();
    void refreshConfig();

signals:
    void sensorStatusesChanged();
    void activeChanged();
    void locationReportingChanged();
    void locationEnabledChanged();
    void locationPresetChanged();
    void locationStaleMinutesChanged();
    void homeOnInternalChanged();
    void lastErrorChanged();
    void lastLocationTextChanged();
    void locationRefreshRequested();

private slots:
    void onWebhookFinished();
    void onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors);
    void onPeriodicTimeout();
    void onConfigRefreshTimeout();
    void onUpdateDebounceTimeout();
    void onStartupStepTimeout();
    void onHomeHeartbeatTimeout();

private:
    enum WebhookKind {
        WebhookNone,
        WebhookGetConfig,
        WebhookRegisterSensor,
        WebhookUpdateSensors,
        WebhookUpdateLocation
    };

    struct SensorDef {
        QString uniqueId;
        QString name;
        QString type;          // sensor | binary_sensor
        QString deviceClass;
        QString unit;
        QString stateClass;
        QString icon;
        QString entityCategory;
        bool defaultDisabled;
    };

    struct SensorRuntime {
        QVariant state;
        QVariantMap attributes;
        QString icon;
        bool registered;
        bool disabled;         // from HA
        bool locallyEnabled;
        bool dirty;
        QString lastError;
        QDateTime lastUpdated;
    };

    void loadPersistedState();
    void persistState() const;
    QStringList registeredIds() const;
    void setRegisteredIds(const QStringList &ids);

    void setLastError(const QString &message);
    void setActive(bool active);
    void updateLocationReporting();
    void updateHomeHeartbeat();
    void postLocationUpdate(bool force);
    void ensureOsVersionSensor();
    void setSensorState(const QString &id, const QVariant &state,
                        const QString &icon, const QVariantMap &attrs = QVariantMap());

    QUrl webhookUrl(int attempt) const;
    void postWebhook(WebhookKind kind, const QJsonObject &body, int urlAttempt = 0);
    void handleGetConfig(const QByteArray &data);
    void handleRegisterSensor(const QByteArray &data, int status, const QString &uniqueId);
    void handleUpdateSensors(const QByteArray &data);
    void handleUpdateLocation(const QByteArray &data, int status);

    void ensureRegistrations();
    void registerNextPending();
    QJsonObject buildRegisterPayload(const SensorDef &def, const SensorRuntime &rt) const;
    void scheduleSensorUpdate();
    void flushSensorUpdates();
    void rebuildStatusList();
    bool isSensorEnabled(const QString &uniqueId) const;
    SensorDef defFor(const QString &uniqueId) const;

    static QList<SensorDef> builtInSensors();
    static QString batteryIconFor(int level, bool charging);

    QNetworkAccessManager *m_nam;
    QTimer m_periodicTimer;
    QTimer m_configTimer;
    QTimer m_updateDebounce;
    QTimer m_startupTimer;
    QTimer m_homeHeartbeatTimer;
    int m_startupStep;

    QString m_webhookId;
    QString m_cloudhookUrl;
    QString m_remoteUiUrl;
    QString m_baseUrl;
    bool m_ignoreSslErrors;
    bool m_active;
    bool m_locationEnabled;
    bool m_locationDisabledInHa;
    int m_locationPreset;
    int m_locationStaleMinutes;
    bool m_homeOnInternal;
    bool m_usingInternalUrl;
    bool m_started;
    bool m_registrationInFlight;
    QString m_lastError;
    QString m_lastLocationText;
    QVariantList m_statusList;

    QList<SensorDef> m_defs;
    QHash<QString, SensorRuntime> m_runtime;
    QStringList m_registerQueue;

    int m_batteryLevel;
    bool m_haveBattery;
    bool m_haveWifi;
    bool m_haveLocation;
    QDateTime m_lastLocationSent;
    double m_lastLat;
    double m_lastLon;
    double m_lastAccuracy;
};

#endif
