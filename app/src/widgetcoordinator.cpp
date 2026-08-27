#include "widgetcoordinator.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonValue>
#include <QFile>
#include <QSaveFile>
#include <QFileSystemWatcher>
#include <QStandardPaths>
#include <QDir>
#include <QUrl>
#include <QHash>
#include <QDateTime>
#include <QDebug>
#include <QDBusConnection>
#include <algorithm>

namespace {

const char *kClientName = "Helmsman";
const char *kDbusService = "org.helmsman.harbour-helmsman";
const char *kDbusPath = "/widget";
const int kPollIntervalMs = 8000;

QString widgetFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/widget.json");
}

bool isLightDimmable(const QJsonObject &attrs)
{
    const QJsonArray modes = attrs.value(QStringLiteral("supported_color_modes")).toArray();
    for (const QJsonValue &value : modes) {
        const QString mode = value.toString();
        if (!mode.isEmpty() && mode != QLatin1String("onoff"))
            return true;
    }
    if (attrs.contains(QStringLiteral("brightness")) && attrs.value(QStringLiteral("brightness")).isDouble())
        return true;
    const int features = attrs.value(QStringLiteral("supported_features")).toInt();
    return (features & 1) != 0;
}

int brightnessToPct(const QJsonValue &brightness)
{
    if (!brightness.isDouble())
        return 0;
    const int raw = qBound(0, brightness.toInt(), 255);
    return qBound(0, int(qRound(raw * 100.0 / 255.0)), 100);
}

} // namespace

WidgetCoordinator::WidgetCoordinator(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_watcher(new QFileSystemWatcher(this))
    , m_ignoreSslErrors(false)
    , m_busy(false)
    , m_active(false)
    , m_dbusRegistered(false)
    , m_loadingSelected(false)
    , m_tokenRejected(false)
{
    m_pollTimer.setInterval(kPollIntervalMs);
    connect(&m_pollTimer, SIGNAL(timeout()), this, SLOT(onPollTimeout()));
    connect(m_nam, SIGNAL(sslErrors(QNetworkReply*,QList<QSslError>)),
            this, SLOT(onSslErrors(QNetworkReply*,QList<QSslError>)));
    connect(m_watcher, SIGNAL(fileChanged(QString)),
            this, SLOT(onWidgetFileChanged(QString)));

    loadSelected();
    watchSelectedFile();
    registerDBus();
}

WidgetCoordinator::~WidgetCoordinator()
{
    if (m_dbusRegistered) {
        QDBusConnection bus = QDBusConnection::sessionBus();
        bus.unregisterObject(QString::fromLatin1(kDbusPath));
        bus.unregisterService(QString::fromLatin1(kDbusService));
    }
}

QVariantList WidgetCoordinator::availableEntities() const
{
    return m_availableEntities;
}

QVariantList WidgetCoordinator::widgetEntities() const
{
    return m_widgetEntities;
}

QStringList WidgetCoordinator::selectedEntityIds() const
{
    return m_selectedEntityIds;
}

bool WidgetCoordinator::busy() const
{
    return m_busy;
}

bool WidgetCoordinator::active() const
{
    return m_active;
}

QString WidgetCoordinator::lastError() const
{
    return m_lastError;
}

bool WidgetCoordinator::dbusRegistered() const
{
    return m_dbusRegistered;
}

void WidgetCoordinator::configure(const QString &baseUrl,
                                  const QString &accessToken,
                                  const QDateTime &accessExpiresAt,
                                  bool ignoreSslErrors)
{
    const bool tokenChanged = m_accessToken != accessToken;
    const bool changed = m_baseUrl != baseUrl
            || tokenChanged
            || m_accessExpiresAt != accessExpiresAt
            || m_ignoreSslErrors != ignoreSslErrors;
    m_baseUrl = baseUrl;
    m_accessToken = accessToken;
    m_accessExpiresAt = accessExpiresAt;
    m_ignoreSslErrors = ignoreSslErrors;
    if (tokenChanged)
        m_tokenRejected = false;
    if (changed && m_active)
        getStates();
}

void WidgetCoordinator::start()
{
    setActive(true);
    if (!m_pollTimer.isActive())
        m_pollTimer.start();
    getStates();
}

void WidgetCoordinator::stop()
{
    m_pollTimer.stop();
    setActive(false);
}

void WidgetCoordinator::setSelectedEntityIds(const QStringList &ids)
{
    QStringList clean;
    clean.reserve(ids.size());
    for (const QString &id : ids) {
        const QString trimmed = id.trimmed();
        if (trimmed.isEmpty() || clean.contains(trimmed))
            continue;
        clean.append(trimmed);
    }
    if (clean == m_selectedEntityIds)
        return;
    m_selectedEntityIds = clean;
    persistSelected();
    emit selectedEntityIdsChanged();
    rebuildWidgetEntities();
    if (m_active)
        getStates();
}

void WidgetCoordinator::setEntitySelected(const QString &entityId, bool selected)
{
    const QString id = entityId.trimmed();
    if (id.isEmpty())
        return;
    QStringList next = m_selectedEntityIds;
    const int index = next.indexOf(id);
    if (selected && index < 0)
        next.append(id);
    else if (!selected && index >= 0)
        next.removeAt(index);
    else
        return;
    setSelectedEntityIds(next);
}

void WidgetCoordinator::refresh()
{
    getStates();
}

void WidgetCoordinator::toggleLight(const QString &entityId)
{
    const QVariantMap current = entityById(entityId);
    const bool wasOn = current.value(QStringLiteral("on")).toBool();
    QVariantMap patch;
    patch.insert(QStringLiteral("on"), !wasOn);
    patch.insert(QStringLiteral("state"), wasOn ? QStringLiteral("off") : QStringLiteral("on"));
    if (wasOn) {
        patch.insert(QStringLiteral("brightnessPct"), 0);
    } else {
        int pct = current.value(QStringLiteral("brightnessPct")).toInt();
        if (pct <= 0)
            pct = 100;
        patch.insert(QStringLiteral("brightnessPct"), pct);
    }
    m_expectOn.insert(entityId, !wasOn);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    callService(QStringLiteral("light"), QStringLiteral("toggle"), body);
}

void WidgetCoordinator::setBrightnessPct(const QString &entityId, int pct)
{
    pct = qBound(0, pct, 100);
    QVariantMap patch;
    patch.insert(QStringLiteral("brightnessPct"), pct);
    patch.insert(QStringLiteral("on"), pct > 0);
    patch.insert(QStringLiteral("state"), pct > 0 ? QStringLiteral("on") : QStringLiteral("off"));
    m_expectOn.insert(entityId, pct > 0);
    applyOptimistic(entityId, patch);

    QJsonObject body;
    body.insert(QStringLiteral("entity_id"), entityId);
    if (pct <= 0) {
        callService(QStringLiteral("light"), QStringLiteral("turn_off"), body);
        return;
    }
    body.insert(QStringLiteral("brightness_pct"), pct);
    callService(QStringLiteral("light"), QStringLiteral("turn_on"), body);
}

QString WidgetCoordinator::GetEntitiesJson() const
{
    return QString::fromUtf8(QJsonDocument::fromVariant(m_widgetEntities).toJson(QJsonDocument::Compact));
}

void WidgetCoordinator::Refresh()
{
    refresh();
}

void WidgetCoordinator::ToggleLight(const QString &entityId)
{
    toggleLight(entityId);
}

void WidgetCoordinator::SetBrightnessPct(const QString &entityId, int pct)
{
    setBrightnessPct(entityId, pct);
}

void WidgetCoordinator::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void WidgetCoordinator::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    emit activeChanged();
}

void WidgetCoordinator::setError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

void WidgetCoordinator::loadSelected()
{
    m_loadingSelected = true;
    QFile file(widgetFilePath());
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (doc.isObject()) {
            const QJsonArray array = doc.object().value(QStringLiteral("selectedEntityIds")).toArray();
            QStringList ids;
            for (const QJsonValue &value : array) {
                const QString id = value.toString().trimmed();
                if (!id.isEmpty() && !ids.contains(id))
                    ids.append(id);
            }
            if (ids != m_selectedEntityIds) {
                m_selectedEntityIds = ids;
                emit selectedEntityIdsChanged();
                rebuildWidgetEntities();
            }
        }
    }
    m_loadingSelected = false;
}

void WidgetCoordinator::persistSelected()
{
    if (m_loadingSelected)
        return;
    QJsonArray array;
    for (const QString &id : m_selectedEntityIds)
        array.append(id);
    QJsonObject obj;
    obj.insert(QStringLiteral("selectedEntityIds"), array);

    const QString path = widgetFilePath();
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "Helmsman widget: could not write" << path << file.errorString();
        return;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    if (!file.commit())
        qWarning() << "Helmsman widget: could not commit" << path << file.errorString();
    watchSelectedFile();
}

void WidgetCoordinator::watchSelectedFile()
{
    const QString path = widgetFilePath();
    if (!QFile::exists(path))
        return;
    const QStringList files = m_watcher->files();
    if (!files.contains(path))
        m_watcher->addPath(path);
}

bool WidgetCoordinator::registerDBus()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QString::fromLatin1(kDbusService))) {
        qWarning() << "Helmsman widget: DBus name already taken";
        return false;
    }
    if (!bus.registerObject(QString::fromLatin1(kDbusPath), this,
                            QDBusConnection::ExportScriptableSlots
                            | QDBusConnection::ExportScriptableSignals)) {
        qWarning() << "Helmsman widget: could not export DBus object";
        bus.unregisterService(QString::fromLatin1(kDbusService));
        return false;
    }
    m_dbusRegistered = true;
    qWarning() << "Helmsman widget: DBus registered as" << kDbusService;
    return true;
}

QUrl WidgetCoordinator::apiUrl(const QString &path) const
{
    QUrl url(m_baseUrl);
    url.setPath(path);
    return url;
}

bool WidgetCoordinator::accessTokenUsable() const
{
    if (m_tokenRejected || m_accessToken.isEmpty())
        return false;
    if (!m_accessExpiresAt.isValid())
        return false;
    return QDateTime::currentDateTimeUtc().msecsTo(m_accessExpiresAt.toUTC()) > 60 * 1000;
}

void WidgetCoordinator::getStates()
{
    if (!m_active || m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    if (!accessTokenUsable()) {
        emit accessTokenStale();
        return;
    }

    QNetworkRequest request(apiUrl(QStringLiteral("/api/states")));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    QNetworkReply *reply = m_nam->get(request);
    reply->setProperty("kind", int(RequestStates));
    reply->setProperty("token", m_accessToken);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
    setBusy(true);
}

void WidgetCoordinator::callService(const QString &domain, const QString &service, const QJsonObject &body)
{
    if (m_baseUrl.isEmpty() || m_accessToken.isEmpty())
        return;
    if (!accessTokenUsable()) {
        emit accessTokenStale();
        return;
    }

    const QString path = QStringLiteral("/api/services/%1/%2").arg(domain, service);
    QNetworkRequest request(apiUrl(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", kClientName);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    const QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = m_nam->post(request, payload);
    reply->setProperty("kind", int(RequestService));
    reply->setProperty("token", m_accessToken);
    connect(reply, SIGNAL(finished()), this, SLOT(onReplyFinished()));
}

void WidgetCoordinator::applyStates(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray()) {
        setError(QStringLiteral("Unexpected states response"));
        return;
    }

    QVariantList lights;
    const QJsonArray array = doc.array();
    for (const QJsonValue &value : array) {
        if (!value.isObject())
            continue;
        const QJsonObject state = value.toObject();
        const QString entityId = state.value(QStringLiteral("entity_id")).toString();
        if (!entityId.startsWith(QLatin1String("light.")))
            continue;
        lights.append(overlayExpectation(entityFromState(state)));
    }

    std::sort(lights.begin(), lights.end(), [](const QVariant &a, const QVariant &b) {
        const QString left = a.toMap().value(QStringLiteral("name")).toString();
        const QString right = b.toMap().value(QStringLiteral("name")).toString();
        return QString::localeAwareCompare(left, right) < 0;
    });

    if (lights != m_availableEntities) {
        m_availableEntities = lights;
        emit availableEntitiesChanged();
    }
    rebuildWidgetEntities();
    setError(QString());
}

QVariantMap WidgetCoordinator::entityFromState(const QJsonObject &state) const
{
    const QString entityId = state.value(QStringLiteral("entity_id")).toString();
    const QJsonObject attrs = state.value(QStringLiteral("attributes")).toObject();
    const QString status = state.value(QStringLiteral("state")).toString();
    const bool available = status != QLatin1String("unavailable")
            && status != QLatin1String("unknown");
    const bool on = status == QLatin1String("on");
    const bool dimmable = isLightDimmable(attrs);
    QString name = attrs.value(QStringLiteral("friendly_name")).toString();
    if (name.isEmpty())
        name = entityId;

    QVariantMap map;
    map.insert(QStringLiteral("entityId"), entityId);
    map.insert(QStringLiteral("name"), name);
    map.insert(QStringLiteral("kind"), QStringLiteral("light"));
    map.insert(QStringLiteral("state"), status);
    map.insert(QStringLiteral("on"), on);
    map.insert(QStringLiteral("available"), available);
    map.insert(QStringLiteral("dimmable"), dimmable);
    map.insert(QStringLiteral("brightnessPct"), on ? brightnessToPct(attrs.value(QStringLiteral("brightness"))) : 0);
    QString icon = attrs.value(QStringLiteral("icon")).toString();
    if (icon.isEmpty())
        icon = on ? QStringLiteral("mdi:lightbulb") : QStringLiteral("mdi:lightbulb-outline");
    map.insert(QStringLiteral("icon"), icon);
    map.insert(QStringLiteral("selected"), m_selectedEntityIds.contains(entityId));
    return map;
}

QVariantMap WidgetCoordinator::overlayExpectation(QVariantMap map)
{
    const QString entityId = map.value(QStringLiteral("entityId")).toString();
    if (entityId.isEmpty() || !m_expectOn.contains(entityId))
        return map;

    const bool expected = m_expectOn.value(entityId);
    const bool actual = map.value(QStringLiteral("on")).toBool();
    if (actual == expected) {
        m_expectOn.remove(entityId);
        return map;
    }

    map.insert(QStringLiteral("on"), expected);
    map.insert(QStringLiteral("state"), expected ? QStringLiteral("on") : QStringLiteral("off"));
    if (!expected)
        map.insert(QStringLiteral("brightnessPct"), 0);
    else if (map.value(QStringLiteral("brightnessPct")).toInt() <= 0)
        map.insert(QStringLiteral("brightnessPct"), 100);
    return map;
}

void WidgetCoordinator::mergeServiceStates(const QByteArray &data)
{
    const QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray() || doc.array().isEmpty())
        return;

    QHash<QString, int> indexById;
    for (int i = 0; i < m_availableEntities.size(); ++i) {
        const QString id = m_availableEntities.at(i).toMap().value(QStringLiteral("entityId")).toString();
        if (!id.isEmpty())
            indexById.insert(id, i);
    }

    bool changed = false;
    const QJsonArray array = doc.array();
    for (const QJsonValue &value : array) {
        if (!value.isObject())
            continue;
        const QJsonObject state = value.toObject();
        const QString entityId = state.value(QStringLiteral("entity_id")).toString();
        if (!entityId.startsWith(QLatin1String("light.")))
            continue;
        const QVariantMap map = overlayExpectation(entityFromState(state));
        if (indexById.contains(entityId)) {
            m_availableEntities[indexById.value(entityId)] = map;
        } else {
            m_availableEntities.append(map);
        }
        changed = true;
    }
    if (!changed)
        return;
    emit availableEntitiesChanged();
    rebuildWidgetEntities();
}

void WidgetCoordinator::rebuildWidgetEntities()
{
    QHash<QString, QVariantMap> byId;
    for (const QVariant &value : m_availableEntities) {
        const QVariantMap map = value.toMap();
        byId.insert(map.value(QStringLiteral("entityId")).toString(), map);
    }

    QVariantList next;
    for (const QString &id : m_selectedEntityIds) {
        if (byId.contains(id)) {
            QVariantMap map = overlayExpectation(byId.value(id));
            map.insert(QStringLiteral("selected"), true);
            next.append(map);
        } else {
            QVariantMap map;
            map.insert(QStringLiteral("entityId"), id);
            map.insert(QStringLiteral("name"), id);
            map.insert(QStringLiteral("kind"), QStringLiteral("light"));
            map.insert(QStringLiteral("state"), QStringLiteral("unknown"));
            map.insert(QStringLiteral("on"), false);
            map.insert(QStringLiteral("available"), false);
            map.insert(QStringLiteral("dimmable"), false);
            map.insert(QStringLiteral("brightnessPct"), 0);
            map.insert(QStringLiteral("icon"), QStringLiteral("mdi:lightbulb-outline"));
            map.insert(QStringLiteral("selected"), true);
            next.append(map);
        }
    }

    if (next == m_widgetEntities)
        return;
    m_widgetEntities = next;
    emit widgetEntitiesChanged();
    emit EntitiesChanged();
}

QVariantMap WidgetCoordinator::entityById(const QString &entityId) const
{
    for (const QVariant &value : m_widgetEntities) {
        const QVariantMap map = value.toMap();
        if (map.value(QStringLiteral("entityId")).toString() == entityId)
            return map;
    }
    for (const QVariant &value : m_availableEntities) {
        const QVariantMap map = value.toMap();
        if (map.value(QStringLiteral("entityId")).toString() == entityId)
            return map;
    }
    return QVariantMap();
}

void WidgetCoordinator::applyOptimistic(const QString &entityId, const QVariantMap &patch)
{
    auto patchList = [entityId, patch](QVariantList list) {
        for (int i = 0; i < list.size(); ++i) {
            QVariantMap map = list.at(i).toMap();
            if (map.value(QStringLiteral("entityId")).toString() != entityId)
                continue;
            for (auto it = patch.begin(); it != patch.end(); ++it)
                map.insert(it.key(), it.value());
            list[i] = map;
            break;
        }
        return list;
    };

    m_availableEntities = patchList(m_availableEntities);
    emit availableEntitiesChanged();
    m_widgetEntities = patchList(m_widgetEntities);
    emit widgetEntitiesChanged();
    emit EntitiesChanged();
}

void WidgetCoordinator::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply *>(sender());
    if (!reply)
        return;

    const RequestKind kind = static_cast<RequestKind>(reply->property("kind").toInt());
    const QByteArray data = reply->readAll();
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QNetworkReply::NetworkError netError = reply->error();
    const QString netErrorString = reply->errorString();
    reply->deleteLater();

    if (kind == RequestStates)
        setBusy(false);

    if (netError != QNetworkReply::NoError && status == 0) {
        setError(QStringLiteral("Could not reach Home Assistant (%1)").arg(netErrorString));
        return;
    }
    if (status == 401) {
        if (reply->property("token").toString() == m_accessToken) {
            m_tokenRejected = true;
            setError(QStringLiteral("Home Assistant session expired"));
            emit accessTokenStale();
        }
        return;
    }
    if (status < 200 || status >= 300) {
        setError(QStringLiteral("Home Assistant HTTP %1").arg(status));
        return;
    }

    if (kind == RequestStates)
        applyStates(data);
    else if (kind == RequestService)
        mergeServiceStates(data);
}

void WidgetCoordinator::onSslErrors(QNetworkReply *reply, const QList<QSslError> &errors)
{
    Q_UNUSED(errors);
    if (m_ignoreSslErrors && reply)
        reply->ignoreSslErrors();
}

void WidgetCoordinator::onPollTimeout()
{
    if (m_active)
        getStates();
}

void WidgetCoordinator::onWidgetFileChanged(const QString &path)
{
    Q_UNUSED(path);
    watchSelectedFile();
    const QStringList previous = m_selectedEntityIds;
    loadSelected();
    if (previous != m_selectedEntityIds && m_active)
        getStates();
}
