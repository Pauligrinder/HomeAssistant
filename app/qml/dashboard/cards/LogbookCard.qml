import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: i18n.translation("activity_logbook")
        color: Theme.highlightColor
    }
    Button {
        text: i18n.translation("open_logbook")
        onClicked: {
            if (dashboard)
                dashboard.openWebPath("/logbook")
        }
    }
}
