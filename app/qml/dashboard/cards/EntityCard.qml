import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property bool isScript: root.entityId.indexOf("script.") === 0

    Column {
        width: parent.width
        spacing: Theme.paddingSmall / 2

        Label {
            width: parent.width
            text: (card && card.name) ? card.name
                  : ((dashboard && root.rev >= 0) ? dashboard.friendlyName(root.entityId) : root.entityId)
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            visible: !root.isScript
            text: (dashboard && root.rev >= 0) ? dashboard.formatState(root.entityId) : ""
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeLarge
            truncationMode: TruncationMode.Fade
        }
        Button {
            visible: root.isScript
            preferredWidth: Theme.buttonWidthExtraSmall
            height: Theme.itemSizeExtraSmall
            text: qsTr("Run")
            onClicked: {
                if (!dashboard || !root.entityId.length)
                    return
                var confirm = card && card.confirmation
                if (confirm === undefined && card && card.tap_action)
                    confirm = card.tap_action.confirmation
                dashboard.performAction(root.mergeConfirmation({ "action": "toggle" }, confirm),
                                       root.entityId)
            }
        }
    }
}
