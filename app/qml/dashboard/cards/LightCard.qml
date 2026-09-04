import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property bool on: dashboard && entityId.length ? dashboard.isOn(entityId) : false
    readonly property int brightness: {
        var b = dashboard ? Number(dashboard.attribute(entityId, "brightness")) : 0
        if (!b) return 0
        return Math.round(b * 100 / 255)
    }

    Row {
        width: parent.width
        spacing: Theme.paddingMedium
        MdiIcon {
            mdiIcons: root.mdiIcons
            name: dashboard ? dashboard.entityIcon(entityId) : "mdi:lightbulb"
            iconColor: root.on ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium
            text: dashboard ? dashboard.friendlyName(entityId) : entityId
            truncationMode: TruncationMode.Fade
        }
    }
    Slider {
        width: parent.width
        visible: root.on
        minimumValue: 0
        maximumValue: 100
        stepSize: 1
        value: root.brightness
        label: "Brightness"
        onReleased: {
            if (dashboard)
                dashboard.callService("light", "turn_on",
                                      { "brightness_pct": Math.round(value) }, entityId)
        }
    }
}
