import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property var hassClient

    property bool routed: false

    function route() {
        if (page.routed)
            return
        page.routed = true
        if (hassClient.loggedIn) {
            pageStack.replace(Qt.resolvedUrl("HomePage.qml"), { hassClient: hassClient })
        } else {
            pageStack.replace(Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
    }

    Component.onCompleted: {
        hassClient.restoreSession()
        // If restoreSession finishes synchronously, defer routing until
        // the page stack is fully ready.
        if (!hassClient.busy)
            Qt.callLater(page.route)
    }

    Connections {
        target: hassClient
        onRestoreFinished: Qt.callLater(page.route)
        onBusyChanged: {
            if (!hassClient.busy && !page.routed)
                Qt.callLater(page.route)
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: !page.routed
        size: BusyIndicatorSize.Large
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.paddingLarge * 2
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: hassClient.statusText
    }
}
