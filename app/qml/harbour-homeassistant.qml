import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.Notifications 1.0
import harbour.helmsman 1.0
import "cover" as CoverDir
import "pages"
import "components"

ApplicationWindow
{
    id: appWindow
    property int notificationCount: 0
    // HA data.tag -> Sailfish replacesId, for replace/clear support.
    property var notificationTags: ({})
    property string coverNotificationTitle: ""
    property string coverNotificationBody: ""
    property string coverNotificationColor: "#03A9F4"
    property string coverNotificationIcon: ""

    readonly property string defaultCoverColor: "#03A9F4"

    function homePageUrl() {
        return hassClientInstance.nativeDashboardEnabled
                ? Qt.resolvedUrl("pages/NativeHomePage.qml")
                : Qt.resolvedUrl("pages/HassWebViewPage.qml")
    }

    function homePageProperties() {
        var props = { hassClient: hassClientInstance, mdiIcons: mdiIcons }
        if (!hassClientInstance.nativeDashboardEnabled)
            props.isHome = true
        return props
    }

    function replaceHomePage() {
        if (!hassClientInstance.loggedIn)
            return
        pageStack.replaceAbove(null, appWindow.homePageUrl(), appWindow.homePageProperties())
    }

    function goHomeIfLoggedIn() {
        if (!hassClientInstance.loggedIn)
            return
        if (pageStack.currentPage
                && (pageStack.currentPage.objectName === "HomePage"
                    || pageStack.currentPage.objectName === "SplashPage"))
            return
        appWindow.replaceHomePage()
    }

    property bool pendingEventsFavorites: false

    function openEventsViewFavorites() {
        appWindow.activate()
        if (pageStack.currentPage
                && pageStack.currentPage.objectName === "SplashPage") {
            appWindow.pendingEventsFavorites = true
            return
        }
        appWindow.showEventsViewFavorites()
    }

    function showEventsViewFavorites() {
        var existing = appWindow.findEventsViewFavoritesPage()
        if (existing) {
            if (pageStack.currentPage !== existing)
                pageStack.pop(existing)
            return
        }
        pageStack.push(Qt.resolvedUrl("pages/EventsViewSettingsPage.qml"),
                       { hassClient: hassClientInstance,
                         eventsViewMode: true })
    }

    function findEventsViewFavoritesPage() {
        if (!pageStack || typeof pageStack.find !== "function")
            return null
        return pageStack.find(function(page) {
            return page && page.objectName === "EventsViewFavoritesPage"
        })
    }

    function flushPendingEventsFavorites() {
        if (!appWindow.pendingEventsFavorites)
            return
        if (pageStack.currentPage
                && pageStack.currentPage.objectName === "SplashPage")
            return
        appWindow.pendingEventsFavorites = false
        appWindow.showEventsViewFavorites()
    }

    function dataString(data, key) {
        if (!data || data[key] === undefined || data[key] === null)
            return ""
        return String(data[key])
    }

    function dataBool(data, key) {
        if (!data || data[key] === undefined || data[key] === null)
            return false
        var value = data[key]
        if (typeof value === "boolean")
            return value
        var text = String(value).toLowerCase()
        return text === "true" || text === "1" || text === "yes"
    }

    function resolveMediaUrl(path) {
        if (!path || path.length === 0)
            return ""
        if (path.indexOf("http://") === 0 || path.indexOf("https://") === 0
                || path.indexOf("file://") === 0 || path.indexOf("/") === 0)
            return path
        var base = hassClientInstance.baseUrl || ""
        if (!base.length)
            return path
        if (path.charAt(0) === "/")
            return base.replace(/\/$/, "") + path
        return base.replace(/\/$/, "") + "/" + path
    }

    function normalizeCoverColor(colorSpec) {
        if (!colorSpec || colorSpec.length === 0)
            return appWindow.defaultCoverColor
        var s = String(colorSpec).trim()
        if ((s.charAt(0) === '"' && s.charAt(s.length - 1) === '"')
                || (s.charAt(0) === "'" && s.charAt(s.length - 1) === "'"))
            s = s.substring(1, s.length - 1).trim()
        if (s.indexOf("0x") === 0 || s.indexOf("0X") === 0)
            s = "#" + s.substring(2)
        if (s.charAt(0) !== "#" && /^[0-9A-Fa-f]{3,8}$/.test(s))
            s = "#" + s
        // Qt/QML named colors and #hex both work as Rectangle.color values.
        return s.length > 0 ? s : appWindow.defaultCoverColor
    }

    function urgencyFromData(data) {
        var importance = dataString(data, "importance").toLowerCase()
        if (!importance.length)
            importance = dataString(data, "priority").toLowerCase()
        if (importance === "high" || importance === "max" || importance === "critical")
            return Notification.Critical
        if (importance === "low" || importance === "min")
            return Notification.Low
        return Notification.Normal
    }

    function cloneTagMap() {
        var next = ({})
        var src = appWindow.notificationTags || ({})
        for (var key in src) {
            if (src.hasOwnProperty(key))
                next[key] = src[key]
        }
        return next
    }

    function clearCoverNotification() {
        appWindow.notificationCount = 0
        appWindow.coverNotificationTitle = ""
        appWindow.coverNotificationBody = ""
        appWindow.coverNotificationColor = appWindow.defaultCoverColor
        appWindow.coverNotificationIcon = ""
    }

    function updateCoverNotification(title, message, color, iconPath) {
        appWindow.coverNotificationTitle = title && title.length > 0 ? title : "Home Assistant"
        appWindow.coverNotificationBody = message || ""
        appWindow.coverNotificationColor = normalizeCoverColor(color)
        appWindow.coverNotificationIcon = iconPath || ""
    }

    function clearWidgetNotifications() {
        if (hassClientInstance.widget)
            hassClientInstance.widget.clearNotifications()
        var next = ({})
        var src = appWindow.notificationTags || ({})
        for (var key in src) {
            // -1 marks tags that only live on the widget. Real Lipstick ids
            // stay tracked so HA clear_notification can still close them.
            if (src.hasOwnProperty(key) && src[key] !== -1)
                next[key] = src[key]
        }
        appWindow.notificationTags = next
    }

    function clearHaNotification(tag) {
        if (!tag || tag.length === 0)
            return
        if (hassClientInstance.widget)
            hassClientInstance.widget.dismissNotification(tag)
        var id = appWindow.notificationTags[tag]
        if (id && id !== -1) {
            var closer = notificationComponent.createObject(appWindow)
            if (closer) {
                closer.replacesId = id
                closer.close()
                closer.destroy()
            }
        }
        if (id) {
            var next = cloneTagMap()
            delete next[tag]
            appWindow.notificationTags = next
        }
        if (appWindow.notificationCount > 0)
            appWindow.notificationCount -= 1
        if (appWindow.notificationCount <= 0)
            appWindow.clearCoverNotification()
    }

    // Icons: prefer HA image/icon_url, else tinted mdi:notification_icon.
    // Color alone tints a default bell when no other icon is given.
    function trayIconPath(iconUrl, notificationIcon, color) {
        if (iconUrl.length > 0)
            return resolveMediaUrl(iconUrl)
        if (!mdiIcons.ready)
            return ""
        var mdiName = notificationIcon
        if (!mdiName.length && color.length > 0)
            mdiName = "mdi:bell"
        if (!mdiName.length)
            return ""
        var iconPath = mdiIcons.renderIconFile(mdiName, color, 128)
        console.log("Helmsman: mdi icon", mdiName, "color=", color, "path=", iconPath)
        return iconPath || ""
    }

    // Leaving summary/body empty makes Lipstick show the preview banner only
    // and keep nothing in the notification list, so the Events View widget
    // stays the single place the alert lives on.
    function publishBannerNotification(summary, body, subtitle, iconPath, urgency) {
        var n = notificationComponent.createObject(appWindow)
        if (!n) {
            console.log("Helmsman: failed to create banner Notification object")
            return
        }
        n.appName = "Helmsman"
        n.appIcon = "harbour-helmsman"
        n.previewSummary = summary
        n.previewBody = body
        if (subtitle.length > 0)
            n.subText = subtitle
        n.urgency = urgency
        if (iconPath.length > 0)
            n.icon = iconPath
        n.clicked.connect(function() { appWindow.activate() })
        try {
            n.publish()
        } catch (e) {
            console.log("Helmsman: banner publish failed:", e)
        }
    }

    function applyCoverNotification(summary, body, color, iconPath, replacing) {
        if (!hassClientInstance.coverNotificationsEnabled)
            return
        if (!replacing)
            appWindow.notificationCount += 1
        else if (appWindow.notificationCount < 1)
            appWindow.notificationCount = 1
        appWindow.updateCoverNotification(summary, body, color, iconPath)
    }

    function showHaNotification(title, message, data) {
        data = data || {}
        console.log("Helmsman: show notification", title, message)

        // HA clear_notification: dismiss a tagged notification.
        if (message === "clear_notification") {
            clearHaNotification(dataString(data, "tag"))
            return
        }

        var tag = dataString(data, "tag")
        var subtitle = dataString(data, "subtitle")
        if (!subtitle.length)
            subtitle = dataString(data, "subject")
        var iconUrl = dataString(data, "icon_url")
        if (!iconUrl.length)
            iconUrl = dataString(data, "image")
        var notificationIcon = dataString(data, "notification_icon")
        var color = dataString(data, "color")

        var replacing = tag.length > 0 && !!appWindow.notificationTags[tag]
        var summary = title && title.length > 0 ? title : "Home Assistant"
        var body = message || ""
        var coverIconPath = ""

        if (iconUrl.length > 0) {
            coverIconPath = resolveMediaUrl(iconUrl)
        } else if (mdiIcons.ready) {
            var mdiName = notificationIcon
            if (!mdiName.length && color.length > 0)
                mdiName = "mdi:bell"
            if (mdiName.length > 0)
                coverIconPath = mdiIcons.renderIconFile(mdiName, "#FFFFFF", 256)
        }

        var widgetEnabled = hassClientInstance.widget
                && hassClientInstance.widget.eventsViewWidgetEnabled === true
        if (widgetEnabled) {
            hassClientInstance.widget.pushNotification(
                        summary, body, appWindow.normalizeCoverColor(color),
                        coverIconPath, tag)
            appWindow.applyCoverNotification(summary, body, color, coverIconPath, replacing)
            appWindow.publishBannerNotification(
                        summary, body, subtitle,
                        appWindow.trayIconPath(iconUrl, notificationIcon, color),
                        appWindow.urgencyFromData(data))
            if (tag.length > 0) {
                var widgetTags = cloneTagMap()
                widgetTags[tag] = appWindow.notificationTags[tag] || -1
                appWindow.notificationTags = widgetTags
            }
            return
        }

        var n = notificationComponent.createObject(appWindow)
        if (!n) {
            console.log("Helmsman: failed to create Notification object")
            return
        }

        // data.group / data.channel are accepted by HA but not mapped here —
        // encoding them into appName/category previously broke Lipstick publish.
        if (replacing)
            n.replacesId = appWindow.notificationTags[tag]
        else
            n.replacesId = 0

        // Keep a stable appName. Encoding HA group into appName previously
        // broke publish on some Lipstick builds (and skipped the cover update).
        n.appName = "Helmsman"
        n.appIcon = "harbour-helmsman"
        n.summary = summary
        n.body = body
        n.previewSummary = summary
        n.previewBody = body
        if (subtitle.length > 0)
            n.subText = subtitle
        n.urgency = urgencyFromData(data)

        var trayPath = appWindow.trayIconPath(iconUrl, notificationIcon, color)
        if (trayPath.length > 0)
            n.icon = trayPath

        // Prefer hint over .resident — older nemo plugins may lack the property.
        if (dataBool(data, "sticky") || dataBool(data, "persistent"))
            n.setHintValue("resident", true)

        var timeoutSec = parseInt(dataString(data, "timeout"), 10)
        if (!isNaN(timeoutSec) && timeoutSec > 0)
            n.expireTimeout = timeoutSec * 1000

        if (data.progress !== undefined && data.progress !== null) {
            var progress = Number(data.progress)
            var progressMax = Number(data.progress_max)
            if (isNaN(progressMax) || progressMax <= 0)
                progressMax = 1
            if (dataBool(data, "progress_indeterminate")) {
                if (Notification.ProgressIndeterminate !== undefined)
                    n.progress = Notification.ProgressIndeterminate
            } else if (!isNaN(progress) && progress >= 0) {
                n.progress = Math.max(0, Math.min(1, progress / progressMax))
            }
        }

        // Cover first: publish() can fail with some HA data fields and must not
        // prevent the cover from reflecting the latest alert.
        appWindow.applyCoverNotification(summary, body, color, coverIconPath, replacing)

        n.clicked.connect(function() { appWindow.activate() })
        try {
            n.publish()
            console.log("Helmsman: published notification id=", n.replacesId)
            if (tag.length > 0) {
                var next = cloneTagMap()
                next[tag] = n.replacesId
                appWindow.notificationTags = next
            }
        } catch (e) {
            console.log("Helmsman: notification publish failed:", e)
        }
    }

    function findHomePage() {
        if (!pageStack || typeof pageStack.find !== "function")
            return null
        return pageStack.find(function(page) {
            return page && page.objectName === "HomePage"
        })
    }

    function wakeHomePageIfPresent() {
        var home = appWindow.findHomePage()
        if (home && typeof home.onAppForegrounded === "function")
            home.onAppForegrounded()
    }

    function captureHomeSnapshotIfPresent() {
        var home = appWindow.findHomePage()
        if (home && typeof home.captureDashboardSnapshot === "function")
            home.captureDashboardSnapshot()
    }

    onApplicationActiveChanged: {
        if (applicationActive) {
            appWindow.clearCoverNotification()
            appWindow.clearWidgetNotifications()
            appWindow.wakeHomePageIfPresent()
            hassClientInstance.notifyAppForegrounded()
        } else {
            appWindow.captureHomeSnapshotIfPresent()
        }
    }

    HassClient {
        id: hassClientInstance
    }

    BatteryMonitor {
        hassClient: hassClientInstance
    }

    LocationReporter {
        hassClient: hassClientInstance
    }

    WifiChecker {
        id: appWifi
        onNetworkChanged: {
            hassClientInstance.updateNetworkState(appWifi.ready, appWifi.connected, appWifi.ssid)
        }
    }

    MdiIconRenderer {
        id: mdiIcons
        Component.onCompleted: hassClientInstance.widget.iconRenderer = mdiIcons
    }

    Component {
        id: notificationComponent
        Notification { }
    }

    Connections {
        target: hassClientInstance
        onLoggedInChanged: {
            if (hassClientInstance.loggedIn
                    && pageStack.currentPage
                    && pageStack.currentPage.objectName !== "SplashPage")
                appWindow.goHomeIfLoggedIn()
            appWindow.flushPendingEventsFavorites()
        }
        onLoginSucceeded: {
            if (pageStack.currentPage
                    && pageStack.currentPage.objectName !== "SplashPage")
                appWindow.goHomeIfLoggedIn()
            appWindow.flushPendingEventsFavorites()
        }
        onNotificationReceived: {
            console.log("Helmsman: HA push received")
            appWindow.showHaNotification(title, message, data)
        }
        onPushConnectedChanged: {
            console.log("Helmsman: pushConnected=", hassClientInstance.pushConnected,
                        "registered=", hassClientInstance.mobileAppRegistered)
        }
    }

    Connections {
        target: hassClientInstance.widget
        onOpenFavoritesRequested: appWindow.openEventsViewFavorites()
        onActivateAppRequested: appWindow.activate()
    }

    Connections {
        target: hassClientInstance
        onCoverNotificationsEnabledChanged: {
            if (!hassClientInstance.coverNotificationsEnabled)
                appWindow.clearCoverNotification()
        }
        onNativeDashboardEnabledChanged: {
            if (hassClientInstance.loggedIn
                    && pageStack.currentPage
                    && pageStack.currentPage.objectName !== "SplashPage")
                appWindow.replaceHomePage()
        }
    }

    Connections {
        target: pageStack
        onCurrentPageChanged: appWindow.flushPendingEventsFavorites()
    }

    initialPage: Component {
        FirstPage {
            hassClient: hassClientInstance
            mdiIcons: mdiIcons
        }
    }
    cover: CoverDir.CoverPage {
        hassClient: hassClientInstance
        mdiIcons: mdiIcons
        notificationCount: appWindow.notificationCount
        notificationTitle: appWindow.coverNotificationTitle
        notificationBody: appWindow.coverNotificationBody
        notificationColor: appWindow.coverNotificationColor
        notificationIcon: appWindow.coverNotificationIcon
    }
    allowedOrientations: Orientation.All
}
