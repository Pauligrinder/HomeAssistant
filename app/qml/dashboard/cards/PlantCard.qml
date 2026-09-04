import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId, "Plant") : "Plant"
        color: Theme.highlightColor
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeMedium
    }
    Repeater {
        model: ["moisture", "temperature", "brightness", "conductivity"]
        Label {
            visible: dashboard && dashboard.attribute(entityId, modelData) !== undefined
            width: parent.width
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: modelData + ": " + String(dashboard.attribute(entityId, modelData))
        }
    }
}
