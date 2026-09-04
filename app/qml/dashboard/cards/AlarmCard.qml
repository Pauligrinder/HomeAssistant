import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var modes: ["disarmed", "armed_home", "armed_away", "armed_night"]

    Label {
        width: parent.width
        text: (dashboard && root.rev >= 0) ? dashboard.friendlyName(entityId) : "Alarm"
        color: Theme.highlightColor
    }
    Label {
        width: parent.width
        text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeMedium
    }
    Flow {
        width: parent.width
        spacing: Theme.paddingSmall
        Repeater {
            model: root.modes
            Button {
                text: String(modelData).replace("_", " ")
                onClicked: {
                    if (!dashboard)
                        return
                    if (modelData === "disarmed")
                        dashboard.callService("alarm_control_panel", "alarm_disarm", {}, entityId)
                    else
                        dashboard.callService("alarm_control_panel", "alarm_arm_" + String(modelData).replace("armed_", ""), {}, entityId)
                }
            }
        }
    }
}
