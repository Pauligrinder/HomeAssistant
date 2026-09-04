import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    property string artUrl: ""
    property string requestedArtPath: ""

    Connections {
        target: dashboard
        onMediaCached: {
            if (path === root.artPath())
                root.artUrl = fileUrl
        }
        onStatesRevisionChanged: root.prefetchArt()
    }

    function artPath() {
        var pic = dashboard ? dashboard.attribute(entityId, "entity_picture") : ""
        return pic ? String(pic) : ""
    }

    function prefetchArt() {
        var p = root.artPath()
        if (!dashboard || !p.length)
            return
        var cached = dashboard.cachedMediaUrl(p)
        if (cached && cached.length)
            root.artUrl = cached
        else if (p !== root.requestedArtPath) {
            root.requestedArtPath = p
            dashboard.prefetchMedia(p)
        }
    }

    Component.onCompleted: root.prefetchArt()

    Image {
        width: parent.width
        height: width * 0.56
        fillMode: Image.PreserveAspectCrop
        source: root.artUrl
        visible: root.artUrl.length > 0
    }
    Label {
        width: parent.width
        text: {
            if (!dashboard || root.rev < 0)
                return entityId
            var title = dashboard.attribute(entityId, "media_title")
            if (title)
                return String(title)
            return dashboard.friendlyName(entityId)
        }
        truncationMode: TruncationMode.Fade
        color: Theme.primaryColor
    }
    Label {
        width: parent.width
        text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }
    Row {
        spacing: Theme.paddingMedium
        Button {
            text: "Prev"
            onClicked: dashboard.callService("media_player", "media_previous_track", {}, entityId)
        }
        Button {
            text: (dashboard && root.rev >= 0 && dashboard.entityState(entityId) === "playing")
                  ? "Pause" : "Play"
            onClicked: dashboard.callService("media_player", "media_play_pause", {}, entityId)
        }
        Button {
            text: "Next"
            onClicked: dashboard.callService("media_player", "media_next_track", {}, entityId)
        }
    }
}
