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
        var path = root.mediaPath()
        if (!dashboard || !path.length)
            return
        var cached = dashboard.cachedMediaUrl(path)
        if (cached && cached.length)
            root.imageUrl = cached
        else
            dashboard.prefetchMedia(path)
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
