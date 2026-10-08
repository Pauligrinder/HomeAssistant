import QtQuick 2.6
import Sailfish.Silica 1.0

// Header and footer elements of an entities card. Home Assistant defines
// several element types; picture and graph are the ones drawn here, and
// anything else collapses to nothing.
Item {
    id: extra
    property var config: ({})
    property var dashboard
    property real edgeWidth: width
    property real edgeOffset: 0
    property real cornerRadius: 0
    property bool roundTop: false
    property bool roundBottom: false
    readonly property string type: (config && config.type) ? String(config.type) : ""

    width: parent ? parent.width : 0
    height: loader.height
    visible: loader.item !== null

    // A Loader with an explicit width resizes whatever it loads, so the
    // edge-to-edge geometry of a picture has to live here: setting it on the
    // loaded item instead would have the Loader overwrite it.
    Loader {
        id: loader
        x: extra.type === "picture" ? extra.edgeOffset : 0
        width: extra.type === "picture" ? extra.edgeWidth : extra.width
        sourceComponent: {
            if (extra.type === "picture")
                return pictureComponent
            if (extra.type === "graph")
                return graphComponent
            return undefined
        }
    }

    Component {
        id: pictureComponent
        Item {
            id: picture
            // Home Assistant shows the picture at full width with its own
            // aspect ratio; the fallback only applies until it has loaded.
            height: image.aspectRatio > 0
                    ? width / image.aspectRatio
                    : Math.max(Theme.itemSizeMedium, width * 0.3)
            property string imageUrl: ""
            property string requestedPath: ""

            function mediaPath() {
                return extra.dashboard
                        ? extra.dashboard.mediaPathOf(extra.config ? extra.config.image : "")
                        : ""
            }

            function refresh() {
                var path = picture.mediaPath()
                if (!extra.dashboard || !path.length)
                    return
                var cached = extra.dashboard.cachedMediaUrl(path)
                if (cached && cached.length)
                    picture.imageUrl = cached
                else if (path !== picture.requestedPath) {
                    picture.requestedPath = path
                    extra.dashboard.prefetchMedia(path)
                }
            }

            Connections {
                target: extra.dashboard
                onMediaCached: {
                    if (path === picture.mediaPath())
                        picture.imageUrl = fileUrl
                }
            }

            Component.onCompleted: picture.refresh()
            opacity: pictureTap.pressed && pictureTap.enabled ? 0.6 : 1.0

            RoundedImage {
                id: image
                anchors.fill: parent
                source: picture.imageUrl
                fillMode: Image.PreserveAspectFit
                cornerRadius: extra.cornerRadius
                roundTop: extra.roundTop
                roundBottom: extra.roundBottom
            }

            MouseArea {
                id: pictureTap
                anchors.fill: parent
                enabled: !!(extra.config && extra.config.tap_action)
                onClicked: extra.dashboard.performAction(extra.config.tap_action, "")
            }
        }
    }

    Component {
        id: graphComponent
        Item {
            id: graph
            width: extra.width
            height: chart.height > 0 ? chart.height : Theme.itemSizeSmall
            property string entityId: (extra.config && extra.config.entity)
                                      ? String(extra.config.entity) : ""
            property var points: []
            readonly property int hours: {
                if (extra.config && extra.config.hours_to_show)
                    return Math.max(1, Number(extra.config.hours_to_show) || 24)
                return 24
            }
            readonly property string unit: {
                if (!extra.dashboard || !graph.entityId.length)
                    return ""
                var u = extra.dashboard.attribute(graph.entityId, "unit_of_measurement")
                return u ? String(u) : ""
            }

            Connections {
                target: extra.dashboard
                onHistoryReady: {
                    if (entityId === graph.entityId)
                        graph.points = points
                }
            }

            Component.onCompleted: {
                if (!extra.dashboard || !graph.entityId.length)
                    return
                extra.dashboard.fetchHistory([graph.entityId], graph.hours)
            }

            HistoryChart {
                id: chart
                width: parent.width
                points: graph.points
                hours: graph.hours
                unit: graph.unit
                showTitle: false
                compact: true
                chartHeight: Theme.itemSizeMedium
            }
        }
    }
}
