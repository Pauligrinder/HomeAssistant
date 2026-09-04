import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property double value: {
        var s = (dashboard && root.rev >= 0) ? dashboard.entityState(entityId) : "0"
        return Number(s)
    }
    readonly property double minValue: card && card.min !== undefined ? Number(card.min) : 0
    readonly property double maxValue: card && card.max !== undefined ? Number(card.max) : 100

    Label {
        width: parent.width
        text: (dashboard && root.rev >= 0) ? dashboard.friendlyName(entityId) : entityId
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }

    Item {
        width: parent.width
        height: Theme.itemSizeSmall
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Theme.paddingSmall
            color: Theme.rgba(Theme.secondaryColor, 0.3)
            radius: height / 2
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * Math.max(0, Math.min(1,
                   (root.value - root.minValue) / Math.max(1, root.maxValue - root.minValue)))
            height: Theme.paddingMedium
            color: Theme.highlightColor
            radius: height / 2
        }
    }

    Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeMedium
    }
}
