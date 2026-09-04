import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Activity / logbook"
        color: Theme.highlightColor
    }
    Button {
        text: "Open logbook"
        onClicked: {
            if (dashboard)
                dashboard.openWebPath("/logbook")
        }
    }
}
