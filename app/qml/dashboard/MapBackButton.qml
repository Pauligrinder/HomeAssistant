import QtQuick 2.6
import Sailfish.Silica 1.0

// Explicit back control for interactive maps (backNavigation off so MapLibre
// can pan horizontally without fighting the page flick).
Item {
    id: root
    width: pill.width + Theme.paddingMedium
    height: Theme.itemSizeMedium
    signal clicked()

    property bool pressed: mouse.pressed

    Rectangle {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Theme.paddingMedium
        width: Theme.itemSizeSmall + Theme.paddingMedium
        height: Theme.itemSizeSmall
        radius: height / 2
        color: "#000000"
        opacity: root.pressed ? 0.72 : 0.55

        Image {
            anchors.centerIn: parent
            source: "image://theme/icon-m-back?" + (root.pressed
                                                    ? Theme.highlightColor
                                                    : "#FFFFFF")
            sourceSize.width: Theme.iconSizeSmall
            sourceSize.height: Theme.iconSizeSmall
            opacity: 0.95
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
