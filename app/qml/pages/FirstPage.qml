import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    objectName: "SplashPage"
    property var hassClient
    property bool decided: false

    backNavigation: false

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
        // Apply http/https endpoint from Wi‑Fi before token refresh.
        hassClient.updateCurrentWifiSsid(wifi.ssid)
        hassClient.restoreSession()
    }

    WifiChecker {
        id: wifi
    }

    // Wait briefly so ConnMan can report the SSID before we pick internal/external.
    Timer {
        id: startRestoreTimer
        interval: 700
        running: true
        repeat: false
        onTriggered: page.startRestore()
    }

    // Don't leave the user on the splash forever if restore hangs.
    Timer {
        interval: 20000
        running: true
        repeat: false
        onTriggered: {
            if (!page.decided)
                page.finish(hassClient.loggedIn)
        }
    }

    Connections {
        target: hassClient
        onRestoreFinished: page.finish(loggedIn)
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
            running: !page.decided
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
                if (hassClient.restoringSession || hassClient.statusText.indexOf("Restoring") === 0)
                    return "Restoring session..."
                if (hassClient.statusText.length > 0)
                    return hassClient.statusText
                return "Starting..."
            }
        }
    }
}
