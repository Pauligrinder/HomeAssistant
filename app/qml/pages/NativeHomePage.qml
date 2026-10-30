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
    // Punch-hole / notch: pad the first paint so cards sit below it. The inset
    // is part of the flickable content (column.y), so scrolling can still carry
    // cards under the cutout. Only upright portrait — landscape puts the cutout
    // on the side, inverted portrait at the bottom.
    readonly property int topCutoutInset: {
        if (typeof Screen === "undefined" || !Screen.topCutout)
            return 0
        if (page.orientation === Orientation.Landscape
                || page.orientation === Orientation.LandscapeInverted
                || page.orientation === Orientation.PortraitInverted)
            return 0
        return Math.max(0, Screen.topCutout.y + Screen.topCutout.height)
    }
    // Full-bleed panel maps draw under the punch-hole; the map itself pads its
    // fit/markers. Tab/badge chrome above a map still needs the page inset.
    readonly property bool mapUnderNotch: {
        if (!page.panelMapView || page.topCutoutInset <= 0)
            return false
        if (page.showViewTabs || page.onSubview)
            return false
        var view = page.boundView
        if (view && view.badges && view.badges.length)
            return false
        return true
    }
    readonly property int viewFillHeight: {
        if (!page.panelMapView)
            return 0
        var h = flick.height - column.y
        var n = 1
        if (subviewHeader.visible) {
            h -= subviewHeader.height
            n++
        } else if (tabFlick.visible) {
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
    // Tabs omit subviews and views hidden for this user (HA hui-root).
    readonly property var tabViews: {
        var rev = dashboard ? dashboard.configsRevision : 0
        var uid = dashboard ? dashboard.userId : ""
        var all = page.boundViews
        var out = []
        if (!all || !all.length)
            return out
        for (var i = 0; i < all.length; ++i) {
            var v = all[i]
            if (!v || v.subview)
                continue
            if (!page.viewVisibleToUser(v, uid))
                continue
            out.push({ "view": v, "index": i })
        }
        return out
    }
    readonly property bool onSubview: !!(page.boundView && page.boundView.subview)
    readonly property bool showViewTabs: !page.onSubview && page.tabViews.length > 1
    property int returnViewIndex: 0
    // View background wins over the dashboard-wide background.
    readonly property var backgroundConfig: {
        var rev = dashboard ? dashboard.configsRevision : 0
        var view = page.boundView
        if (view && view.background !== undefined && view.background !== null
                && view.background !== "")
            return view.background
        var cfg = dashboard ? dashboard.currentConfig : null
        if (cfg && cfg.background !== undefined && cfg.background !== null
                && cfg.background !== "")
            return cfg.background
        return null
    }
    readonly property bool boundReady: {
        var rev = dashboard ? dashboard.configsRevision : 0
        if (!dashboard || rev < 0)
            return false
        // Cached Overview sits on the empty path. Hide it until the profile
        // default is known, or the web/switcher selection is explicit.
        if (page.followDefault && !dashboard.defaultsReady && !dashboard.explicitDashboard)
            return false
        return dashboard.pathConfigReady(page.boundPath)
    }
    // Empty views, or views made only of webpage/iframe/custom HTML cards,
    // cannot usefully render natively — offer the webview dashboard instead.
    readonly property bool needsWebviewPrompt: {
        var rev = dashboard ? dashboard.configsRevision : 0
        if (!dashboard || rev < 0 || !page.boundReady)
            return false
        if (dashboard.busy)
            return false
        return page.viewIsEmptyOrWebHtml(page.boundView)
    }
    // Panel MapLibre maps need horizontal pan; Silica back-swipe steals it.
    backNavigation: !page.followDefault && !page.panelMapView

    function cardIsWebHtml(card) {
        if (!card)
            return true
        var t = String(card.type || "")
        if (t === "webpage" || t === "iframe")
            return true
        if (t.indexOf("custom:html") === 0 || t === "custom:html-template-card"
                || t === "custom:html-card" || t === "custom:config-template-card")
            return true
        // Stacks, grids, and layout-card roots (custom:horizontal-layout, …):
        // treat nested cards as the real content.
        var nested = card.cards || []
        if (nested.length
                || t === "vertical-stack" || t === "horizontal-stack" || t === "grid") {
            if (!nested.length)
                return true
            for (var i = 0; i < nested.length; ++i) {
                if (!page.cardIsWebHtml(nested[i]))
                    return false
            }
            return true
        }
        if (t === "conditional" && card.card)
            return page.cardIsWebHtml(card.card)
        return false
    }

    // Map a Lovelace view type onto one of our layout components. Exact matches
    // first; then word hints (layout-card uses custom:horizontal-layout etc.).
    // Unknown types still get masonry so the card list is never dropped.
    function layoutComponentForType(type) {
        var t = String(type || "").toLowerCase()
        if (t === "sections" || t.indexOf("section") >= 0)
            return sectionsComp
        if (t === "panel")
            return panelComp
        if (t === "sidebar" || t.indexOf("sidebar") >= 0)
            return sidebarComp
        // layout-card column layouts (thomasloven). CSS width/300, scaled by
        // Theme.pixelRatio so HD phones match the webview's one column.
        if (t.indexOf("horizontal-layout") >= 0)
            return horizontalComp
        if (t.indexOf("vertical-layout") >= 0)
            return verticalComp
        return masonryComp
    }

    function viewLooksLikeSections(view) {
        if (!view)
            return false
        var t = String(view.type || "").toLowerCase()
        if (t === "sections" || t.indexOf("section") >= 0)
            return true
        return !!(view.sections && view.sections.length
                  && !(view.cards && view.cards.length))
    }

    function collectViewCards(view) {
        var out = []
        if (!view)
            return out
        var cards = view.cards || []
        for (var i = 0; i < cards.length; ++i)
            out.push(cards[i])
        var sections = view.sections || []
        for (var s = 0; s < sections.length; ++s) {
            var sectionCards = (sections[s] && sections[s].cards) ? sections[s].cards : []
            for (var c = 0; c < sectionCards.length; ++c)
                out.push(sectionCards[c])
        }
        return out
    }

    // Overview's generated strategy is one card per entity. Instantiating all
    // of them freezes the UI, so large views are shown 50 cards at a time.
    readonly property int cardPageSize: 50
    property int cardPage: 0
    readonly property int cardCount: page.layoutCardCount(page.boundView)
    readonly property int cardPageCount: {
        var n = page.cardCount
        if (n <= page.cardPageSize)
            return 1
        return Math.ceil(n / page.cardPageSize)
    }
    readonly property var displayView: page.pagedView(page.boundView, page.cardPage)

    function layoutCardCount(view) {
        if (!view)
            return 0
        if (page.viewLooksLikeSections(view)) {
            var total = 0
            var sections = view.sections || []
            for (var s = 0; s < sections.length; ++s) {
                var cards = (sections[s] && sections[s].cards) ? sections[s].cards : []
                total += cards.length
            }
            return total
        }
        var cards = view.cards || []
        return cards.length
    }

    function sliceList(list, start, count) {
        var out = []
        if (!list || count <= 0)
            return out
        var n = list.length
        if (start < 0)
            start = 0
        var end = start + count
        if (end > n)
            end = n
        for (var i = start; i < end; ++i)
            out.push(list[i])
        return out
    }

    function pagedView(view, pageIndex) {
        var size = page.cardPageSize
        if (!view)
            return ({})
        var index = pageIndex > 0 ? pageIndex : 0
        if (page.viewLooksLikeSections(view)) {
            var sections = view.sections || []
            var total = 0
            for (var s = 0; s < sections.length; ++s) {
                var list = (sections[s] && sections[s].cards) ? sections[s].cards : []
                total += list.length
            }
            if (total <= size)
                return view
            var maxPage = Math.floor((total - 1) / size)
            if (index > maxPage)
                index = maxPage
            var start = index * size
            var end = start + size
            var built = []
            var seen = 0
            for (var s2 = 0; s2 < sections.length; ++s2) {
                var section = sections[s2] || ({})
                var cards = section.cards || []
                var from = seen
                var to = seen + cards.length
                seen = to
                if (to <= start || from >= end)
                    continue
                var localStart = start > from ? start - from : 0
                var localEnd = end < to ? end - from : cards.length
                var picked = []
                for (var c = localStart; c < localEnd; ++c)
                    picked.push(cards[c])
                built.push({
                               title: section.title,
                               type: section.type,
                               visibility: section.visibility,
                               cards: picked
                           })
            }
            return {
                title: view.title,
                path: view.path,
                icon: view.icon,
                type: view.type || "sections",
                badges: view.badges,
                cards: [],
                sections: built
            }
        }
        var flat = view.cards || []
        if (flat.length <= size)
            return view
        var maxFlat = Math.floor((flat.length - 1) / size)
        if (index > maxFlat)
            index = maxFlat
        return {
            title: view.title,
            path: view.path,
            icon: view.icon,
            type: view.type,
            badges: view.badges,
            cards: page.sliceList(flat, index * size, size),
            sections: view.sections || []
        }
    }

    function viewIsEmptyOrWebHtml(view) {
        if (!view)
            return true
        var cards = page.collectViewCards(view)
        if (!cards.length)
            return true
        for (var i = 0; i < cards.length; ++i) {
            if (!page.cardIsWebHtml(cards[i]))
                return false
        }
        return true
    }

    function switchToWebviewDashboards() {
        if (hassClient)
            hassClient.nativeDashboardEnabled = false
    }

    function viewVisibleToUser(view, userId) {
        if (!view)
            return false
        var vis = view.visible
        if (vis === undefined || vis === null)
            return true
        if (vis === true || vis === "true")
            return true
        if (vis === false || vis === "false")
            return false
        // Legacy: visible: "<user id>"
        if (typeof vis === "string")
            return vis.length > 0 && vis === String(userId || "")
        // visible: [ { user: "…" }, … ]
        if (vis.length !== undefined) {
            var uid = String(userId || "")
            for (var i = 0; i < vis.length; ++i) {
                var entry = vis[i]
                if (entry && String(entry.user || "") === uid)
                    return true
            }
            return false
        }
        return true
    }

    function viewHasIcon(view) {
        return !!(view && view.icon && String(view.icon).length)
    }

    function viewShowIconAndTitle(view) {
        return !!(view && view.show_icon_and_title && page.viewHasIcon(view)
                  && view.title && String(view.title).length)
    }

    function viewTabTitle(view) {
        if (view && view.title && String(view.title).length)
            return String(view.title)
        if (view && view.path && String(view.path).length)
            return String(view.path)
        return i18n.translation("unnamed_view")
    }

    function selectViewIndex(index) {
        var views = page.boundViews
        if (!views || index < 0 || index >= views.length)
            return
        var next = views[index]
        var cur = page.boundView
        if (next && next.subview && !(cur && cur.subview))
            page.returnViewIndex = page.viewIndex
        page.viewIndex = index
    }

    function leaveSubview() {
        var view = page.boundView
        if (view && view.back_path && String(view.back_path).length) {
            page.handleNavigate(String(view.back_path))
            return
        }
        var idx = page.returnViewIndex
        var views = page.boundViews
        if (views && idx >= 0 && idx < views.length && !(views[idx] && views[idx].subview))
            page.viewIndex = idx
        else if (page.tabViews.length)
            page.viewIndex = page.tabViews[0].index
        else
            page.viewIndex = 0
    }

    function selectLocalView(path) {
        if (!path || !page.boundViews)
            return
        for (var i = 0; i < page.boundViews.length; i++) {
            if (page.boundViews[i] && String(page.boundViews[i].path || "") === path) {
                page.selectViewIndex(i)
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
        page.dashboard.pinDashboard(norm)
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

    function openEditDashboard() {
        if (!dashboard || !dashboard.canEditDashboard(page.boundPath))
            return
        var path = page.boundPath.length ? ("/" + page.boundPath) : "/lovelace"
        var viewPath = (page.boundView && page.boundView.path)
                ? String(page.boundView.path) : ""
        if (viewPath.length)
            path += "/" + encodeURIComponent(viewPath)
        page.openWeb(path + "?edit=1")
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

    function syncBoundDashboard() {
        if (!dashboard || page.status !== PageStatus.Active)
            return
        // followDefault binds to the profile default. Until that value has
        // arrived, syncing would pin Overview and then keep showing it.
        if (page.followDefault && !dashboard.defaultsReady)
            return
        if (dashboard.currentUrlPath !== page.boundPath)
            dashboard.setCurrentUrlPath(page.boundPath)
    }

    onStatusChanged: {
        if (status !== PageStatus.Active)
            return
        page.syncBoundDashboard()
        page.consumePendingWebPath()
    }

    onBoundPathChanged: page.cardPage = 0
    onViewIndexChanged: page.cardPage = 0
    onCardCountChanged: {
        var pages = page.cardCount > page.cardPageSize
                ? Math.ceil(page.cardCount / page.cardPageSize) : 1
        if (page.cardPage >= pages)
            page.cardPage = pages - 1
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
        onDefaultsReadyChanged: page.syncBoundDashboard()
        onDefaultUrlPathChanged: page.syncBoundDashboard()
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

    DashboardBackground {
        id: dashBackground
        anchors.fill: parent
        anchors.bottomMargin: page.cardPageCount > 1
                              ? Theme.itemSizeSmall + Theme.paddingMedium : 0
        z: -1
        dashboard: page.dashboard
        background: page.backgroundConfig
        contentHeight: flick.contentHeight
        contentY: flick.contentY
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        anchors.bottomMargin: page.cardPageCount > 1
                             ? Theme.itemSizeSmall + Theme.paddingMedium : 0
        contentHeight: page.panelMapView ? height : (column.y + column.height + Theme.paddingLarge)
        // Panel maps are interactive MapLibre; vertical flick would steal pans.
        interactive: !page.panelMapView
        clip: true
        // Keep the ambience / background visible between cards.
        // (SilicaFlickable is transparent by default.)

        PullDownMenu {
            // Panel maps consume the top drag for map gestures; this menu
            // cannot be pulled there, so hide it and rely on back-swipe.
            visible: !page.panelMapView
            enabled: !page.panelMapView
            MenuItem {
                text: i18n.translation("edit_dashboard")
                visible: {
                    if (!dashboard)
                        return false
                    // These reads keep the binding live as the user and the
                    // dashboard mode arrive.
                    dashboard.userIsAdmin
                    dashboard.dashboards
                    dashboard.switcherItems
                    return dashboard.canEditDashboard(page.boundPath)
                }
                onClicked: page.openEditDashboard()
            }
            MenuItem {
                text: i18n.translation("change_dashboard")
                visible: !!(dashboard && dashboard.switcherItems
                            && dashboard.switcherItems.length > 1)
                onClicked: page.openDashboardSwitcher()
            }
            MenuItem {
                text: i18n.translation("settings")
                onClicked: page.openSettings()
            }
            MenuItem {
                text: i18n.translation("refresh")
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
            // the very top of the screen. Use the cutout clearance when the
            // punch-hole is present — stacking paddingLarge on top left the
            // tab bar floating too far below the notch. Panel maps keep y at 0
            // so tiles bleed under the cutout; MapCard pads content instead.
            y: {
                if (page.mapUnderNotch)
                    return 0
                if (page.topCutoutInset > 0)
                    return page.topCutoutInset
                return Theme.paddingLarge
            }
            spacing: Theme.paddingMedium

            // Subview: HA shows back + title, not the tab strip.
            Item {
                id: subviewHeader
                visible: page.onSubview
                width: parent.width
                height: visible ? Theme.itemSizeSmall : 0

                IconButton {
                    id: subviewBack
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-back"
                    onClicked: page.leaveSubview()
                }

                Label {
                    anchors.left: subviewBack.right
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    truncationMode: TruncationMode.Fade
                    color: Theme.highlightColor
                    text: page.viewTabTitle(page.boundView)
                }
            }

            Flickable {
                id: tabFlick
                // Match HA: tabs only when 2+ non-subview, visible views.
                visible: page.showViewTabs
                width: parent.width
                height: visible ? Theme.itemSizeSmall : 0
                // Non-primary dashboards show the Silica back indicator; keep
                // the first tab clear of that hit target / visual.
                readonly property int leftPad: page.followDefault
                                              ? Theme.horizontalPageMargin
                                              : Theme.itemSizeLarge
                contentWidth: tabRow.x + tabRow.width + Theme.horizontalPageMargin
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: tabRow
                    spacing: Theme.paddingLarge
                    x: tabFlick.leftPad
                    Repeater {
                        model: page.tabViews
                        Item {
                            id: tabItem
                            property var tab: modelData
                            property var tabView: tab && tab.view ? tab.view : ({})
                            property int viewIdx: tab && tab.index !== undefined ? tab.index : -1
                            property bool selected: viewIdx === page.viewIndex
                            property bool iconAndTitle: page.viewShowIconAndTitle(tabView)
                            property bool iconOnly: page.viewHasIcon(tabView) && !iconAndTitle
                            property bool titleOnly: !iconOnly && !iconAndTitle
                            // Icon-only tabs are otherwise just the glyph width.
                            readonly property int hPad: iconOnly
                                                        ? Theme.paddingMedium
                                                        : 0
                            width: tabContent.width + 2 * hPad
                            height: Theme.itemSizeSmall
                            opacity: tabTap.pressed ? 0.6 : 1.0
                            Behavior on opacity {
                                NumberAnimation { duration: 100 }
                            }

                            Row {
                                id: tabContent
                                anchors.centerIn: parent
                                spacing: Theme.paddingSmall

                                MdiIcon {
                                    visible: tabItem.iconOnly || tabItem.iconAndTitle
                                    anchors.verticalCenter: parent.verticalCenter
                                    mdiIcons: page.mdiIcons
                                    name: tabItem.tabView.icon ? String(tabItem.tabView.icon) : ""
                                    iconColor: tabItem.selected
                                               ? Theme.highlightColor : Theme.secondaryColor
                                    width: Theme.iconSizeSmall
                                }

                                Label {
                                    visible: tabItem.iconAndTitle || tabItem.titleOnly
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.viewTabTitle(tabItem.tabView)
                                    color: tabItem.selected
                                           ? Theme.highlightColor : Theme.secondaryColor
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }

                            MouseArea {
                                id: tabTap
                                anchors.fill: parent
                                onClicked: page.selectViewIndex(tabItem.viewIdx)
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
                    if (page.needsWebviewPrompt)
                        return webviewPromptComp
                    if (!page.boundReady || !page.boundView)
                        return emptyComp
                    // Missing / unknown type still renders when cards exist
                    // (layout-card roots like custom:horizontal-layout).
                    if (!page.boundView.type
                            && !page.collectViewCards(page.boundView).length)
                        return emptyComp
                    return page.layoutComponentForType(page.boundView.type)
                }
            }
        }
    }

    Row {
        id: cardPager
        z: 2
        visible: page.cardPageCount > 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingMedium
        spacing: Theme.paddingLarge

        IconButton {
            width: Theme.itemSizeSmall
            height: Theme.itemSizeSmall
            icon.source: "image://theme/icon-m-left"
            enabled: page.cardPage > 0
            onClicked: {
                page.cardPage = Math.max(0, page.cardPage - 1)
                flick.contentY = 0
            }
        }
        IconButton {
            width: Theme.itemSizeSmall
            height: Theme.itemSizeSmall
            icon.source: "image://theme/icon-m-right"
            enabled: page.cardPage + 1 < page.cardPageCount
            onClicked: {
                page.cardPage = Math.min(page.cardPageCount - 1, page.cardPage + 1)
                flick.contentY = 0
            }
        }
    }

    Component {
        id: webviewPromptComp
        Column {
            width: viewLoader.width
            spacing: Theme.paddingLarge

            Label {
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: i18n.translation("dashboard_unsupported")
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: i18n.translation("change_to_webview_based_dashboards")
                onClicked: page.switchToWebviewDashboards()
            }
        }
    }

    Component {
        id: emptyComp
        Item {
            width: viewLoader.width
            height: Theme.itemSizeLarge
            // lastError is shown by the label above the loader.
            visible: !(dashboard && dashboard.lastError && dashboard.lastError.length)
            Label {
                anchors.centerIn: parent
                text: {
                    if (dashboard && dashboard.busy)
                        return i18n.translation("loading_dashboard")
                    if (dashboard && !dashboard.connected)
                        return i18n.translation("connecting_to_home_assistant")
                    return i18n.translation("no_views")
                }
                color: Theme.secondaryColor
            }
        }
    }

    Component {
        id: sectionsComp
        SectionsLayout {
            width: viewLoader.width
            view: page.displayView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: masonryComp
        MasonryLayout {
            width: viewLoader.width
            view: page.displayView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: horizontalComp
        HorizontalLayout {
            width: viewLoader.width
            view: page.displayView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: verticalComp
        VerticalLayout {
            width: viewLoader.width
            view: page.displayView
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
            topContentInset: page.mapUnderNotch ? page.topCutoutInset : 0
            view: page.displayView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    Component {
        id: sidebarComp
        SidebarLayout {
            width: viewLoader.width
            view: page.displayView
            dashboard: page.dashboard
            hassClient: page.hassClient
            mdiIcons: page.mdiIcons
        }
    }

    // Explicit back control on panel maps (backNavigation is off so pan works).
    MapBackButton {
        anchors.left: parent.left
        anchors.top: parent.top
        z: 50
        visible: page.panelMapView && !page.followDefault
        onClicked: pageStack.pop()
    }

    Component.onCompleted: {
        if (dashboard && dashboard.ready && hassClient && !page.notifiedReady
                && page.followDefault) {
            page.notifiedReady = true
            hassClient.notifyDashboardReady()
        }
    }
}
