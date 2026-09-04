import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: true

    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Energy dashboard"
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeMedium
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: "Energy cards stay in the Home Assistant frontend. Tap to open."
    }

    function defaultTap() {
        if (dashboard)
            dashboard.openWebPath("/energy")
    }

    MouseArea {
        anchors.fill: parent
        z: 1
        onClicked: root.defaultTap()
    }
}
