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
#include <QSet>
#include <QSslError>
#include <QList>
#include <QUrl>

#include "hasscamerastream.h"

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
    Q_PROPERTY(QVariantList switcherItems READ switcherItems NOTIFY switcherItemsChanged)
    Q_PROPERTY(QString currentUrlPath READ currentUrlPath WRITE setCurrentUrlPath NOTIFY currentUrlPathChanged)
    Q_PROPERTY(QString defaultUrlPath READ defaultUrlPath NOTIFY defaultUrlPathChanged)
    Q_PROPERTY(QVariantMap currentConfig READ currentConfig NOTIFY currentConfigChanged)
    Q_PROPERTY(QVariantList views READ views NOTIFY viewsChanged)
    Q_PROPERTY(int currentViewIndex READ currentViewIndex WRITE setCurrentViewIndex NOTIFY currentViewIndexChanged)
    Q_PROPERTY(QVariantMap currentView READ currentView NOTIFY currentViewChanged)
    Q_PROPERTY(int configsRevision READ configsRevision NOTIFY configsRevisionChanged)
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
    Q_PROPERTY(bool pendingWebChromeless READ pendingWebChromeless NOTIFY pendingWebPathChanged)
    Q_PROPERTY(QString ingressSession READ ingressSession NOTIFY ingressSessionChanged)
    Q_PROPERTY(QVariantMap pendingConfirmation READ pendingConfirmation NOTIFY pendingConfirmationChanged)
    Q_PROPERTY(HassCameraStream *cameraStream READ cameraStream CONSTANT)

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
    QVariantList switcherItems() const;
    QString currentUrlPath() const;
    QString defaultUrlPath() const;
    Q_INVOKABLE bool isDefaultDashboardPath(const QString &path) const;
    Q_INVOKABLE QString normalizedUrlPath(const QString &path) const;
    Q_INVOKABLE QVariantList viewsForPath(const QString &path) const;
    Q_INVOKABLE bool pathConfigReady(const QString &path) const;
    QVariantMap currentConfig() const;
    QVariantList views() const;
    int currentViewIndex() const;
    QVariantMap currentView() const;
    int configsRevision() const;
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
    bool pendingWebChromeless() const;
    QString ingressSession() const;
    QVariantMap pendingConfirmation() const;
    HassCameraStream *cameraStream() const;

public slots:
    // Property setters live here so QML can call them directly, not only
    // through the property write.
    void setCurrentUrlPath(const QString &path);
    void setCurrentViewIndex(int index);
    void selectSwitcherPath(const QString &path);

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
    QVariantList relatedEntities(const QString &entityId) const;
    QVariantList zones() const;

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
    void confirmPendingAction();
    void cancelPendingAction();

    void fetchHistory(const QStringList &entityIds, int hours = 24);
    void fetchStatistics(const QStringList &entityIds);
    void prefetchMedia(const QString &path);
    QString cachedMediaUrl(const QString &path) const;
    QString cameraPath(const QString &entityId) const;
    QString mediaPathOf(const QVariant &value) const;
    QString resolveMedia(const QString &path) const;
    void renderTemplate(const QString &templateText, const QString &key);
    QString templateValue(const QString &key) const;
    void clearPendingNavigate();
    void clearPendingUrl();
    void clearPendingMoreInfo();
    void clearPendingWebPath();
    void openWebPath(const QString &path, bool chromeless = false);
    void keepIngressSessionAlive();
    void openMoreInfo(const QString &entityId);
    void fetchEnergyPrefs();
    void fetchCalendar(const QString &entityId);
    void fetchCalendarRange(const QString &entityId,
                            const QString &start,
                            const QString &end);
    void fetchTodo(const QString &entityId);
    void setTodoItem(const QString &entityId, const QString &item, bool checked);
    void addTodoItem(const QString &entityId, const QString &summary);
    void removeTodoItem(const QString &entityId, const QString &item);
    void moveTodoItem(const QString &entityId,
                      const QString &uid,
                      const QString &previousUid = QString());
    QVariantList calendarEvents(const QString &entityId) const;
    QVariantList todoItems(const QString &entityId) const;

signals:
    void readyChanged();
    void busyChanged();
    void connectedChanged();
    void lastErrorChanged();
    void dashboardsChanged();
    void switcherItemsChanged();
    void currentUrlPathChanged();
    void defaultUrlPathChanged();
    void currentConfigChanged();
    void viewsChanged();
    void currentViewIndexChanged();
    void currentViewChanged();
    void configsRevisionChanged();
    void statesRevisionChanged();
    void entityChanged(const QString &entityId);
    void userIdChanged();
    void areasChanged();
    void energyPrefsChanged();
    void pendingNavigateChanged();
    void pendingUrlChanged();
    void pendingMoreInfoChanged();
    void pendingWebPathChanged();
    void ingressSessionChanged();
    void pendingConfirmationChanged();
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
    void requestPanels();
    void requestConfig();
    void requestPanelConfig(const QString &path);
    void applyProbedPanelConfig(const QString &path, bool success, const QVariant &result);
    bool isKnownDashboardPath(const QString &path) const;
    void openPanelInWebView(const QString &path, const QString &component);
    void requestIngressOpen(const QString &slug, const QString &fallbackPath);
    void finishIngressOpenIfReady();
    void requestIngressSession();
    void setIngressSession(const QString &session);
    void requestStates();
    void requestUser();
    void requestFrontendDefaults();
    void requestAreas();
    void requestEntityRegistry();
    void requestEntityIcons();
    void maybeRequestInitialConfig();
    void applyStates(const QVariant &result);
    void applyStateObject(const QVariantMap &state);
    void applyStateChanged(const QVariantMap &event);
    void applyDashboards(const QVariant &result);
    void applyPanels(const QVariant &result);
    void rebuildSwitcherItems();
    void applyConfig(const QVariant &result);
    void commitConfig(const QVariantMap &config);
    void applyGeneratedConfig();
    bool tryFallbackDashboard();
    void handleConfigFailure(const QVariantMap &error);
    void applyUser(const QVariant &result);
    void applyAreas(const QVariant &result);
    void applyEntityRegistry(const QVariant &result);
    void applyIconResources(const QString &category, const QVariant &result);
    void bumpStatesRevision();
    QString resolvedEntityIcon(const QString &entityId) const;
    QString iconFromComponentResources(const QString &domain,
                                       const QString &deviceClass,
                                       const QString &state) const;
    QString iconFromEntityResources(const QString &platform,
                                    const QString &translationKey,
                                    const QString &state) const;
    QVariantList normalizeViews(const QVariantMap &config) const;
    QVariantMap decorateCard(const QVariantMap &card) const;
    QVariantList decorateCards(const QVariantList &cards) const;
    bool evalConditions(const QVariantList &conditions, bool matchAll) const;
    bool evalCondition(const QVariantMap &condition) const;
    QString defaultActionType(const QString &entityId, bool icon) const;
    void attachCardConfirmation(QVariantMap *action, const QVariantMap &card) const;
    bool confirmationRequired(const QVariant &confirmation) const;
    QVariantMap buildConfirmationPrompt(const QVariant &confirmation,
                                        const QString &entityId) const;
    bool requestConfirmationIfNeeded(const QVariantMap &action, const QString &entityId);
    void clearPendingConfirmation();
    QUrl apiUrl(const QString &path) const;
    void getJson(const QString &path, const QString &kind, const QString &tag = QString());
    void getMedia(const QUrl &url, const QString &tag, int redirects = 0);
    void resolveMediaSource(const QString &path);
    void postJson(const QString &path, const QJsonObject &body, const QString &kind, const QString &tag = QString());
    QString mediaCachePath(const QString &path) const;

    HassWebsocket *m_socket;
    QNetworkAccessManager *m_nam;
    HassCameraStream *m_cameraStream;
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
    int m_configsRevision;
    int m_getStatesId;
    int m_subscribeStatesId;
    int m_subscribeLovelaceId;
    int m_subscribePanelsId;
    int m_dashboardsId;
    int m_panelsId;
    int m_panelConfigId;
    int m_configId;
    int m_userIdReq;
    int m_frontendUserDataId;
    int m_frontendSystemDataId;
    int m_areasId;
    int m_entityRegistryId;
    int m_entityComponentIconsId;
    int m_entityIconsId;
    int m_subscribeRegistryId;
    int m_energyId;
    int m_ingressAddonInfoId;
    int m_ingressSessionId;
    int m_ingressValidateId;
    QString m_lastError;
    QString m_currentUrlPath;
    QHash<QString, QVariantMap> m_configByPath;
    QHash<QString, QVariantList> m_viewsByPath;
    QString m_userId;
    QString m_userName;
    QString m_userDefaultPanel;
    QString m_systemDefaultPanel;
    bool m_initialDashboardSelected;
    QString m_pendingNavigate;
    QString m_pendingUrl;
    QString m_pendingMoreInfo;
    QString m_pendingWebPath;
    bool m_pendingWebChromeless;
    QString m_ingressSession;
    QString m_pendingIngressSlug;
    QString m_pendingIngressFallback;
    QString m_pendingIngressUrl;
    QVariantMap m_pendingConfirmation;
    QVariantMap m_pendingConfirmedAction;
    QString m_pendingActionEntityId;
    QVariantList m_dashboards;
    QVariantMap m_panels;
    QVariantList m_switcherItems;
    QString m_pendingPanelPath;
    QSet<QString> m_nativePanelPaths;
    QVariantMap m_currentConfig;
    QVariantList m_views;
    QVariantList m_areas;
    QVariantMap m_energyPrefs;
    QHash<QString, QVariantMap> m_entities;
    QHash<QString, QVariantMap> m_entityRegistry;
    QVariantMap m_entityComponentIcons;
    QVariantMap m_entityIcons;
    QHash<QString, QString> m_mediaCache;
    QSet<QString> m_mediaPending;
    QHash<int, QString> m_mediaSourceById;
    QHash<QString, QString> m_templates;
    QHash<int, QString> m_templateKeys;
    QHash<QString, QVariantList> m_calendarEvents;
    QHash<QString, QVariantList> m_todoItems;
    QHash<int, QString> m_todoById;
    QHash<int, QString> m_todoRefreshById;
};

#endif
