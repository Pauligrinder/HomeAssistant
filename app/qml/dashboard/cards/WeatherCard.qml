import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var forecast: {
        var f = dashboard ? dashboard.attribute(entityId, "forecast") : []
        return f || []
    }

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId, "Weather") : "Weather"
        color: Theme.highlightColor
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeLarge
    }
    Label {
        width: parent.width
        text: {
            var t = dashboard ? dashboard.attribute(entityId, "temperature") : ""
            var u = dashboard ? dashboard.attribute(entityId, "temperature_unit") : ""
            return t ? (String(t) + (u ? (" " + u) : "°")) : ""
        }
        color: Theme.secondaryColor
    }
    Repeater {
        model: root.forecast
        Label {
            width: parent.width
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: {
                var d = modelData.datetime || modelData.day || ""
                var cond = modelData.condition || ""
                var t = modelData.temperature !== undefined ? modelData.temperature : ""
                return String(d) + "  " + String(cond) + "  " + String(t)
            }
        }
    }
}
