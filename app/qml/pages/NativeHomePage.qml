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
    property bool notifiedReady: false
    backNavigation: false

    function openSettings() {
        pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { hassClient: hassClient })
    }

    function openWeb(path) {
        pageStack.push(Qt.resolvedUrl("HassWebViewPage.qml"), {
                           hassClient: hassClient,
                           startPath: path || "/lovelace"
                       })
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
        if (parts[0] === "lovelace" || parts[0] === "home") {
            dashboard.setCurrentUrlPath("")
            if (parts.length > 1 && parts[1].length)
                dashboard.selectViewByPath(parts[1])
            return
        }
        dashboard.setCurrentUrlPath(parts[0])
        if (parts.length > 1 && parts[1].length)
            dashboard.selectViewByPath(parts[1])
    }

    WifiChecker {
        id: wifi
        onNetworkChanged: hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
    }

    Connections {
        target: hassClient
        onLoggedInChanged: {
            if (!hassClient.loggedIn)
                pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
    }

    Connections {
        target: dashboard
        onReadyChanged: {
            if (dashboard && dashboard.ready && !page.notifiedReady) {
                page.notifiedReady = true
                if (hassClient)
                    hassClient.notifyDashboardReady()
            }
        }
        onPendingNavigateChanged: {
            if (!dashboard || !dashboard.pendingNavigate.length)
                return
            var path = dashboard.pendingNavigate
            dashboard.clearPendingNavigate()
            page.handleNavigate(path)
        }
        onPendingUrlChanged: {
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
            if (!dashboard || !dashboard.pendingMoreInfo.length)
                return
            var id = dashboard.pendingMoreInfo
            dashboard.clearPendingMoreInfo()
            page.openMoreInfo(id)
        }
        onPendingWebPathChanged: {
            if (!dashboard || !dashboard.pendingWebPath.length)
                return
            var path = dashboard.pendingWebPath
            dashboard.clearPendingWebPath()
            page.openWeb(path)
        }
        onDashboardsChanged: dashboardBox.syncFromCoordinator()
        onCurrentUrlPathChanged: dashboardBox.syncFromCoordinator()
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge
        clip: true

        PullDownMenu {
            MenuItem {
                text: "Settings"
                onClicked: page.openSettings()
            }
            MenuItem {
                text: "Open Home Assistant"
                onClicked: page.openWeb("/lovelace")
            }
            MenuItem {
                text: "Refresh"
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
            spacing: Theme.paddingMedium

            PageHeader {
                title: {
                    var view = dashboard ? dashboard.currentView : null
                    if (view && view.title)
                        return view.title
                    return hassClient && hassClient.instanceName.length
                            ? hassClient.instanceName : "Home Assistant"
                }
            }

            ComboBox {
                id: dashboardBox
                width: parent.width
                visible: dashboard && dashboard.dashboards && dashboard.dashboards.length > 1
                label: "Dashboard"
                property bool applyingIndex: false

                function pathAt(index) {
                    if (!dashboard || index < 0 || index >= dashboard.dashboards.length)
                        return ""
                    var d = dashboard.dashboards[index]
                    return (d && d.url_path) ? String(d.url_path) : ""
                }

                function syncFromCoordinator() {
                    if (!dashboard)
                        return
                    var path = dashboard.currentUrlPath || ""
                    var list = dashboard.dashboards
                    var idx = 0
                    for (var i = 0; i < list.length; ++i) {
                        var p = (list[i] && list[i].url_path) ? String(list[i].url_path) : ""
                        if (p === path) {
                            idx = i
                            break
                        }
                    }
                    if (currentIndex !== idx) {
                        applyingIndex = true
                        currentIndex = idx
                        applyingIndex = false
                    }
                }

                menu: ContextMenu {
                    Repeater {
                        model: dashboard ? dashboard.dashboards : []
                        MenuItem {
                            property string dashboardPath: (modelData && modelData.url_path)
                                                           ? String(modelData.url_path) : ""
                            text: (modelData.title && String(modelData.title).length)
                                  ? modelData.title
                                  : (dashboardPath || "Overview")
                            onClicked: {
                                if (dashboard)
                                    dashboard.setCurrentUrlPath(dashboardPath)
                            }
                        }
                    }
                }

                onCurrentIndexChanged: {
                    if (applyingIndex || !dashboard)
                        return
                    var path = pathAt(currentIndex)
                    if (path !== (dashboard.currentUrlPath || ""))
                        dashboard.setCurrentUrlPath(path)
                }
            }

            Flickable {
                id: tabFlick
                visible: dashboard && dashboard.views && dashboard.views.length > 1
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
                        model: dashboard ? dashboard.views : []
                        Label {
                            text: modelData.title || modelData.path || ("View " + (index + 1))
                            color: index === (dashboard ? dashboard.currentViewIndex : -1)
                                   ? Theme.highlightColor : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: index === (dashboard ? dashboard.currentViewIndex : -1)
                            MouseArea {
                                anchors.fill: parent
                                onClicked: dashboard.setCurrentViewIndex(index)
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
                visible: dashboard && dashboard.currentView
                         && dashboard.currentView.badges
                         && dashboard.currentView.badges.length
                Repeater {
                    model: dashboard && dashboard.currentView ? dashboard.currentView.badges : []
                    Label {
                        property string entityId: typeof modelData === "string"
                                                  ? modelData
                                                  : (modelData.entity ? String(modelData.entity) : "")
                        text: (dashboard && entityId.length && page.rev >= 0)
                              ? dashboard.formatState(entityId) : ""
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                        MouseArea {
                            anchors.fill: parent
                            onClicked: page.openMoreInfo(entityId)
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: !dashboard || (!dashboard.ready && dashboard.busy)
                BusyIndicator {
                    anchors.centerIn: parent
                    running: parent.visible
                    size: BusyIndicatorSize.Medium
                }
            }

            Label {
                visible: dashboard && dashboard.lastError.length > 0 && !dashboard.ready
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
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                sourceComponent: {
                    if (!dashboard || !dashboard.currentView)
                        return emptyComp
                    var t = dashboard.currentView.type || "masonry"
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
                text: dashboard && dashboard.busy ? "Loading dashboard…" : "No views"
                color: Theme.secondaryColor
            }
        }
    }

    Component {
        id: sectionsComp
        SectionsLayout {
            width: viewLoader.width
            view: dashboard ? dashboard.currentView : ({})
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: masonryComp
        MasonryLayout {
            width: viewLoader.width
            view: dashboard ? dashboard.currentView : ({})
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: panelComp
        PanelLayout {
            width: viewLoader.width
            view: dashboard ? dashboard.currentView : ({})
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: sidebarComp
        SidebarLayout {
            width: viewLoader.width
            view: dashboard ? dashboard.currentView : ({})
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component.onCompleted: {
        if (dashboard && dashboard.ready && hassClient && !page.notifiedReady) {
            page.notifiedReady = true
            hassClient.notifyDashboardReady()
        }
    }
}
