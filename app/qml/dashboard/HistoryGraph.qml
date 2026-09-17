import QtQuick 2.6
import Sailfish.Silica 1.0

// 24h (or N-hour) sparkline for more-info. Hidden until history has at least
// two plottable points, so cameras and other non-numeric entities stay clean.
Item {
    id: root
    property var dashboard
    property string entityId: ""
    property int hours: 24
    property var points: []
    readonly property var samples: {
        var src = root.points
        return src ? root.plotSamples() : []
    }
    readonly property bool hasGraph: samples.length >= 2
    readonly property string unit: {
        if (!dashboard || !root.entityId.length)
            return ""
        var u = dashboard.attribute(root.entityId, "unit_of_measurement")
        return u ? String(u) : ""
    }

    width: parent ? parent.width : 0
    height: hasGraph ? (caption.height + canvas.height + rangeLabel.height
                        + Theme.paddingSmall) : 0
    visible: hasGraph
    clip: true

    function plotValue(state) {
        if (state === undefined || state === null || state === ""
                || state === "unavailable" || state === "unknown")
            return NaN
        var n = Number(state)
        if (!isNaN(n))
            return n
        var s = String(state).toLowerCase()
        if (s === "on" || s === "true" || s === "open" || s === "unlocked"
                || s === "detected" || s === "home" || s === "active"
                || s === "occupied" || s === "wet" || s === "motion")
            return 1
        if (s === "off" || s === "false" || s === "closed" || s === "locked"
                || s === "clear" || s === "not_home" || s === "empty" || s === "dry")
            return 0
        return NaN
    }

    function parseTime(stamp) {
        if (!stamp)
            return 0
        var t = Date.parse(stamp)
        return isNaN(t) ? 0 : t
    }

    function plotSamples() {
        var src = root.points || []
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var value = root.plotValue(src[i].state)
            if (isNaN(value))
                continue
            out.push({
                         "t": root.parseTime(src[i].last_changed),
                         "v": value
                     })
        }
        return out
    }

    function rangeText() {
        var src = root.samples
        if (src.length < 2)
            return ""
        var min = src[0].v
        var max = src[0].v
        for (var i = 1; i < src.length; ++i) {
            if (src[i].v < min)
                min = src[i].v
            if (src[i].v > max)
                max = src[i].v
        }
        function fmt(n) {
            return (Math.abs(n - Math.round(n)) < 0.05)
                    ? String(Math.round(n)) : n.toFixed(1)
        }
        var text = fmt(min) + " – " + fmt(max)
        if (root.unit.length)
            text += " " + root.unit
        return text
    }

    function refresh() {
        root.points = []
        if (dashboard && root.entityId.length)
            dashboard.fetchHistory([root.entityId], root.hours > 0 ? root.hours : 24)
    }

    Connections {
        target: dashboard
        onHistoryReady: {
            if (entityId === root.entityId)
                root.points = points
        }
    }

    onEntityIdChanged: root.refresh()
    onDashboardChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Label {
        id: caption
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: root.hours === 24 ? "Last 24 hours"
                                : ("Last " + root.hours + " hours")
    }

    Canvas {
        id: canvas
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: caption.bottom
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        height: Theme.itemSizeExtraLarge
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var src = root.samples
            if (src.length < 2 || width < 4 || height < 4)
                return
            var min = src[0].v
            var max = src[0].v
            var t0 = src[0].t
            var t1 = src[0].t
            var timed = true
            for (var i = 1; i < src.length; ++i) {
                if (src[i].v < min)
                    min = src[i].v
                if (src[i].v > max)
                    max = src[i].v
                if (src[i].t < t0)
                    t0 = src[i].t
                if (src[i].t > t1)
                    t1 = src[i].t
                if (!src[i].t)
                    timed = false
            }
            if (!src[0].t)
                timed = false
            if (min === max) {
                min -= 1
                max += 1
            }
            var span = (timed && t1 > t0) ? (t1 - t0) : 0
            ctx.strokeStyle = Theme.highlightColor
            ctx.lineWidth = 2
            ctx.beginPath()
            for (var j = 0; j < src.length; ++j) {
                var x
                if (span > 0)
                    x = ((src[j].t - t0) / span) * (width - 2)
                else
                    x = j * (width - 2) / (src.length - 1)
                var y = height - ((src[j].v - min) / (max - min)) * (height - 4) - 2
                if (j === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.stroke()
        }
        Connections {
            target: root
            onPointsChanged: canvas.requestPaint()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Label {
        id: rangeLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: canvas.bottom
        anchors.leftMargin: Theme.horizontalPageMargin
        anchors.rightMargin: Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        text: {
            var s = root.samples
            return s ? root.rangeText() : ""
        }
    }
}
