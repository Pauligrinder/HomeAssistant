import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// Camera stills / MJPEG must not hit the scene at full resolution during the
// first paint (hybris ANR). Poster first, then a capped still or live stream.
CardChrome {
    id: root
    tapEnabled: true
    contentTopMargin: 0
    contentBottomMargin: Theme.paddingMedium
    contentHorizontalMargin: 0
    readonly property int rev: root.statesRevision
    readonly property var entityList: (card && card.entities) ? card.entities : []
    property string imageUrl: ""
    property string requestedPath: ""
    property string activePath: ""
    property bool streamArmed: false
    readonly property string cameraEntity: {
        if (card && card.camera_image)
            return String(card.camera_image)
        if (card && card.entity && dashboard && dashboard.domainOf(String(card.entity)) === "camera")
            return String(card.entity)
        return ""
    }
    readonly property string cameraView: {
        if (!card || card.camera_view === undefined || card.camera_view === null)
            return "auto"
        return String(card.camera_view)
    }
    readonly property bool wantLive: root.cameraEntity.length > 0
                                     && (root.cameraView === "live" || root.cameraView === "auto")
    readonly property string titleText: {
        if (!card)
            return ""
        if (card.title !== undefined && card.title !== null && String(card.title).length)
            return String(card.title)
        if (card.name !== undefined && card.name !== null && String(card.name).length)
            return String(card.name)
        return ""
    }
    readonly property int maxSourcePx: Math.round(640 * Math.max(1, Theme.pixelRatio))

    // Open camera / entity more-info (CardChrome otherwise only sees card.entity).
    tapHandler: function() {
        if (!dashboard)
            return
        if (card && card.tap_action) {
            dashboard.performAction(card.tap_action, root.cameraEntity)
            return
        }
        if (root.cameraEntity.length)
            dashboard.openMoreInfo(root.cameraEntity)
        else if (card)
            dashboard.handleCardTap(card)
    }

    function posterPath() {
        return dashboard ? dashboard.mediaPathOf(card ? card.image : "") : ""
    }

    function cameraMediaPath() {
        if (!dashboard || !root.cameraEntity.length)
            return ""
        return dashboard.cameraPath(root.cameraEntity)
    }

    function applyPath(path) {
        if (!dashboard || !path.length)
            return
        root.activePath = path
        var cached = dashboard.cachedMediaUrl(path)
        if (cached && cached.length) {
            root.imageUrl = cached
            return
        }
        if (path !== root.requestedPath) {
            root.requestedPath = path
            dashboard.prefetchMedia(path)
        }
    }

    function showPoster() {
        var path = root.posterPath()
        if (path.length)
            root.applyPath(path)
    }

    function showCameraStill() {
        var path = root.cameraMediaPath()
        if (path.length)
            root.applyPath(path)
    }

    Connections {
        target: dashboard
        onMediaCached: {
            if (path === root.activePath)
                root.imageUrl = fileUrl
        }
    }

    Component.onCompleted: {
        root.showPoster()
        cameraDelay.start()
    }

    Component.onDestruction: {
        root.streamArmed = false
    }

    Timer {
        id: cameraDelay
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.wantLive) {
                root.streamArmed = true
                return
            }
            root.showCameraStill()
        }
    }

    Column {
        width: parent.width
        spacing: Theme.paddingSmall

        Item {
            id: stage
            width: parent.width
            height: Math.max(Theme.itemSizeExtraLarge, width * 9 / 16)

            Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                visible: !(livePlayer.active && livePlayer.stream
                           && livePlayer.stream.playing)
                source: root.imageUrl
                sourceSize.width: root.maxSourcePx
                sourceSize.height: root.maxSourcePx
            }

            CameraStreamPlayer {
                id: livePlayer
                anchors.fill: parent
                stream: dashboard ? dashboard.cameraStream : null
                entityId: root.cameraEntity
                active: root.streamArmed && root.wantLive
                        && Qt.application.state === Qt.ApplicationActive
            }

            BusyIndicator {
                anchors.centerIn: parent
                size: BusyIndicatorSize.Medium
                running: {
                    if (livePlayer.active)
                        return !!(livePlayer.stream && livePlayer.stream.loading
                                  && !(livePlayer.stream.playing))
                    return String(root.imageUrl).length === 0
                            && root.requestedPath.length > 0
                }
                visible: running
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: titleLabel.height + 2 * Theme.paddingSmall
                visible: titleLabel.text.length > 0
                color: "#000000"
                opacity: 0.55
                z: 5
            }

            Label {
                id: titleLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.paddingSmall
                z: 6
                text: root.titleText
                color: "#FFFFFF"
                font.pixelSize: Theme.fontSizeSmall
                truncationMode: TruncationMode.Fade
            }
        }

        Flow {
            width: parent.width - 2 * Theme.paddingMedium
            x: Theme.paddingMedium
            spacing: Theme.paddingSmall
            Repeater {
                model: root.entityList
                MouseArea {
                    width: Theme.itemSizeMedium
                    height: Theme.itemSizeMedium
                    z: 2
                    visible: !dashboard || root.rev < 0
                             || dashboard.entityEntryVisible(modelData)
                    opacity: root.withPressOpacity(
                                 (entityId.length && dashboard && root.rev >= 0
                                  && dashboard.entityDimmed(entityId)) ? 0.45 : 1.0,
                                 pressed)
                    property string entityId: typeof modelData === "string" ? modelData
                                              : (modelData.entity ? String(modelData.entity) : "")
                    onClicked: {
                        if (dashboard && entityId.length)
                            dashboard.openMoreInfo(entityId)
                    }
                    Column {
                        anchors.fill: parent
                        Item {
                            x: (parent.width - width) / 2
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            MdiIcon {
                                anchors.fill: parent
                                mdiIcons: root.mdiIcons
                                name: (dashboard && root.rev >= 0) ? dashboard.entityIcon(entityId) : ""
                                iconColor: (dashboard && root.rev >= 0 && dashboard.isOn(entityId))
                                           ? Theme.highlightColor : Theme.primaryColor
                                width: Theme.iconSizeSmall
                                opacity: (dashboard && root.rev >= 0 && dashboard.isPending(entityId))
                                         ? 0.55 : 1.0
                            }
                            PendingIndicator {
                                anchors.centerIn: parent
                                dashboard: root.dashboard
                                entityId: entityId
                            }
                        }
                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Theme.fontSizeTiny
                            wrapMode: Text.Wrap
                            text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
                        }
                    }
                }
            }
        }
    }
}
