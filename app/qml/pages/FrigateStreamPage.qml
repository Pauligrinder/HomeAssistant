import QtQuick 2.6
import Sailfish.Silica 1.0
import "../dashboard/cards"

Page {
    id: page
    property var hassClient
    property var dashboard
    property string entityId: ""
    property string titleText: ""
    property var sourcePlayer

    allowedOrientations: Orientation.Landscape | Orientation.LandscapeInverted
    backNavigation: false

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Loader {
        anchors.fill: parent
        active: page.status === PageStatus.Active
                && !page.orientationTransitionRunning
                && page.width > Theme.itemSizeLarge
                && page.height > Theme.itemSizeLarge
                && Qt.application.state === Qt.ApplicationActive
        sourceComponent: FrigateGo2rtcStream {
            dashboard: page.dashboard
            hassClient: page.hassClient
            entityId: page.entityId
            cameraTitle: page.titleText
            active: page.status === PageStatus.Active
                    && !page.orientationTransitionRunning
                    && Qt.application.state === Qt.ApplicationActive
            allowFullscreen: false
        }
    }

    Label {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: Theme.paddingLarge
        anchors.topMargin: Theme.paddingLarge
        width: Math.min(implicitWidth, page.width - closeButton.width - 4 * Theme.paddingLarge)
        text: page.titleText
        color: "white"
        font.pixelSize: Theme.fontSizeSmall
        truncationMode: TruncationMode.Fade
        z: 5
    }

    IconButton {
        id: closeButton
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.paddingSmall
        icon.source: "image://theme/icon-m-close"
        onClicked: pageStack.pop()
        z: 5
    }

    Component.onDestruction: {
        if (page.sourcePlayer)
            page.sourcePlayer.finishFullscreen()
    }
}
