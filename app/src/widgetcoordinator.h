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

// Lights (and later other entities) for the Events View widget. Uses the
// Home Assistant REST API with the same session Helmsman already stores.
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
"    <signal name=\"EntitiesChanged\"/>\n"
"  </interface>\n"
"")
    Q_PROPERTY(QVariantList availableEntities READ availableEntities NOTIFY availableEntitiesChanged)
    Q_PROPERTY(QVariantList widgetEntities READ widgetEntities NOTIFY widgetEntitiesChanged)
    Q_PROPERTY(QStringList selectedEntityIds READ selectedEntityIds WRITE setSelectedEntityIds NOTIFY selectedEntityIdsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit WidgetCoordinator(QObject *parent = nullptr);
    ~WidgetCoordinator() override;

    QVariantList availableEntities() const;
    QVariantList widgetEntities() const;
    QStringList selectedEntityIds() const;
    bool busy() const;
    bool active() const;
    QString lastError() const;
    bool dbusRegistered() const;

    void configure(const QString &baseUrl,
                   const QString &accessToken,
                   const QDateTime &accessExpiresAt,
                   bool ignoreSslErrors);
    void start();
    void stop();

public slots:
    void setSelectedEntityIds(const QStringList &ids);
    void setEntitySelected(const QString &entityId, bool selected);
    void refresh();
    void refreshAvailable();
    void toggleLight(const QString &entityId);
    void setBrightnessPct(const QString &entityId, int pct);
    Q_SCRIPTABLE QString GetEntitiesJson() const;
    Q_SCRIPTABLE void Refresh();
    Q_SCRIPTABLE void ToggleLight(const QString &entityId);
    Q_SCRIPTABLE void SetBrightnessPct(const QString &entityId, int pct);

signals:
    void availableEntitiesChanged();
    void widgetEntitiesChanged();
    void selectedEntityIdsChanged();
    void busyChanged();
    void activeChanged();
    void lastErrorChanged();
    void accessTokenStale();
    Q_SCRIPTABLE void EntitiesChanged();

private slots:
    void onReplyFinished();
    void onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors);
    void onPollTimeout();
    void onStartupTimeout();
    void onWidgetFileChanged(const QString &path);

private:
    enum RequestKind {
        RequestNone,
        RequestStates,
        RequestOneState,
        RequestService
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
    QVariantMap entityById(const QString &entityId) const;
    void applyOptimistic(const QString &entityId, const QVariantMap &patch);

    QNetworkAccessManager *m_nam;
    QFileSystemWatcher *m_watcher;
    QTimer m_pollTimer;
    QTimer m_startupTimer;
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
    QString m_lastError;
    QStringList m_selectedEntityIds;
    QVariantList m_availableEntities;
    QVariantList m_widgetEntities;
    QHash<QString, bool> m_expectOn;
};

#endif
