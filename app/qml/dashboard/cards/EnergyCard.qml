import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: true

    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: i18n.translation("energy_dashboard")
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeMedium
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: i18n.translation("energy_cards_help")
    }

    function defaultTap() {
        if (dashboard)
            dashboard.openWebPath("/energy")
    }

    Component.onCompleted: tapHandler = defaultTap
}
