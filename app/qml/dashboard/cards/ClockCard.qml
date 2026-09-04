import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clockLabel.text = Qt.formatTime(new Date(), "hh:mm")
    }

    Label {
        id: clockLabel
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeExtraLarge
        color: Theme.primaryColor
        text: Qt.formatTime(new Date(), "hh:mm")
    }
    Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondaryColor
        text: Qt.formatDate(new Date(), Qt.DefaultLocaleLongDate)
    }
}
