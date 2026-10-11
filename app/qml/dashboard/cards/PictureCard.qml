import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    property string imageUrl: ""
    contentTopMargin: 0
    contentBottomMargin: 0
    contentHorizontalMargin: 0
    readonly property bool lightAmbience: Theme.colorScheme === Theme.DarkOnLight

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
        width: root.width
        height: {
            if (picture.aspectRatio > 0)
                return width / picture.aspectRatio
            if (root.fillHeight > 0)
                return root.fillHeight
            return Math.max(Theme.itemSizeExtraLarge, width * 9 / 16)
        }

        RoundedImage {
            id: picture
            anchors.fill: parent
            source: root.imageUrl
            // CardChrome clips; skip Canvas corner paint on large pictures.
            cornerRadius: 0
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.round(Math.max(width, Screen.width / 2)
                                         * Theme.pixelRatio)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: titleLabel.height + 2 * Theme.paddingSmall
            visible: titleLabel.visible
            radius: root.radius
            color: root.lightAmbience ? "#FFFFFF" : "#000000"
            opacity: 0.55

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: parent.radius
                color: parent.color
            }
        }

        Label {
            id: titleLabel
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.paddingSmall
            text: {
                if (!card)
                    return ""
                if (card._helmsman_card_title && String(card._helmsman_card_title).length)
                    return String(card._helmsman_card_title)
                return card.title ? String(card.title) : ""
            }
            color: root.lightAmbience ? "#111111" : "#FFFFFF"
            visible: text.length > 0
            truncationMode: TruncationMode.Fade
            z: 2
        }
    }
}
