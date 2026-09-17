import QtQuick 2.6
import Sailfish.Silica 1.0

// Sits under NativeHomePage so a non-default dashboard can use the real
// Silica back swipe. This page is never the interactive home screen.
Page {
    id: page
    objectName: "HomeAnchor"
    property var hassClient
    property var mdiIcons
    backNavigation: false
    showNavigationIndicator: false

    function showHome() {
        if (page.status !== PageStatus.Active || pageStack.busy)
            return
        if (pageStack.currentPage !== page)
            return
        if (hassClient && hassClient.lovelace)
            hassClient.lovelace.setCurrentUrlPath(hassClient.lovelace.defaultUrlPath || "")
        pageStack.push(Qt.resolvedUrl("NativeHomePage.qml"), {
                           hassClient: hassClient,
                           mdiIcons: mdiIcons
                       }, PageStackAction.Immediate)
    }

    onStatusChanged: {
        if (status === PageStatus.Active)
            page.showHome()
    }

    Connections {
        target: pageStack
        onBusyChanged: {
            if (!pageStack.busy)
                page.showHome()
        }
    }
}
