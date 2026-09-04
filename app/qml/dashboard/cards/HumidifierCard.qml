import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property double humidity: {
        var h = dashboard ? dashboard.attribute(entityId, "humidity") : 0
        return h ? Number(h) : 0
    }

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId) : entityId
        color: Theme.highlightColor
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeLarge
    }
    Row {
        spacing: Theme.paddingMedium
        Button {
            text: "−"
            onClicked: dashboard.callService("humidifier", "set_humidity",
                                             { "humidity": root.humidity - 1 }, entityId)
        }
        Button {
            text: "+"
            onClicked: dashboard.callService("humidifier", "set_humidity",
                                             { "humidity": root.humidity + 1 }, entityId)
        }
    }
}
