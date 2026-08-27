import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root
    property var entities: []
    property string statusText: ""
    signal toggleRequested(string entityId)
    signal brightnessRequested(string entityId, int pct)

    width: parent ? parent.width : Screen.width
    implicitWidth: width
    implicitHeight: visible ? column.height : 0
    height: implicitHeight
    visible: (entities && entities.length > 0) || statusText.length > 0

    Column {
        id: column
        width: parent.width

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            text: "Helmsman"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeMedium
            font.family: Theme.fontFamilyHeading
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: root.statusText.length > 0 && (!root.entities || root.entities.length === 0)
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            text: root.statusText
        }

        Repeater {
            model: root.entities || []
            delegate: Column {
                id: lightColumn
                width: column.width
                property bool dimmable: modelData.dimmable === true
                property bool available: modelData.available !== false

                TextSwitch {
                    width: parent.width
                    text: modelData.name || modelData.entityId
                    description: lightColumn.available
                                 ? (modelData.on ? "On" : "Off")
                                 : (modelData.state || "unavailable")
                    checked: modelData.on === true
                    automaticCheck: false
                    enabled: lightColumn.available
                    onClicked: root.toggleRequested(modelData.entityId)
                }

                Slider {
                    id: dimmer
                    width: parent.width
                    visible: lightColumn.dimmable
                    enabled: lightColumn.available
                    minimumValue: 0
                    maximumValue: 100
                    stepSize: 1
                    valueText: Math.round(value) + "%"
                    label: "Brightness"
                    Binding {
                        target: dimmer
                        property: "value"
                        value: Number(modelData.brightnessPct) || 0
                        when: !dimmer.down
                    }
                    onDownChanged: {
                        if (!down)
                            root.brightnessRequested(modelData.entityId, Math.round(value))
                    }
                }
            }
        }
    }
}
