import QtQuick 2.6
import Sailfish.Silica 1.0

// HACS button-card color_type: blank-card / label-card spacer (or label text).
Item {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    property int minContentHeight: 0
    width: parent ? parent.width : Screen.width
    height: Math.max(fillHeight, minContentHeight,
                     (card && card.color_type === "label-card"
                      && card.name) ? Theme.itemSizeSmall : Theme.paddingLarge)

    Label {
        anchors.centerIn: parent
        width: parent.width
        visible: !!(card && card.color_type === "label-card" && card.name)
        text: card && card.name ? String(card.name) : ""
        color: Theme.secondaryColor
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeExtraSmall
        wrapMode: Text.Wrap
    }
}
