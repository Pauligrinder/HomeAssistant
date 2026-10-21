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
              ? i18n.translation("custom_component_unsupported")
              : i18n.translation("card_type_unsupported")
    }
    Button {
        text: i18n.translation("open_in_home_assistant")
        onClicked: {
            if (!dashboard)
                return
            dashboard.openWebPath("/lovelace")
        }
    }
}
