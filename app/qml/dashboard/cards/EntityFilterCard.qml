import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var entities: dashboard ? dashboard.filterEntities(card || {}) : []

    Label {
        width: parent.width
        visible: card && card.title
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
    }
    Repeater {
        model: root.entities
        BackgroundItem {
            width: parent.width
            height: Theme.itemSizeSmall
            onClicked: dashboard.openMoreInfo(String(modelData))
            Label {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: dashboard ? dashboard.friendlyName(String(modelData)) : String(modelData)
                truncationMode: TruncationMode.Fade
                width: parent.width * 0.6
            }
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: dashboard ? dashboard.formatState(String(modelData)) : ""
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }
    }
}
