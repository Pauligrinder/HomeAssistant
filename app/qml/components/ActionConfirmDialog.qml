import QtQuick 2.6
import Sailfish.Silica 1.0

Dialog {
    id: dialog
    property var prompt: ({})
    readonly property string confirmText: (prompt && prompt.confirmText)
                                          ? String(prompt.confirmText) : "Allow"
    readonly property string dismissText: (prompt && prompt.dismissText)
                                          ? String(prompt.dismissText) : "Deny"

    DialogHeader {
        acceptText: dialog.confirmText
        cancelText: dialog.dismissText
        _glassOnly: true
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round((parent.height - height) / 2.0)
        width: parent.width
        spacing: Theme.paddingMedium

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamilyHeading
            font.pixelSize: Theme.fontSizeExtraLarge
            color: Theme.highlightColor
            opacity: Theme.opacityHigh
            text: dialog.prompt && dialog.prompt.title ? String(dialog.prompt.title) : ""
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: !!(dialog.prompt && dialog.prompt.text && String(dialog.prompt.text).length)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.highlightColor
            opacity: Theme.opacityHigh
            text: dialog.prompt && dialog.prompt.text ? String(dialog.prompt.text) : ""
        }
    }
}
