import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root
    property var prompt: ({})
    readonly property bool active: !!(prompt && prompt.active)

    signal accepted()
    signal rejected()

    visible: root.active
    enabled: root.active
    z: 1000

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightDimmerColor, 0.8)

        MouseArea {
            anchors.fill: parent
            enabled: root.active
            onClicked: { }
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: content.height + 2 * Theme.paddingLarge
        radius: Theme.paddingMedium
        color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)

        Column {
            id: content
            width: parent.width - 2 * Theme.horizontalPageMargin
            x: Theme.horizontalPageMargin
            y: Theme.paddingLarge
            spacing: Theme.paddingMedium

            Label {
                width: parent.width
                text: "Helmsman"
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                font.bold: true
            }

            Label {
                width: parent.width
                text: root.prompt && root.prompt.title ? String(root.prompt.title) : ""
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            Label {
                width: parent.width
                visible: !!(root.prompt && root.prompt.text && String(root.prompt.text).length)
                text: root.prompt && root.prompt.text ? String(root.prompt.text) : ""
                wrapMode: Text.Wrap
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                width: parent.width
                spacing: Theme.paddingMedium

                Button {
                    width: (parent.width - parent.spacing) / 2
                    text: (root.prompt && root.prompt.dismissText)
                          ? String(root.prompt.dismissText) : "Deny"
                    onClicked: root.rejected()
                }

                Button {
                    width: (parent.width - parent.spacing) / 2
                    text: (root.prompt && root.prompt.confirmText)
                          ? String(root.prompt.confirmText) : "Allow"
                    onClicked: root.accepted()
                }
            }
        }
    }
}
