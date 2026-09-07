import QtQuick 2.6
import QtGraphicalEffects 1.0
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    property string imageUrl: ""
    property string requestedPath: ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    contentTopMargin: 0
    contentBottomMargin: 0

    function mediaPath() {
        if (!dashboard)
            return ""
        if (entityId.length && dashboard.domainOf(entityId) === "camera")
            return dashboard.cameraPath(entityId)
        var pic = dashboard.mediaPathOf(dashboard.attribute(entityId, "entity_picture"))
        if (pic.length)
            return pic
        return dashboard.mediaPathOf(card ? card.image : "")
    }

    // Home Assistant tints the picture per state with CSS filter functions,
    // e.g. "brightness(1) saturate(2) hue-rotate(90deg)".
    readonly property string stateFilter: {
        if (!card || !card.state_filter || !dashboard || root.rev < 0)
            return ""
        var value = card.state_filter[dashboard.entityState(entityId)]
        return value ? String(value) : ""
    }

    function cssAmount(filter, name, fallback) {
        var match = new RegExp(name + "\\(\\s*([-+0-9.]+)\\s*(deg|%)?\\s*\\)").exec(filter)
        if (!match)
            return fallback
        var value = parseFloat(match[1])
        if (isNaN(value))
            return fallback
        return match[2] === "%" ? value / 100 : value
    }

    // A full hue turn is 1.0 for HueSaturation, and its saturation and
    // lightness are offsets around 0 rather than CSS multipliers.
    readonly property real filterHue: (root.cssAmount(root.stateFilter, "hue-rotate", 0) % 360) / 360
    readonly property real filterSaturation: Math.max(-1, Math.min(1,
            root.cssAmount(root.stateFilter, "saturate", 1) - 1
            - root.cssAmount(root.stateFilter, "grayscale", 0)))
    readonly property real filterLightness: Math.max(-1, Math.min(1,
            root.cssAmount(root.stateFilter, "brightness", 1) - 1))
    readonly property real filterOpacity: Math.max(0, Math.min(1,
            root.cssAmount(root.stateFilter, "opacity", 1)))

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
        onStatesRevisionChanged: root.refresh()
    }

    function refresh() {
        var p = root.mediaPath()
        if (!dashboard || !p.length)
            return
        var cached = dashboard.cachedMediaUrl(p)
        if (cached && cached.length)
            root.imageUrl = cached
        else if (p !== root.requestedPath) {
            root.requestedPath = p
            dashboard.prefetchMedia(p)
        }
    }

    Component.onCompleted: root.refresh()

    Item {
        id: pictureArea
        x: -Theme.paddingMedium
        width: root.width
        height: Math.max(Theme.itemSizeExtraLarge, width * 0.5)

        Image {
            id: picture
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: root.imageUrl
            visible: false
        }

        Loader {
            id: filterLoader
            anchors.fill: parent
            active: root.stateFilter.length > 0 && root.imageUrl.length > 0
            source: Qt.resolvedUrl("../PictureFilter.qml")
            visible: false
            onLoaded: {
                item.source = picture
                item.filterHue = Qt.binding(function() { return root.filterHue })
                item.filterSaturation = Qt.binding(function() { return root.filterSaturation })
                item.filterLightness = Qt.binding(function() { return root.filterLightness })
            }
        }

        Rectangle {
            id: pictureMask
            anchors.fill: parent
            radius: root.radius
            visible: false
        }

        OpacityMask {
            anchors.fill: parent
            source: filterLoader.item ? filterLoader.item : picture
            maskSource: pictureMask
            opacity: root.filterOpacity
            cached: true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: overlay.height + 2 * Theme.paddingSmall
            color: "black"
            opacity: overlay.visible ? 0.45 : 0
        }

        Column {
            id: overlay
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.paddingSmall
            visible: nameLabel.visible || stateLabel.visible

            Label {
                id: nameLabel
                width: parent.width
                visible: !card || card.show_name !== false
                text: {
                    if (card && card.name)
                        return String(card.name)
                    return (dashboard && root.rev >= 0)
                            ? dashboard.friendlyName(entityId) : entityId
                }
                color: "white"
                truncationMode: TruncationMode.Fade
            }

            Label {
                id: stateLabel
                width: parent.width
                visible: !card || card.show_state !== false
                text: (dashboard && root.rev >= 0)
                      ? dashboard.formatState(entityId) : ""
                color: "white"
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
            }
        }
    }
}
