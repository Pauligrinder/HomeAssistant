import QtQuick 2.6
import QtGraphicalEffects 1.0
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    property string imageUrl: ""
    property string requestedPath: ""
    // state_filter goes through HueSaturation and OpacityMask, which keep a
    // framebuffer. Recreate that path after the GL context comes back.
    property bool filterLive: true
    property bool textureLost: false
    property bool beenActive: false
    readonly property int rev: root.statesRevision
    contentTopMargin: 0
    contentBottomMargin: 0
    contentHorizontalMargin: 0
    readonly property bool lightAmbience: Theme.colorScheme === Theme.DarkOnLight
    readonly property bool showName: !card || card.show_name !== false
    readonly property bool showState: !card || card.show_state !== false
    readonly property bool showOverlay: root.showName || root.showState
    readonly property string nameText: {
        var _ = root.rev
        if (card && card.name !== undefined && card.name !== null
                && String(card.name).length)
            return String(card.name)
        if (root.entityId.length && dashboard && root.rev >= 0)
            return dashboard.friendlyName(root.entityId)
        return root.entityId
    }
    readonly property string stateText: {
        var _ = root.rev
        if (!root.entityId.length || !dashboard || root.rev < 0)
            return ""
        return dashboard.formatState(root.entityId)
    }

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
            // Signal arg is also named entityId — compare against the card's.
            if (entityId === root.entityId)
                root.refresh()
        }
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

    Component.onCompleted: {
        root.beenActive = Qt.application.state === Qt.ApplicationActive
        root.refresh()
    }

    Timer {
        id: filterReload
        interval: 1
        property url pending
        onTriggered: {
            var url = pending
            pending = ""
            root.textureLost = false
            if (!url || String(url).length === 0 || String(picture.source).length > 0)
                return
            picture.source = url
            if (root.stateFilter.length === 0)
                return
            root.filterLive = false
            filterRestore.restart()
        }
    }

    Timer {
        id: filterRestore
        interval: 1
        onTriggered: root.filterLive = true
    }

    function reloadPicture() {
        var url = String(root.imageUrl).length ? root.imageUrl : picture.source
        if (!url || String(url).length === 0) {
            textureLost = false
            return
        }
        filterReload.pending = url
        picture.source = ""
        filterReload.restart()
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive) {
                if (root.beenActive && root.textureLost && root.stateFilter.length > 0)
                    root.reloadPicture()
                else
                    root.textureLost = false
                root.beenActive = true
            } else if (root.beenActive) {
                root.textureLost = true
            }
        }
    }

    Item {
        id: pictureArea
        width: root.width
        height: root.fillHeight > 0
                ? root.fillHeight
                : Math.max(Theme.itemSizeExtraLarge, width * 0.5)

        // Default path: RoundedImage (no cached FBO over the footer).
        RoundedImage {
            anchors.fill: parent
            visible: root.stateFilter.length === 0
            source: root.imageUrl
            cornerRadius: root.radius
            roundBottom: !root.showOverlay
            fillMode: Image.PreserveAspectCrop
        }

        // Filtered path only when state_filter is set.
        Item {
            anchors.fill: parent
            visible: root.stateFilter.length > 0

            Image {
                id: picture
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
                property url pictureUrl: root.imageUrl
                function applyUrl() {
                    if (String(picture.source) === String(pictureUrl))
                        return
                    picture.source = pictureUrl
                }
                onPictureUrlChanged: applyUrl()
                Component.onCompleted: applyUrl()
            }

            BusyIndicator {
                anchors.centerIn: parent
                z: 2
                size: BusyIndicatorSize.Medium
                running: root.stateFilter.length > 0
                         && root.imageUrl.length > 0
                         && picture.status !== Image.Ready
                         && picture.status !== Image.Error
                visible: running
            }

            Loader {
                id: filterLoader
                anchors.fill: parent
                active: root.filterLive && root.stateFilter.length > 0 && root.imageUrl.length > 0
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

                // Square the bottom under the footer so no dark crescent shows.
                Rectangle {
                    visible: root.showOverlay
                    y: parent.height - root.radius
                    width: parent.width
                    height: root.radius
                    color: parent.color
                }
            }

            OpacityMask {
                anchors.fill: parent
                source: filterLoader.item ? filterLoader.item : picture
                maskSource: pictureMask
                opacity: root.filterOpacity
                cached: false
            }
        }

        // Flat bar — no radius/cover strip (that stacked into a darker band).
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: overlay.height + 2 * Theme.paddingSmall
            visible: root.showOverlay
            z: 10
            color: root.lightAmbience ? "#FFFFFF" : "#000000"
            opacity: 0.55
        }

        Column {
            id: overlay
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.paddingSmall
            visible: root.showOverlay
            z: 11

            Label {
                width: parent.width
                visible: root.showName
                text: root.nameText
                color: root.lightAmbience ? "#111111" : "#FFFFFF"
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeSmall
            }

            Label {
                width: parent.width
                visible: root.showState
                text: root.stateText
                color: root.lightAmbience ? "#333333" : "#F0F0F0"
                font.pixelSize: Theme.fontSizeExtraSmall
                truncationMode: TruncationMode.Fade
            }
        }
    }
}
