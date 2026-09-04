import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    showBackground: false
    tapEnabled: true

    Row {
        width: parent.width
        spacing: Theme.paddingMedium

        MdiIcon {
            visible: card && card.icon && String(card.icon).length > 0
            mdiIcons: root.mdiIcons
            name: card && card.icon ? card.icon : ""
            iconColor: Theme.highlightColor
            width: Theme.iconSizeSmall
        }

        Label {
            width: parent.width - (card && card.icon ? Theme.iconSizeSmall + Theme.paddingMedium : 0)
            text: (card && (card.heading || card.title)) ? (card.heading || card.title) : ""
            color: Theme.highlightColor
            font.pixelSize: (card && card.heading_style === "subtitle")
                            ? Theme.fontSizeSmall : Theme.fontSizeMedium
            font.bold: true
            wrapMode: Text.Wrap
        }
    }
}
