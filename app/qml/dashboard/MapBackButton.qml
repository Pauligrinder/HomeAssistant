import QtQuick 2.6
import Sailfish.Silica 1.0

// Mimics Silica's page-stack back dots so maps can disable backNavigation
// (needed so MapLibre's horizontal pan isn't stolen by the page flick).
Item {
    id: root
    width: Theme.itemSizeLarge
    height: Theme.itemSizeLarge
    signal clicked()

    // Soft backdrop so the dots stay readable on bright map tiles.
    Rectangle {
        width: Theme.itemSizeLarge * 0.95
        height: Theme.itemSizeLarge * 0.82
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: -Math.round(width * 0.60)
        color: "#000000"
        opacity: root.pressed ? 0.36 : 0.22
    }

    Rectangle {
        width: Theme.itemSizeSmall * 0.95
        height: Theme.itemSizeSmall * 0.95
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: -Math.round(width * 0.40)
        color: "#000000"
        opacity: root.pressed ? 0.48 : 0.32
    }

    property bool pressed: mouse.pressed

    Column {
        id: dots
        anchors.verticalCenter: parent.verticalCenter
        // Match the native stack indicator position near the left edge.
        anchors.left: parent.left
        anchors.leftMargin: Theme.paddingMedium
        spacing: Math.max(3, Math.round(Theme.paddingSmall * 0.55))

        Repeater {
            model: 3
            Rectangle {
                width: Math.max(4, Math.round(Theme.paddingSmall * 0.7))
                height: width
                radius: width / 2
                color: "#FFFFFF"
                opacity: root.pressed ? 1.0 : 0.9
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
