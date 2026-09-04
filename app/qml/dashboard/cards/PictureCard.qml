import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    property string imageUrl: ""

    function mediaPath() {
        if (card && card.image)
            return String(card.image)
        return ""
    }

    Connections {
        target: dashboard
        onMediaCached: {
            if (path === root.mediaPath())
                root.imageUrl = fileUrl
        }
    }

    Component.onCompleted: {
        if (dashboard && root.mediaPath().length)
            dashboard.prefetchMedia(root.mediaPath())
        else if (card && card.image && String(card.image).indexOf("http") === 0)
            root.imageUrl = card.image
    }

    Image {
        width: parent.width
        height: Math.max(Theme.itemSizeExtraLarge, width * 0.45)
        fillMode: Image.PreserveAspectCrop
        source: root.imageUrl
        Label {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: Theme.paddingSmall
            text: card && card.title ? card.title : ""
            color: "white"
            visible: text.length > 0
        }
    }
}
