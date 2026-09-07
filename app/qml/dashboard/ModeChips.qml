import QtQuick 2.6
import Sailfish.Silica 1.0

// A row of mode pills in the style of the events view controls: the active
// mode is a bright pill, the rest are faint. Long lists wrap.
Column {
    id: chips
    property string title: ""
    property var modes: []
    property string current: ""
    property int columns: 4
    signal picked(string mode)

    width: parent ? parent.width : 0
    spacing: Theme.paddingSmall
    visible: !!(modes && modes.length)

    function label(mode) {
        var text = String(mode).replace(/_/g, " ")
        return text.charAt(0).toUpperCase() + text.slice(1)
    }

    Label {
        width: parent.width
        visible: chips.title.length > 0
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: chips.title
    }

    Flow {
        id: flow
        width: parent.width
        spacing: Theme.paddingSmall

        Repeater {
            model: chips.modes
            Rectangle {
                readonly property bool active: String(modelData) === chips.current
                width: {
                    var perRow = Math.min(chips.columns,
                                          Math.max(1, chips.modes ? chips.modes.length : 1))
                    return (flow.width - (perRow - 1) * flow.spacing) / perRow
                }
                height: Theme.itemSizeExtraSmall
                radius: Theme.paddingSmall
                color: active ? "#73FFFFFF" : "#28FFFFFF"

                Label {
                    anchors.fill: parent
                    anchors.margins: Theme.paddingSmall / 2
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    font.bold: parent.active
                    truncationMode: TruncationMode.Fade
                    text: chips.label(modelData)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: chips.picked(String(modelData))
                }
            }
        }
    }
}
