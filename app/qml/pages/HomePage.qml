import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0

Page {
    id: page
    property var hassClient
    property bool sessionInjected: false
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

    function injectSessionTokens() {
        if (page.sessionInjected || !hassClient.accessToken || hassClient.accessToken.length === 0)
            return

        var expires = hassClient.accessExpiresAtMs > 0
                ? hassClient.accessExpiresAtMs
                : (Date.now() + 1800 * 1000)
        var expiresIn = Math.max(0, Math.floor((expires - Date.now()) / 1000))

        var script = "(function(){"
                + "var tokens={"
                + "access_token:" + page.jsString(hassClient.accessToken) + ","
                + "expires_in:" + String(expiresIn) + ","
                + "token_type:'Bearer',"
                + "hassUrl:" + page.jsString(hassClient.baseUrl) + ","
                + "clientId:" + page.jsString(hassClient.baseUrl + "/") + ","
                + "expires:" + String(expires) + ","
                + "refresh_token:" + page.jsString(hassClient.refreshToken) + ","
                + "};"
                + "localStorage.setItem('hassTokens', JSON.stringify(tokens));"
                + "sessionStorage.setItem('hassTokens', JSON.stringify(tokens));"
                + "return 'ok';"
                + "})();"
        dashboardView.runJavaScript(
                    script,
                    function(result) {
                        if (result === "ok") {
                            page.sessionInjected = true
                            dashboardView.url = page.dashboardUrl
                        }
                    },
                    function(error) {
                        console.log("Token injection failed:", error)
                    })
    }

    Connections {
        target: hassClient
        onLoggedInChanged: {
            if (!hassClient.loggedIn)
                pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
        onAccessTokenChanged: page.sessionInjected = false
    }

    PageHeader {
        id: header
        title: hassClient.instanceName.length > 0 ? hassClient.instanceName : "Home Assistant"
    }

    Button {
        id: signOutButton
        anchors.top: header.bottom
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        text: "Sign out"
        onClicked: hassClient.logout()
        z: 2
    }

    WebView {
        id: dashboardView
        anchors.top: signOutButton.bottom
        anchors.topMargin: Theme.paddingMedium
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        url: hassClient.baseUrl
        onLoadedChanged: {
            if (loaded)
                page.injectSessionTokens()
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: dashboardView.loading
        visible: running
        size: BusyIndicatorSize.Large
        z: 3
    }
}
