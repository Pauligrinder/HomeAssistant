import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

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
            text: (dashboard && root.rev >= 0) ? dashboard.formatState(root.entityId) : ""
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeLarge
            truncationMode: TruncationMode.Fade
        }
    }
}
