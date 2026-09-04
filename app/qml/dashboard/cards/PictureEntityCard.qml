import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    property string imageUrl: ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    function mediaPath() {
        if (dashboard && entityId.length && dashboard.domainOf(entityId) === "camera")
            return dashboard.cameraPath(entityId)
        var pic = dashboard ? dashboard.attribute(entityId, "entity_picture") : ""
        if (pic)
            return String(pic)
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
        onEntityChanged: {
            if (entityId === root.entityId)
                root.refresh()
        }
    }

    function refresh() {
        var p = root.mediaPath()
        if (dashboard && p.length)
            dashboard.prefetchMedia(p)
    }

    Component.onCompleted: root.refresh()

    Image {
        width: parent.width
        height: Math.max(Theme.itemSizeExtraLarge, width * 0.5)
        fillMode: Image.PreserveAspectCrop
        source: root.imageUrl
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId) : entityId
        truncationMode: TruncationMode.Fade
    }
    Label {
        width: parent.width
        visible: !card || card.show_state !== false
        text: dashboard ? dashboard.formatState(entityId) : ""
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }
}
