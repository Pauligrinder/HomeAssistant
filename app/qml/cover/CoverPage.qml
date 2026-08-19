import QtQuick 2.6
import Sailfish.Silica 1.0

CoverBackground {
    id: cover
    property var hassClient

    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.paddingLarge * 2
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            truncationMode: TruncationMode.Fade
            text: hassClient && hassClient.instanceName.length > 0
                  ? hassClient.instanceName
                  : "Home Assistant"
            font.pixelSize: Theme.fontSizeLarge
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            text: {
                if (!hassClient)
                    return ""
                if (hassClient.loggedIn)
                    return "Signed in"
                if (hassClient.connected)
                    return "Connected"
                return "Not connected"
            }
        }
    }
}
