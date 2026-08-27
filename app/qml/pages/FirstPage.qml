import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    objectName: "SplashPage"
    property var hassClient
    property bool decided: false
    property bool restoreFailed: false
    property bool restoreCancelled: false

    backNavigation: false

    readonly property bool showSettings: !page.decided
            && (page.restoreFailed
                || hassClient.errorMessage.length > 0
                || page.restoreCancelled)

    function finish(loggedIn) {
        if (page.decided)
            return
        page.decided = true
        if (loggedIn) {
            pageStack.replaceAbove(null, Qt.resolvedUrl("HomePage.qml"),
                                   { hassClient: hassClient })
        } else {
            pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"),
                                   { hassClient: hassClient })
        }
    }

    function startRestore() {
        page.restoreFailed = false
        page.restoreCancelled = false
        hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
        hassClient.restoreSession()
    }

    function openSettings() {
        hassClient.cancelRestore()
        page.restoreCancelled = true
        page.restoreFailed = true
        pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { hassClient: hassClient })
    }

    WifiChecker {
        id: wifi
        onNetworkChanged: hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
    }

    // Wait so ConnMan can report the SSID before we pick internal/external.
    // Too short and restore hits external HTTPS while still on the LAN.
    // Always wait at least one frame so the splash can paint first.
    Timer {
        id: startRestoreTimer
        interval: hassClient.internalUrl.length > 0 ? 1500 : 50
        running: true
        repeat: false
        onTriggered: page.startRestore()
    }

    Connections {
        target: hassClient
        onRestoreFinished: {
            if (loggedIn)
                page.finish(true)
            else
                page.restoreFailed = true
        }
        onLoginFailed: page.restoreFailed = true
        onLoggedInChanged: {
            if (hassClient.loggedIn)
                page.finish(true)
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingLarge

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Helmsman"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraLarge
        }

        BusyIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            running: !page.decided && !page.restoreFailed
            size: BusyIndicatorSize.Large
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
            text: {
                if (page.restoreFailed || hassClient.errorMessage.length > 0)
                    return hassClient.statusText.length > 0
                            ? hassClient.statusText
                            : "Connection failed"
                if (hassClient.restoringSession || hassClient.statusText.indexOf("Restoring") === 0)
                    return "Restoring session..."
                if (hassClient.statusText.length > 0)
                    return hassClient.statusText
                return "Starting..."
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
            visible: hassClient.errorMessage.length > 0
            text: hassClient.errorMessage
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.showSettings
            text: "Settings"
            onClicked: page.openSettings()
        }

        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.restoreFailed && !page.decided
            text: "Retry"
            onClicked: page.startRestore()
        }
    }
}
