import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    readonly property string cardType: card && card.type ? String(card.type) : "unknown"

    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: card && card.title ? card.title : root.cardType
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: root.cardType.indexOf("custom:") === 0
              ? "This custom card is not rendered natively."
              : "This card type is not rendered natively."
    }
    Button {
        text: "Open in Home Assistant"
        onClicked: {
            if (!dashboard)
                return
            dashboard.openWebPath("/lovelace")
        }
    }
}
