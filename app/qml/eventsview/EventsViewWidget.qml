import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root
    property var entities: []
    property string statusText: ""

    width: parent ? parent.width : Screen.width
    implicitWidth: width
    implicitHeight: visible ? column.height : 0
    height: implicitHeight
    visible: (entities && entities.length > 0) || statusText.length > 0

    function stateLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        if (entity.dimmable === true && entity.on === true)
            return "On · " + Math.round(Number(entity.brightnessPct) || 0) + "%"
        return entity.on === true ? "On" : "Off"
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingSmall

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
                x: Theme.horizontalPageMargin
                width: column.width - 2 * x

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: modelData.on === true
                    text: modelData.name || modelData.entityId
                }

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    text: root.stateLabel(modelData)
                }
            }
        }
    }
}
