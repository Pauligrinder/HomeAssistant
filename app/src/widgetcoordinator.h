#ifndef WIDGETCOORDINATOR_H
#define WIDGETCOORDINATOR_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QUrl>
#include <QTimer>
#include <QHash>
#include <QDateTime>
#include <QSslError>
#include <QList>

class QNetworkAccessManager;
class QNetworkReply;
class QFileSystemWatcher;
class MdiIconRenderer;

// Lights, switches, scripts, climate, sensors, and graphable sensors for the
// cover and Events View widget. Uses the Home Assistant REST API with the same
// session Helmsman already stores. Sensors and graph sensors are Events View only.
class WidgetCoordinator : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.helmsman.Widget")
    Q_CLASSINFO("D-Bus Introspection", ""
"  <interface name=\"org.helmsman.Widget\">\n"
"    <method name=\"GetEntitiesJson\">\n"
"      <arg direction=\"out\" type=\"s\"/>\n"
"    </method>\n"
"    <method name=\"Refresh\"/>\n"
"    <method name=\"ToggleLight\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"    </method>\n"
"    <method name=\"SetBrightnessPct\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"pct\"/>\n"
"    </method>\n"
"    <method name=\"SetColorTempKelvin\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"kelvin\"/>\n"
"    </method>\n"
"    <method name=\"SetRgbColor\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"r\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"g\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"b\"/>\n"
"    </method>\n"
"    <method name=\"SetHvacMode\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"s\" name=\"mode\"/>\n"
"    </method>\n"
"    <method name=\"SetFanLevel\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"level\"/>\n"
"    </method>\n"
"    <method name=\"SetVaneVertical\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"level\"/>\n"
"    </method>\n"
"    <method name=\"SetVaneHorizontal\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"level\"/>\n"
"    </method>\n"
"    <method name=\"SetTargetTemp\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"d\" name=\"temp\"/>\n"
"    </method>\n"
"    <method name=\"OpenFavorites\"/>\n"
"    <method name=\"RunScript\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"    </method>\n"
"    <method name=\"CancelScript\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"    </method>\n"
"    <method name=\"WidgetPresent\"/>\n"
"    <method name=\"WidgetGone\"/>\n"
"    <method name=\"DismissNotification\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"idOrTag\"/>\n"
"    </method>\n"
"    <method name=\"OpenApp\"/>\n"
"    <method name=\"ReorderEventsViewEntity\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"      <arg direction=\"in\" type=\"i\" name=\"newIndex\"/>\n"
"    </method>\n"
"    <method name=\"RemoveEventsViewEntity\">\n"
"      <arg direction=\"in\" type=\"s\" name=\"entityId\"/>\n"
"    </method>\n"
"    <signal name=\"EntitiesChanged\"/>\n"
"  </interface>\n"
"")
    Q_PROPERTY(QVariantList availableEntities READ availableEntities NOTIFY availableEntitiesChanged)
    Q_PROPERTY(QVariantList widgetEntities READ widgetEntities NOTIFY widgetEntitiesChanged)
    Q_PROPERTY(QVariantList eventsViewWidgetEntities READ eventsViewWidgetEntities NOTIFY eventsViewWidgetEntitiesChanged)
    Q_PROPERTY(QStringList selectedEntityIds READ selectedEntityIds WRITE setSelectedEntityIds NOTIFY selectedEntityIdsChanged)
    Q_PROPERTY(QStringList eventsViewSelectedEntityIds READ eventsViewSelectedEntityIds WRITE setEventsViewSelectedEntityIds NOTIFY eventsViewSelectedEntityIdsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // Set from QML so widget entities can carry a rendered icon path; the
    // events view runs in lipstick and cannot use the app image provider.
    Q_PROPERTY(MdiIconRenderer *iconRenderer READ iconRenderer WRITE setIconRenderer NOTIFY iconRendererChanged)
    // True while the Lipstick Events View widget is loaded (it heartbeats over D-Bus).
    Q_PROPERTY(bool eventsViewWidgetEnabled READ eventsViewWidgetEnabled NOTIFY eventsViewWidgetEnabledChanged)

public:
    explicit WidgetCoordinator(QObject *parent = nullptr);
    ~WidgetCoordinator() override;

    QVariantList availableEntities() const;
    QVariantList widgetEntities() const;
    QVariantList eventsViewWidgetEntities() const;
    QStringList selectedEntityIds() const;
    QStringList eventsViewSelectedEntityIds() const;
    bool busy() const;
    bool active() const;
    QString lastError() const;
    bool dbusRegistered() const;
    bool eventsViewWidgetEnabled() const;
    MdiIconRenderer *iconRenderer() const;
    void setIconRenderer(MdiIconRenderer *renderer);

    void configure(const QString &baseUrl,
                   const QString &accessToken,
                   const QDateTime &accessExpiresAt,
                   bool ignoreSslErrors);
    void start();
    void stop();

public slots:
    void setSelectedEntityIds(const QStringList &ids);
    void setEntitySelected(const QString &entityId, bool selected);
    void setEventsViewSelectedEntityIds(const QStringList &ids);
    void setEventsViewEntitySelected(const QString &entityId, bool selected);
    void reorderEventsViewEntity(const QString &entityId, int newIndex);
    void refresh();
    void refreshAvailable();
    void toggleLight(const QString &entityId);
    void setBrightnessPct(const QString &entityId, int pct);
    void setColorTempKelvin(const QString &entityId, int kelvin);
    void setRgbColor(const QString &entityId, int r, int g, int b);
    void setHvacMode(const QString &entityId, const QString &mode);
    void setFanLevel(const QString &entityId, int level);
    void setVaneVertical(const QString &entityId, int level);
    void setVaneHorizontal(const QString &entityId, int level);
    void setTargetTemp(const QString &entityId, double temp);
    void runScript(const QString &entityId);
    void cancelScript(const QString &entityId);
    void pushNotification(const QString &title,
                          const QString &body,
                          const QString &color,
                          const QString &iconPath,
                          const QString &tag);
    void dismissNotification(const QString &idOrTag);
    Q_SCRIPTABLE QString GetEntitiesJson() const;
    Q_SCRIPTABLE void Refresh();
    Q_SCRIPTABLE void ToggleLight(const QString &entityId);
    Q_SCRIPTABLE void SetBrightnessPct(const QString &entityId, int pct);
    Q_SCRIPTABLE void SetColorTempKelvin(const QString &entityId, int kelvin);
    Q_SCRIPTABLE void SetRgbColor(const QString &entityId, int r, int g, int b);
    Q_SCRIPTABLE void SetHvacMode(const QString &entityId, const QString &mode);
    Q_SCRIPTABLE void SetFanLevel(const QString &entityId, int level);
    Q_SCRIPTABLE void SetVaneVertical(const QString &entityId, int level);
    Q_SCRIPTABLE void SetVaneHorizontal(const QString &entityId, int level);
    Q_SCRIPTABLE void SetTargetTemp(const QString &entityId, double temp);
    Q_SCRIPTABLE void OpenFavorites();
    Q_SCRIPTABLE void RunScript(const QString &entityId);
    Q_SCRIPTABLE void CancelScript(const QString &entityId);
    Q_SCRIPTABLE void WidgetPresent();
    Q_SCRIPTABLE void WidgetGone();
    Q_SCRIPTABLE void DismissNotification(const QString &idOrTag);
    Q_SCRIPTABLE void OpenApp();
    Q_SCRIPTABLE void ReorderEventsViewEntity(const QString &entityId, int newIndex);
    Q_SCRIPTABLE void RemoveEventsViewEntity(const QString &entityId);

signals:
    void availableEntitiesChanged();
    void widgetEntitiesChanged();
    void eventsViewWidgetEntitiesChanged();
    void selectedEntityIdsChanged();
    void eventsViewSelectedEntityIdsChanged();
    void busyChanged();
    void activeChanged();
    void lastErrorChanged();
    void iconRendererChanged();
    void accessTokenStale();
    void openFavoritesRequested();
    void activateAppRequested();
    void eventsViewWidgetEnabledChanged();
    Q_SCRIPTABLE void EntitiesChanged();

private slots:
    void onReplyFinished();
    void onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors);
    void onPollTimeout();
    void onStartupTimeout();
    void onWidgetFileChanged(const QString &path);
    void onPresenceConfirmTimeout();

private:
    enum RequestKind {
        RequestNone,
        RequestStates,
        RequestOneState,
        RequestService,
        RequestHistory
    };

    void setBusy(bool busy);
    void setActive(bool active);
    void setError(const QString &message);
    void loadSelected();
    void persistSelected();
    void watchSelectedFile();
    bool registerDBus();
    bool accessTokenUsable() const;
    QUrl apiUrl(const QString &path) const;
    void scheduleStates();
    void getStates();
    void getSelectedStates();
    void getAllStates();
    void getEntityState(const QString &entityId);
    void callService(const QString &domain, const QString &service, const QJsonObject &body);
    void applyStates(const QByteArray &data);
    void applyOneState(const QByteArray &data);
    QVariantMap entityFromState(const QJsonObject &state) const;
    QVariantMap overlayExpectation(QVariantMap map);
    void mergeServiceStates(const QByteArray &data);
    void rebuildWidgetEntities();
    QVariantList entitiesForSelection(const QStringList &ids) const;
    QString watermarkIconPath(const QVariantMap &entity) const;
    QVariantMap entityById(const QString &entityId) const;
    void applyOptimistic(const QString &entityId, const QVariantMap &patch);
    void setEventsViewWidgetEnabled(bool enabled);
    void persistWidgetPresence() const;
    void loadWidgetPresence();
    QString notificationEntityId(const QString &tag) const;
    void emitWidgetPayloadChanged();
    void fetchSensorHistory(bool force);
    void applyHistory(const QByteArray &data);
    QStringList historyEntityIds() const;

    QNetworkAccessManager *m_nam;
    QFileSystemWatcher *m_watcher;
    MdiIconRenderer *m_iconRenderer;
    QTimer m_pollTimer;
    QTimer m_startupTimer;
    QTimer m_presenceConfirmTimer;
    QString m_baseUrl;
    QString m_accessToken;
    QDateTime m_accessExpiresAt;
    bool m_ignoreSslErrors;
    bool m_busy;
    bool m_active;
    bool m_dbusRegistered;
    bool m_loadingSelected;
    bool m_tokenRejected;
    int m_selectedOutstanding;
    QNetworkReply *m_allStatesReply;
    QNetworkReply *m_historyReply;
    QString m_lastError;
    QStringList m_selectedEntityIds;
    QStringList m_eventsViewSelectedEntityIds;
    QVariantList m_availableEntities;
    QVariantList m_widgetEntities;
    QVariantList m_eventsViewWidgetEntities;
    QVariantList m_notifications;
    bool m_eventsViewWidgetEnabled;
    QHash<QString, bool> m_expectOn;
    QHash<QString, QVariantList> m_historyPoints;
    QStringList m_historyRequestedIds;
    QDateTime m_historyFetchedAt;
    // Rendering is not cheap and rebuilds happen on every poll.
    mutable QHash<QString, QString> m_iconPathCache;
};

#endif
