import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property double temp: {
        var t = dashboard ? dashboard.attribute(entityId, "temperature") : 0
        return t ? Number(t) : 0
    }
    readonly property string mode: dashboard ? dashboard.entityState(entityId) : ""

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId) : entityId
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeLarge
        color: Theme.primaryColor
    }
    Row {
        spacing: Theme.paddingMedium
        Button {
            text: "−"
            enabled: dashboard && entityId.length
            onClicked: dashboard.callService("climate", "set_temperature",
                                             { "temperature": root.temp - 0.5 }, entityId)
        }
        Button {
            text: "+"
            enabled: dashboard && entityId.length
            onClicked: dashboard.callService("climate", "set_temperature",
                                             { "temperature": root.temp + 0.5 }, entityId)
        }
    }
    Flow {
        width: parent.width
        spacing: Theme.paddingSmall
        Repeater {
            model: dashboard ? dashboard.attribute(entityId, "hvac_modes") : []
            Button {
                text: String(modelData)
                color: String(modelData) === root.mode ? Theme.highlightColor : Theme.primaryColor
                onClicked: dashboard.callService("climate", "set_hvac_mode",
                                                 { "hvac_mode": String(modelData) }, entityId)
            }
        }
    }
}
