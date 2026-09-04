import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Column {
        width: parent.width
        spacing: Theme.paddingSmall

        MdiIcon {
            x: (parent.width - width) / 2
            mdiIcons: root.mdiIcons
            name: (card && card.icon) ? card.icon
                  : ((dashboard && root.rev >= 0) ? dashboard.entityIcon(root.entityId) : "mdi:gesture-tap-button")
            iconColor: Theme.highlightColor
            width: Theme.iconSizeLarge
            height: width
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: (card && card.name) ? card.name
                  : (card && card.show_name === false ? ""
                     : ((dashboard && root.rev >= 0) ? dashboard.friendlyName(root.entityId, "Button") : "Button"))
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
