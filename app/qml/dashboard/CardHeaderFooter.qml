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
            height: Theme.itemSizeSmall
            property string entityId: (extra.config && extra.config.entity)
                                      ? String(extra.config.entity) : ""
            property var points: []

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
                var hours = (extra.config && extra.config.hours_to_show)
                        ? Number(extra.config.hours_to_show) : 24
                extra.dashboard.fetchHistory([graph.entityId], hours > 0 ? hours : 24)
            }

            Canvas {
                id: canvas
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var src = graph.points || []
                    var values = []
                    for (var i = 0; i < src.length; ++i) {
                        var value = Number(src[i].state)
                        if (!isNaN(value))
                            values.push(value)
                    }
                    if (values.length < 2)
                        return
                    var min = Math.min.apply(Math, values)
                    var max = Math.max.apply(Math, values)
                    if (min === max) {
                        min -= 1
                        max += 1
                    }
                    ctx.strokeStyle = Theme.highlightColor
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var j = 0; j < values.length; ++j) {
                        var x = j * (width - 2) / (values.length - 1)
                        var y = height - ((values[j] - min) / (max - min)) * (height - 4) - 2
                        if (j === 0)
                            ctx.moveTo(x, y)
                        else
                            ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
                Connections {
                    target: graph
                    onPointsChanged: canvas.requestPaint()
                }
            }
        }
    }
}
