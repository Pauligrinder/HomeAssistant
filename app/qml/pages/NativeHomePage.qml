import QtQuick 2.6
import Sailfish.Silica 1.0
import "../dashboard"
import "../components"

Page {
    id: page
    objectName: "HomePage"
    property var hassClient
    property var mdiIcons
    property var dashboard: hassClient ? hassClient.lovelace : null
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property bool panelMapView: {
        if (!page.boundView || !page.boundView.type)
            return false
        if (String(page.boundView.type || "") !== "panel")
            return false
        var cards = page.boundView.cards
        if (!cards || cards.length < 1)
            return false
        return String(cards[0].type || "") === "map"
    }
    readonly property int viewFillHeight: {
        if (!page.panelMapView)
            return 0
        var h = flick.height - column.y
        var n = 1
        if (tabFlick.visible) {
            h -= tabFlick.height
            n++
        }
        if (badges.visible) {
            h -= badges.height
            n++
        }
        h -= (n - 1) * column.spacing
        return Math.max(Theme.itemSizeHuge, Math.floor(h))
    }
    property bool notifiedReady: false
    property var confirmDialogPage: null
    // Root home follows the user default. Extra dashboards are stacked pages
    // pinned to urlPath so the Silica back swipe can peel them off.
    property bool followDefault: true
    property string urlPath: ""
    property int viewIndex: 0
    property string pendingViewPath: ""
    readonly property string boundPath: {
        if (!dashboard)
            return page.followDefault ? "" : page.urlPath
        return dashboard.normalizedUrlPath(page.followDefault
                                           ? (dashboard.defaultUrlPath || "")
                                           : page.urlPath)
    }
    readonly property var boundViews: {
        var rev = dashboard ? dashboard.configsRevision : 0
        if (!dashboard || rev < 0)
            return []
        return dashboard.viewsForPath(page.boundPath)
    }
    readonly property var boundView: {
        var views = page.boundViews
        if (!views || !views.length)
            return ({})
        var i = page.viewIndex
        if (i < 0 || i >= views.length)
            i = 0
        return views[i] || ({})
    }
    readonly property bool boundReady: {
        var rev = dashboard ? dashboard.configsRevision : 0
        if (!dashboard || rev < 0)
            return false
        return dashboard.pathConfigReady(page.boundPath)
    }
    backNavigation: !page.followDefault

    function selectLocalView(path) {
        if (!path || !page.boundViews)
            return
        for (var i = 0; i < page.boundViews.length; i++) {
            if (page.boundViews[i] && String(page.boundViews[i].path || "") === path) {
                page.viewIndex = i
                return
            }
        }
    }

    function openPinnedDashboard(path, viewPath) {
        if (!dashboard)
            return
        var norm = dashboard.normalizedUrlPath(path || "")
        if (page.boundPath === norm) {
            if (viewPath)
                page.selectLocalView(viewPath)
            return
        }
        var existing = pageStack.find(function(p) {
            return p && p.objectName === "HomePage" && p.boundPath === norm
        })
        if (existing) {
            if (viewPath && typeof existing.selectLocalView === "function")
                existing.selectLocalView(viewPath)
            pageStack.pop(existing)
            return
        }
        page.dashboard.setCurrentUrlPath(norm)
        pageStack.push(Qt.resolvedUrl("NativeHomePage.qml"), {
                           hassClient: hassClient,
                           mdiIcons: page.mdiIcons,
                           followDefault: false,
                           urlPath: norm,
                           pendingViewPath: viewPath || ""
                       })
    }

    function openSettings() {
        pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { hassClient: hassClient })
    }

    function openDashboardSwitcher() {
        pageStack.push(Qt.resolvedUrl("DashboardSwitchPage.qml"), {
                           hassClient: hassClient,
                           mdiIcons: page.mdiIcons
                       })
    }

    function isSwitcherWebPanel(path) {
        if (!dashboard || !dashboard.switcherItems)
            return false
        var items = dashboard.switcherItems
        for (var i = 0; i < items.length; i++) {
            if (items[i] && items[i].kind !== "lovelace"
                    && String(items[i].url_path || "") === path)
                return true
        }
        return false
    }

    function openWeb(path, session, chromeless) {
        pageStack.push(Qt.resolvedUrl("HassWebViewPage.qml"), {
                           hassClient: hassClient,
                           startPath: path || "/lovelace",
                           ingressSession: session || "",
                           chromeless: !!chromeless
                       })
    }

    function consumePendingWebPath() {
        if (!dashboard || !dashboard.pendingWebPath.length)
            return
        if (page.status !== PageStatus.Active || pageStack.busy)
            return
        var path = dashboard.pendingWebPath
        var session = dashboard.ingressSession || ""
        var chromeless = !!dashboard.pendingWebChromeless
        dashboard.clearPendingWebPath()
        page.openWeb(path, session, chromeless)
    }

    function openMoreInfo(entityId) {
        if (!entityId)
            return
        pageStack.push(Qt.resolvedUrl("MoreInfoPage.qml"), {
                           hassClient: hassClient,
                           mdiIcons: page.mdiIcons,
                           entityId: entityId
                       })
    }

    function openActionConfirm(prompt, onOk, onCancel) {
        if (page.confirmDialogPage)
            return
        var dlg = pageStack.push(Qt.resolvedUrl("../components/ActionConfirmDialog.qml"),
                                 { prompt: prompt })
        page.confirmDialogPage = dlg
        dlg.accepted.connect(function() {
            page.confirmDialogPage = null
            if (onOk)
                onOk()
        })
        dlg.rejected.connect(function() {
            page.confirmDialogPage = null
            if (onCancel)
                onCancel()
        })
    }

    function handleNavigate(path) {
        if (!dashboard || !path)
            return
        var p = String(path)
        if (p.indexOf("http://") === 0 || p.indexOf("https://") === 0) {
            dashboard.performAction({ "action": "url", "url_path": p }, "")
            return
        }
        if (p.charAt(0) === "/")
            p = p.substring(1)
        var hash = p.indexOf("#")
        if (hash >= 0)
            p = p.substring(0, hash)
        var parts = p.split("/")
        if (!parts.length || !parts[0].length)
            return
        if (parts[0] === "energy" || parts[0] === "map" || parts[0] === "logbook"
                || parts[0] === "history" || parts[0] === "config"
                || parts[0] === "developer-tools" || parts[0] === "assist") {
            page.openWeb("/" + p)
            return
        }
        if (page.isSwitcherWebPanel(parts[0])) {
            dashboard.selectSwitcherPath(parts[0])
            return
        }
        page.openPinnedDashboard(parts[0], parts.length > 1 ? parts[1] : "")
    }

    WifiChecker {
        id: wifi
        onNetworkChanged: hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
    }

    Connections {
        target: pageStack
        onBusyChanged: {
            if (!pageStack.busy && page.status === PageStatus.Active)
                page.consumePendingWebPath()
        }
    }

    onStatusChanged: {
        if (status !== PageStatus.Active)
            return
        if (dashboard && dashboard.currentUrlPath !== page.boundPath)
            dashboard.setCurrentUrlPath(page.boundPath)
        page.consumePendingWebPath()
    }

    onBoundViewsChanged: {
        if (page.pendingViewPath && page.boundViews && page.boundViews.length) {
            page.selectLocalView(page.pendingViewPath)
            page.pendingViewPath = ""
        }
        if (page.boundViews && page.viewIndex >= page.boundViews.length)
            page.viewIndex = 0
    }

    Connections {
        target: hassClient
        onLoggedInChanged: {
            if (!hassClient.loggedIn && page.status === PageStatus.Active)
                pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
    }

    Connections {
        target: dashboard
        onReadyChanged: {
            if (dashboard && dashboard.ready && !page.notifiedReady
                    && page.followDefault) {
                page.notifiedReady = true
                if (hassClient)
                    hassClient.notifyDashboardReady()
            }
        }
        onPendingNavigateChanged: {
            if (page.status !== PageStatus.Active)
                return
            if (!dashboard || !dashboard.pendingNavigate.length)
                return
            var path = dashboard.pendingNavigate
            dashboard.clearPendingNavigate()
            page.handleNavigate(path)
        }
        onPendingUrlChanged: {
            if (page.status !== PageStatus.Active)
                return
            if (!dashboard || !dashboard.pendingUrl.length)
                return
            var url = dashboard.pendingUrl
            dashboard.clearPendingUrl()
            if (url.charAt(0) === "/")
                page.openWeb(url)
            else
                Qt.openUrlExternally(url)
        }
        onPendingMoreInfoChanged: {
            if (page.status !== PageStatus.Active)
                return
            if (!dashboard || !dashboard.pendingMoreInfo.length)
                return
            var id = dashboard.pendingMoreInfo
            dashboard.clearPendingMoreInfo()
            page.openMoreInfo(id)
        }
        onPendingWebPathChanged: {
            if (page.status === PageStatus.Active)
                page.consumePendingWebPath()
        }
        onPendingConfirmationChanged: {
            if (page.status !== PageStatus.Active)
                return
            var prompt = dashboard ? dashboard.pendingConfirmation : null
            if (!(prompt && prompt.active))
                return
            page.openActionConfirm(prompt, function() {
                if (dashboard)
                    dashboard.confirmPendingAction()
            }, function() {
                if (dashboard)
                    dashboard.cancelPendingAction()
            })
        }
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: page.panelMapView ? height : (column.y + column.height + Theme.paddingLarge)
        clip: true

        PullDownMenu {
            MenuItem {
                text: qsTr("Change dashboard")
                visible: !!(dashboard && dashboard.switcherItems
                            && dashboard.switcherItems.length > 1)
                onClicked: page.openDashboardSwitcher()
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: page.openSettings()
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: {
                    if (dashboard)
                        dashboard.refresh()
                }
            }
        }

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            // Without a page header the first row would otherwise sit against
            // the very top of the screen.
            y: Theme.paddingLarge
            spacing: Theme.paddingMedium

            Flickable {
                id: tabFlick
                visible: !!(page.boundViews && page.boundViews.length > 1)
                width: parent.width
                height: visible ? Theme.itemSizeSmall : 0
                contentWidth: tabRow.width
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: tabRow
                    spacing: Theme.paddingLarge
                    x: Theme.horizontalPageMargin
                    Repeater {
                        model: page.boundViews
                        Item {
                            width: Theme.itemSizeSmall
                            height: Theme.itemSizeSmall

                            MdiIcon {
                                anchors.centerIn: parent
                                mdiIcons: page.mdiIcons
                                name: modelData && modelData.icon
                                      ? String(modelData.icon) : "mdi:view-dashboard"
                                iconColor: index === page.viewIndex
                                           ? Theme.highlightColor : Theme.secondaryColor
                                width: Theme.iconSizeSmall
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: page.viewIndex = index
                            }
                        }
                    }
                }
            }

            Flow {
                id: badges
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium
                // A chained && yields undefined for a view without badges, which
                // QML refuses to assign and leaves the row taking up space.
                visible: !!(page.boundView && page.boundView.badges
                            && page.boundView.badges.length)
                Repeater {
                    model: page.boundView ? page.boundView.badges : []
                    BadgeChip {
                        dashboard: page.dashboard
                        mdiIcons: page.mdiIcons
                        badge: modelData
                        onClicked: page.openMoreInfo(entityId)
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: !page.boundReady && (!dashboard || dashboard.busy)
                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.visible
                    size: BusyIndicatorSize.Medium
                }
            }

            Label {
                visible: dashboard && dashboard.lastError.length > 0 && !page.boundReady
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: dashboard ? dashboard.lastError : ""
            }

            Loader {
                id: viewLoader
                width: page.panelMapView ? parent.width : parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: {
                    if (!page.boundView || !page.boundView.type)
                        return emptyComp
                    var t = page.boundView.type || "masonry"
                    if (t === "sections")
                        return sectionsComp
                    if (t === "panel")
                        return panelComp
                    if (t === "sidebar")
                        return sidebarComp
                    return masonryComp
                }
            }
        }
    }

    Component {
        id: emptyComp
        Item {
            width: viewLoader.width
            height: Theme.itemSizeLarge
            Label {
                anchors.centerIn: parent
                text: dashboard && dashboard.busy ? qsTr("Loading dashboard…") : qsTr("No views")
                color: Theme.secondaryColor
            }
        }
    }

    Component {
        id: sectionsComp
        SectionsLayout {
            width: viewLoader.width
            view: page.boundView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: masonryComp
        MasonryLayout {
            width: viewLoader.width
            view: page.boundView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: panelComp
        PanelLayout {
            width: viewLoader.width
            fillHeight: page.viewFillHeight
            view: page.boundView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: sidebarComp
        SidebarLayout {
            width: viewLoader.width
            view: page.boundView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component.onCompleted: {
        if (dashboard && dashboard.ready && hassClient && !page.notifiedReady
                && page.followDefault) {
            page.notifiedReady = true
            hassClient.notifyDashboardReady()
        }
    }
}
