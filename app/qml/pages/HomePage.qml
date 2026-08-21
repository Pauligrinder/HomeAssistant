import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import "../components"

WebViewPage {
    id: page
    objectName: "HomePage"
    property var hassClient
    property bool tokensInjected: false
    property bool bridgeInstalled: false
    property bool dashboardReady: false
    property bool readyCheckRunning: false
    property int readyCheckAttempts: 0
    property string lastLoadedBase: ""
    property color overlayBackgroundColor: page.fallbackOverlayBackground
    property color overlayTextColor: page.fallbackOverlayText
    readonly property color haDarkBackground: "#111111"
    readonly property color haDarkText: "#e1e1e1"
    readonly property color haLightBackground: "#fafafa"
    readonly property color haLightText: "#212121"
    readonly property color fallbackOverlayBackground: Theme.colorScheme === Theme.LightOnDark
            ? page.haDarkBackground
            : page.haLightBackground
    readonly property color fallbackOverlayText: Theme.colorScheme === Theme.LightOnDark
            ? page.haDarkText
            : page.haLightText
    property string startUrl: {
        var base = hassClient.baseUrl
        if (!base || base.length === 0)
            return ""
        // No external_auth=1: Sailfish can only inject JS after load, which is too late
        // for HA's external auth module (it requires window.externalApp at import time).
        return base + "/"
    }
    property string dashboardUrl: {
        var base = hassClient.baseUrl
        if (!base || base.length === 0)
            return ""
        return base + "/lovelace"
    }
    property string loadStatusText: {
        if (!page.tokensInjected)
            return "Preparing session..."
        if (dashboardView.loading && dashboardView.loadProgress > 0)
            return "Loading dashboard… " + dashboardView.loadProgress + "%"
        if (page.readyCheckRunning)
            return "Loading dashboard…"
        return "Loading dashboard…"
    }
    backNavigation: false

    function jsString(value) {
        return JSON.stringify(value ? String(value) : "")
    }

    function isLovelaceUrl(value) {
        return String(value).indexOf("/lovelace") >= 0
    }

    function openSettings() {
        pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { hassClient: hassClient })
    }

    function resetDashboardState() {
        page.dashboardReady = false
        page.tokensInjected = false
        page.bridgeInstalled = false
        page.readyCheckRunning = false
        page.readyCheckAttempts = 0
        page.overlayBackgroundColor = page.fallbackOverlayBackground
        page.overlayTextColor = page.fallbackOverlayText
        readyCheckTimer.stop()
        page.lastLoadedBase = ""
    }

    function applyLoadingTheme(raw) {
        if (!raw || raw.length === 0)
            return
        var colors
        try {
            colors = JSON.parse(raw)
        } catch (e) {
            return
        }
        if (colors.bg)
            page.overlayBackgroundColor = colors.bg
        if (colors.fg)
            page.overlayTextColor = colors.fg
    }

    function updateLoadingThemeFromWebView() {
        var script = "return (function(){"
                + "try {"
                + "  var root=document.documentElement;"
                + "  var bg=getComputedStyle(root).getPropertyValue('--primary-background-color').trim();"
                + "  var fg=getComputedStyle(root).getPropertyValue('--primary-text-color').trim();"
                + "  if(bg&&fg)return JSON.stringify({bg:bg,fg:fg});"
                + "} catch (e) {}"
                + "try {"
                + "  var dark=window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches;"
                + "  var raw=localStorage.getItem('selectedThemeSettings')||localStorage.getItem('selectedTheme');"
                + "  if(raw){"
                + "    var s=JSON.parse(raw);"
                + "    if(s&&s.dark===true)dark=true;"
                + "    else if(s&&s.dark===false)dark=false;"
                + "  }"
                + "  if(dark)return JSON.stringify({bg:'#111111',fg:'#e1e1e1'});"
                + "} catch (e2) {}"
                + "return JSON.stringify({bg:'#fafafa',fg:'#212121'});"
                + "})();"

        dashboardView.runJavaScript(
                    script,
                    function(result) {
                        page.applyLoadingTheme(result)
                    },
                    function(error) {
                        console.log("Loading theme detection failed:", error)
                    })
    }

    function reloadDashboard() {
        page.resetDashboardState()
        dashboardView.url = page.startUrl
    }

    function finishDashboardLoad() {
        readyCheckTimer.stop()
        page.readyCheckRunning = false
        page.dashboardReady = true
        page.pollBridge()
    }

    function beginReadyCheck() {
        if (page.dashboardReady || page.readyCheckRunning)
            return
        page.updateLoadingThemeFromWebView()
        page.readyCheckRunning = true
        page.readyCheckAttempts = 0
        readyCheckTimer.start()
        page.checkDashboardReady()
    }

    function checkDashboardReady() {
        if (!page.readyCheckRunning)
            return

        var script = "return (function(){"
                + "var ha=document.querySelector('home-assistant');"
                + "if(!ha||!ha.hass||!ha.hass.connection||!ha.hass.connection.connected)return 'wait';"
                + "if(document.querySelector('ha-circular-progress'))return 'wait';"
                + "var hui=document.querySelector('hui-root');"
                + "if(!hui)return 'wait';"
                + "return 'ready';"
                + "})();"

        dashboardView.runJavaScript(
                    script,
                    function(result) {
                        if (!page.readyCheckRunning)
                            return
                        if (result === "ready") {
                            page.finishDashboardLoad()
                            return
                        }
                        page.readyCheckAttempts += 1
                        if (page.readyCheckAttempts >= 30)
                            page.finishDashboardLoad()
                    },
                    function(error) {
                        console.log("Dashboard ready check failed:", error)
                        page.readyCheckAttempts += 1
                        if (page.readyCheckAttempts >= 30)
                            page.finishDashboardLoad()
                    })
    }

    function injectSessionAndBridge(silent) {
        if (!hassClient.accessToken || hassClient.accessToken.length === 0)
            return

        var expires = hassClient.accessExpiresAtMs > 0
                ? hassClient.accessExpiresAtMs
                : (Date.now() + 1800 * 1000)
        var expiresIn = Math.max(60, Math.floor((expires - Date.now()) / 1000))

        var script = "return (function(){"
                + "var tokens={"
                + "access_token:" + page.jsString(hassClient.accessToken) + ","
                + "expires_in:" + String(expiresIn) + ","
                + "token_type:'Bearer',"
                + "hassUrl:" + page.jsString(hassClient.baseUrl) + ","
                + "clientId:" + page.jsString(hassClient.authClientId) + ","
                + "expires:" + String(expires) + ","
                + "refresh_token:" + page.jsString(hassClient.refreshToken)
                + "};"
                + "try {"
                + "  localStorage.setItem('hassTokens', JSON.stringify(tokens));"
                + "  sessionStorage.setItem('hassTokens', JSON.stringify(tokens));"
                + "} catch (e) { return 'storage-error'; }"
                + "window.__helmsmanQueue = window.__helmsmanQueue || [];"
                + "if (!window.__helmsmanBridge) {"
                + "  window.externalApp = {"
                + "    externalBus: function(message) {"
                + "      window.__helmsmanQueue.push({type:'externalBus', opts: typeof message === 'string' ? message : JSON.stringify(message || {})});"
                + "    }"
                + "  };"
                + "  window.__helmsmanBridge = true;"
                + "}"
                + "return 'ok';"
                + "})();"

        dashboardView.runJavaScript(
                    script,
                    function(result) {
                        if (result !== "ok") {
                            console.log("Token injection result:", result)
                            return
                        }
                        page.bridgeInstalled = true
                        page.updateLoadingThemeFromWebView()
                        if (!page.tokensInjected) {
                            page.tokensInjected = true
                            dashboardView.url = page.dashboardUrl
                            return
                        }
                        if (silent)
                            return
                        if (page.isLovelaceUrl(dashboardView.url))
                            page.beginReadyCheck()
                        else
                            page.pollBridge()
                    },
                    function(error) {
                        console.log("Token injection failed:", error)
                    })
    }

    function pollBridge() {
        if (!page.bridgeInstalled || !page.dashboardReady)
            return

        dashboardView.runJavaScript(
                    "return (function(){var q=window.__helmsmanQueue||[]; window.__helmsmanQueue=[]; return JSON.stringify(q);})();",
                    function(result) {
                        page.handleBridgeQueue(result)
                    },
                    function(error) {
                        console.log("Bridge poll failed:", error)
                    })
    }

    function handleBridgeQueue(raw) {
        if (!raw || raw.length === 0 || raw === "[]")
            return

        var queue
        try {
            queue = JSON.parse(raw)
        } catch (e) {
            return
        }

        for (var i = 0; i < queue.length; ++i) {
            var item = queue[i]
            if (!item || !item.type)
                continue
            if (item.type === "externalBus")
                page.handleExternalBus(item.opts)
        }
    }

    function sendExternalBusResult(id, success, resultObj) {
        var payload = {
            id: id,
            type: "result",
            success: success
        }
        if (success)
            payload.result = resultObj
        else
            payload.error = resultObj

        dashboardView.runJavaScript(
                    "window.externalBus && window.externalBus("
                    + page.jsString(JSON.stringify(payload))
                    + "); return true;")
    }

    function handleExternalBus(raw) {
        var msg
        try {
            msg = JSON.parse(raw || "{}")
        } catch (e) {
            return
        }
        if (!msg || !msg.type)
            return

        if (msg.type === "config/get") {
            page.sendExternalBusResult(msg.id, true, {
                                           hasSettingsScreen: true,
                                           appVersion: hassClient.appVersion
                                       })
            return
        }
        if (msg.type === "config_screen/show") {
            page.openSettings()
        }
    }

    WifiChecker {
        id: wifi
        onSsidChanged: hassClient.updateCurrentWifiSsid(wifi.ssid)
    }

    Connections {
        target: hassClient
        onLoggedInChanged: {
            if (!hassClient.loggedIn)
                pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
        onAccessTokenChanged: {
            if (!hassClient.loggedIn)
                return
            if (page.dashboardReady)
                page.injectSessionAndBridge(true)
            else
                page.tokensInjected = false
        }
        onBaseUrlChanged: {
            if (page.status !== PageStatus.Active || !hassClient.loggedIn)
                return
            if (page.lastLoadedBase === hassClient.baseUrl)
                return
            page.reloadDashboard()
        }
    }

    WebView {
        id: dashboardView
        anchors.fill: parent
        opacity: page.dashboardReady ? 1.0 : 0.0
        url: page.startUrl
        onLoadedChanged: {
            if (!loaded)
                return
            page.lastLoadedBase = hassClient.baseUrl
            page.injectSessionAndBridge()
        }
        onUrlChanged: {
            if (!hassClient.loggedIn)
                return
            var value = String(url)
            if (value.indexOf("/_my_redirect/companion_app") >= 0) {
                page.openSettings()
                return
            }
            if (page.tokensInjected
                    && (value.indexOf("/auth/authorize") >= 0
                        || value.indexOf("/auth/login_flow") >= 0)) {
                page.dashboardReady = false
                page.readyCheckRunning = false
                readyCheckTimer.stop()
                page.tokensInjected = false
                page.injectSessionAndBridge()
            }
        }

        Behavior on opacity {
            NumberAnimation { duration: 180 }
        }
    }

    Timer {
        id: readyCheckTimer
        interval: 250
        repeat: true
        onTriggered: page.checkDashboardReady()
    }

    Timer {
        id: bridgePollTimer
        interval: 900
        repeat: true
        running: page.status === PageStatus.Active
                 && hassClient.loggedIn
                 && page.dashboardReady
                 && page.bridgeInstalled
        onTriggered: page.pollBridge()
    }

    // Cover the WebView until Lovelace is ready so users do not see partial renders.
    Rectangle {
        anchors.fill: parent
        color: page.overlayBackgroundColor
        visible: !page.dashboardReady
        z: 2

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.horizontalPageMargin
            spacing: Theme.paddingLarge

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: true
                size: BusyIndicatorSize.Large
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: page.overlayTextColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.loadStatusText
            }
        }
    }
}
