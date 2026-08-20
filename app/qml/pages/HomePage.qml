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
    property string lastLoadedBase: ""
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
    backNavigation: false

    function jsString(value) {
        return JSON.stringify(value ? String(value) : "")
    }

    function openSettings() {
        pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { hassClient: hassClient })
    }

    function reloadDashboard() {
        page.tokensInjected = false
        page.bridgeInstalled = false
        page.lastLoadedBase = ""
        dashboardView.url = page.startUrl
    }

    function injectSessionAndBridge() {
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
                        if (!page.tokensInjected) {
                            page.tokensInjected = true
                            dashboardView.url = page.dashboardUrl
                        } else {
                            page.pollBridge()
                        }
                    },
                    function(error) {
                        console.log("Token injection failed:", error)
                    })
    }

    function pollBridge() {
        if (!page.bridgeInstalled)
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
        onAccessTokenChanged: page.tokensInjected = false
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
        url: page.startUrl
        onLoadedChanged: {
            if (!loaded)
                return
            page.lastLoadedBase = hassClient.baseUrl
            page.bridgeInstalled = false
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
            // If the frontend bounced to auth, re-inject tokens instead of wiping
            // the native session (that was clearing login across app restarts).
            if (page.tokensInjected
                    && (value.indexOf("/auth/authorize") >= 0
                        || value.indexOf("/auth/login_flow") >= 0)) {
                page.tokensInjected = false
                page.injectSessionAndBridge()
            }
        }
    }

    Timer {
        interval: 400
        repeat: true
        running: page.status === PageStatus.Active && hassClient.loggedIn && page.bridgeInstalled
        onTriggered: page.pollBridge()
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: dashboardView.loading
        visible: running
        size: BusyIndicatorSize.Large
        z: 3
    }
}
