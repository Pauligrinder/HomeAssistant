#ifndef LOVELACECOORDINATOR_H
#define LOVELACECOORDINATOR_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <QJsonObject>
#include <QJsonArray>
#include <QSslError>
#include <QList>
#include <QUrl>

class HassWebsocket;
class QNetworkAccessManager;
class QNetworkReply;

class LovelaceCoordinator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantList dashboards READ dashboards NOTIFY dashboardsChanged)
    Q_PROPERTY(QString currentUrlPath READ currentUrlPath WRITE setCurrentUrlPath NOTIFY currentUrlPathChanged)
    Q_PROPERTY(QVariantMap currentConfig READ currentConfig NOTIFY currentConfigChanged)
    Q_PROPERTY(QVariantList views READ views NOTIFY viewsChanged)
    Q_PROPERTY(int currentViewIndex READ currentViewIndex WRITE setCurrentViewIndex NOTIFY currentViewIndexChanged)
    Q_PROPERTY(QVariantMap currentView READ currentView NOTIFY currentViewChanged)
    Q_PROPERTY(int statesRevision READ statesRevision NOTIFY statesRevisionChanged)
    Q_PROPERTY(QString userId READ userId NOTIFY userIdChanged)
    Q_PROPERTY(bool userIsAdmin READ userIsAdmin NOTIFY userIdChanged)
    Q_PROPERTY(QString userName READ userName NOTIFY userIdChanged)
    Q_PROPERTY(QVariantList areas READ areas NOTIFY areasChanged)
    Q_PROPERTY(QVariantMap energyPrefs READ energyPrefs NOTIFY energyPrefsChanged)
    Q_PROPERTY(QString pendingNavigate READ pendingNavigate NOTIFY pendingNavigateChanged)
    Q_PROPERTY(QString pendingUrl READ pendingUrl NOTIFY pendingUrlChanged)
    Q_PROPERTY(QString pendingMoreInfo READ pendingMoreInfo NOTIFY pendingMoreInfoChanged)
    Q_PROPERTY(QString pendingWebPath READ pendingWebPath NOTIFY pendingWebPathChanged)

public:
    explicit LovelaceCoordinator(QObject *parent = nullptr);
    ~LovelaceCoordinator() override;

    void setWebsocket(HassWebsocket *socket);
    void configure(const QString &baseUrl,
                   const QString &accessToken,
                   bool ignoreSslErrors);

    bool ready() const;
    bool busy() const;
    bool connected() const;
    QString lastError() const;
    QVariantList dashboards() const;
    QString currentUrlPath() const;
    QVariantMap currentConfig() const;
    QVariantList views() const;
    int currentViewIndex() const;
    QVariantMap currentView() const;
    int statesRevision() const;
    QString userId() const;
    bool userIsAdmin() const;
    QString userName() const;
    QVariantList areas() const;
    QVariantMap energyPrefs() const;
    QString pendingNavigate() const;
    QString pendingUrl() const;
    QString pendingMoreInfo() const;
    QString pendingWebPath() const;

public slots:
    // Property setters live here so QML can call them directly, not only
    // through the property write.
    void setCurrentUrlPath(const QString &path);
    void setCurrentViewIndex(int index);

    void start();
    void stop();
    void refresh();
    void selectViewByPath(const QString &path);

    QVariantMap entity(const QString &entityId) const;
    QString entityState(const QString &entityId) const;
    QString friendlyName(const QString &entityId, const QString &fallback = QString()) const;
    QString entityIcon(const QString &entityId, const QString &fallback = QString()) const;
    QString domainOf(const QString &entityId) const;
    bool isOn(const QString &entityId) const;
    bool isToggleable(const QString &entityId) const;
    bool isAvailable(const QString &entityId) const;
    QVariant attribute(const QString &entityId, const QString &key) const;
    QString formatState(const QString &entityId) const;
    QString areaName(const QString &areaId) const;
    QVariantList areaEntities(const QString &areaId) const;

    bool isVisible(const QVariant &visibility) const;
    bool cardVisible(const QVariantMap &card) const;
    QVariantList filterEntities(const QVariantMap &card) const;

    void performAction(const QVariantMap &action, const QString &defaultEntityId = QString());
    void toggle(const QString &entityId);
    void callService(const QString &domain,
                     const QString &service,
                     const QVariantMap &data = QVariantMap(),
                     const QString &entityId = QString());
    void handleCardTap(const QVariantMap &card);
    void handleCardHold(const QVariantMap &card);
    void handleCardDoubleTap(const QVariantMap &card);

    void fetchHistory(const QStringList &entityIds, int hours = 24);
    void fetchStatistics(const QStringList &entityIds);
    void prefetchMedia(const QString &path);
    QString cachedMediaUrl(const QString &path) const;
    QString cameraPath(const QString &entityId) const;
    QString resolveMedia(const QString &path) const;
    void renderTemplate(const QString &templateText, const QString &key);
    QString templateValue(const QString &key) const;
    void clearPendingNavigate();
    void clearPendingUrl();
    void clearPendingMoreInfo();
    void clearPendingWebPath();
    void openWebPath(const QString &path);
    void openMoreInfo(const QString &entityId);
    void fetchEnergyPrefs();
    void fetchCalendar(const QString &entityId);
    void fetchTodo(const QString &entityId);
    void setTodoItem(const QString &entityId, const QString &item, bool checked);
    QVariantList calendarEvents(const QString &entityId) const;
    QVariantList todoItems(const QString &entityId) const;

signals:
    void readyChanged();
    void busyChanged();
    void connectedChanged();
    void lastErrorChanged();
    void dashboardsChanged();
    void currentUrlPathChanged();
    void currentConfigChanged();
    void viewsChanged();
    void currentViewIndexChanged();
    void currentViewChanged();
    void statesRevisionChanged();
    void entityChanged(const QString &entityId);
    void userIdChanged();
    void areasChanged();
    void energyPrefsChanged();
    void pendingNavigateChanged();
    void pendingUrlChanged();
    void pendingMoreInfoChanged();
    void pendingWebPathChanged();
    void historyReady(const QString &entityId, const QVariantList &points);
    void statisticsReady(const QString &entityId, const QVariantList &points);
    void mediaCached(const QString &path, const QString &fileUrl);
    void templateReady(const QString &key, const QString &value);
    void calendarReady(const QString &entityId);
    void todoReady(const QString &entityId);

private slots:
    void onConnectionReady();
    void onAuthenticatedChanged();
    void onResultReceived(int id, bool success, const QVariant &result, const QVariantMap &error);
    void onEventReceived(int id, const QVariantMap &event);
    void onReplyFinished();
    void onSslErrors(const QList<QSslError> &errors);

private:
    void setBusy(bool busy);
    void setReady(bool ready);
    void setError(const QString &message);
    void subscribeAll();
    void requestDashboards();
    void requestConfig();
    void requestStates();
    void requestUser();
    void requestAreas();
    void applyStates(const QVariant &result);
    void applyStateObject(const QVariantMap &state);
    void applyStateChanged(const QVariantMap &event);
    void applyDashboards(const QVariant &result);
    void applyConfig(const QVariant &result);
    void commitConfig(const QVariantMap &config);
    void applyGeneratedConfig();
    bool tryFallbackDashboard();
    void handleConfigFailure(const QVariantMap &error);
    void applyUser(const QVariant &result);
    void applyAreas(const QVariant &result);
    QVariantList normalizeViews(const QVariantMap &config) const;
    QVariantMap decorateCard(const QVariantMap &card) const;
    QVariantList decorateCards(const QVariantList &cards) const;
    bool evalConditions(const QVariantList &conditions, bool matchAll) const;
    bool evalCondition(const QVariantMap &condition) const;
    QString defaultActionType(const QString &entityId, bool icon) const;
    QUrl apiUrl(const QString &path) const;
    void getJson(const QString &path, const QString &kind, const QString &tag = QString());
    void getMedia(const QUrl &url, const QString &tag, int redirects = 0);
    void postJson(const QString &path, const QJsonObject &body, const QString &kind, const QString &tag = QString());
    QString mediaCachePath(const QString &path) const;

    HassWebsocket *m_socket;
    QNetworkAccessManager *m_nam;
    QString m_baseUrl;
    QString m_accessToken;
    bool m_ignoreSslErrors;
    bool m_wantRunning;
    bool m_ready;
    bool m_busy;
    bool m_statesLoaded;
    bool m_configLoaded;
    bool m_configFallbackTried;
    bool m_pendingGenerated;
    bool m_userIsAdmin;
    int m_statesRevision;
    int m_currentViewIndex;
    int m_getStatesId;
    int m_subscribeStatesId;
    int m_subscribeLovelaceId;
    int m_dashboardsId;
    int m_configId;
    int m_userIdReq;
    int m_areasId;
    int m_energyId;
    QString m_lastError;
    QString m_currentUrlPath;
    QString m_userId;
    QString m_userName;
    QString m_pendingNavigate;
    QString m_pendingUrl;
    QString m_pendingMoreInfo;
    QString m_pendingWebPath;
    QVariantList m_dashboards;
    QVariantMap m_currentConfig;
    QVariantList m_views;
    QVariantList m_areas;
    QVariantMap m_energyPrefs;
    QHash<QString, QVariantMap> m_entities;
    QHash<QString, QString> m_mediaCache;
    QHash<QString, QString> m_templates;
    QHash<int, QString> m_templateKeys;
    QHash<QString, QVariantList> m_calendarEvents;
    QHash<QString, QVariantList> m_todoItems;
    QHash<int, QString> m_todoById;
    QHash<int, QString> m_calendarById;
};

#endif
