import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    property string imageUrl: ""
    contentTopMargin: 0
    contentBottomMargin: 0

    function mediaPath() {
        return dashboard ? dashboard.mediaPathOf(card ? card.image : "") : ""
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

    Item {
        x: -Theme.paddingMedium
        width: root.width
        height: Math.max(Theme.itemSizeExtraLarge, width * 0.45)

        RoundedImage {
            anchors.fill: parent
            source: root.imageUrl
            cornerRadius: root.radius
        }

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
