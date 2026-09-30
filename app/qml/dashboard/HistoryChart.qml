import QtQuick 2.6
import Sailfish.Silica 1.0

// Shared 24h (or N-hour) history plot: numeric line chart, or a horizontal
// state bar for categorical entities. Draws a grid plus x/y axis labels.
Item {
    id: root
    property var points: []
    property int hours: 24
    property string unit: ""
    property string title: ""
    property color accent: Theme.highlightColor
    property bool compact: false
    property bool showTitle: true
    property real chartHeight: compact ? Theme.itemSizeSmall
                                       : Theme.itemSizeExtraLarge

    readonly property var samples: root.buildSamples()
    readonly property var periods: root.buildPeriods()
    readonly property var legendModel: {
        var src = root.periods
        return src ? root.legendStates() : []
    }
    readonly property bool numeric: root.samples.length >= 2
    readonly property bool categorical: !root.numeric && root.periods.length > 0
    readonly property bool hasContent: root.numeric || root.categorical
    readonly property real plotLeft: compact ? Theme.paddingLarge
                                             : Theme.itemSizeSmall
    readonly property real plotRight: Theme.paddingMedium
    readonly property real plotTop: Theme.paddingSmall
    readonly property real plotBottom: compact ? Theme.paddingMedium
                                               : Theme.paddingLarge + Theme.fontSizeTiny

    width: parent ? parent.width : 0
    height: hasContent
            ? ((showTitle && titleLabel.visible ? titleLabel.height : 0)
               + canvas.height
               + (legendRow.visible ? legendRow.height + Theme.paddingSmall : 0))
            : 0
    visible: hasContent
    clip: true

    onPointsChanged: canvas.requestPaint()
    onHoursChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onUnitChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()

    Label {
        id: titleLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.showTitle && root.title.length > 0 && root.hasContent
        text: root.title
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        truncationMode: TruncationMode.Fade
    }

    Canvas {
        id: canvas
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleLabel.visible ? titleLabel.bottom : parent.top
        height: root.chartHeight
        onPaint: root.paintChart(getContext("2d"))
    }

    Flow {
        id: legendRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: canvas.bottom
        anchors.topMargin: Theme.paddingSmall
        spacing: Theme.paddingMedium
        visible: root.categorical && !root.compact && root.legendModel.length > 0

        Repeater {
            model: root.legendModel
            Row {
                spacing: Theme.paddingSmall
                Rectangle {
                    width: Theme.paddingMedium
                    height: width
                    radius: width / 4
                    color: root.colorForState(modelData)
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: root.prettyState(modelData)
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeTiny
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    function parseTime(stamp) {
        if (!stamp)
            return 0
        if (stamp instanceof Date)
            return stamp.getTime()
        var t = Date.parse(stamp)
        return isNaN(t) ? 0 : t
    }

    function plotValue(state) {
        if (state === undefined || state === null || state === ""
                || state === "unavailable" || state === "unknown")
            return NaN
        var n = Number(state)
        return isNaN(n) ? NaN : n
    }

    function buildSamples() {
        var src = root.points || []
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var value = root.plotValue(src[i].state)
            if (isNaN(value))
                continue
            var t = root.parseTime(src[i].last_changed)
            if (!t)
                continue
            out.push({ "t": t, "v": value })
        }
        return out
    }

    function buildPeriods() {
        var src = root.points || []
        if (!src.length)
            return []
        var endBound = Date.now()
        var startBound = endBound - Math.max(1, root.hours) * 3600000
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var start = root.parseTime(src[i].last_changed)
            if (!start)
                continue
            var end = (i + 1 < src.length)
                      ? root.parseTime(src[i + 1].last_changed) : endBound
            if (!end)
                end = endBound
            if (end < startBound || start > endBound)
                continue
            out.push({
                         "state": String(src[i].state || ""),
                         "start": Math.max(start, startBound),
                         "end": Math.min(end, endBound)
                     })
        }
        return out
    }

    function windowBounds() {
        var end = Date.now()
        var start = end - Math.max(1, root.hours) * 3600000
        if (root.numeric) {
            var src = root.samples
            if (src.length) {
                var last = src[src.length - 1].t
                if (last > end)
                    end = last
                start = end - Math.max(1, root.hours) * 3600000
            }
        }
        return { "start": start, "end": end }
    }

    function fmtNumber(n) {
        if (!isFinite(n))
            return ""
        if (Math.abs(n) >= 100 || Math.abs(n - Math.round(n)) < 0.05)
            return String(Math.round(n))
        if (Math.abs(n) >= 10)
            return n.toFixed(1)
        return n.toFixed(2)
    }

    function timeLabel(ms) {
        var d = new Date(ms)
        var h = d.getHours()
        var m = d.getMinutes()
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }

    function prettyState(state) {
        var s = String(state || "")
        if (!s.length)
            return qsTr("Unknown")
        if (s === "unavailable")
            return qsTr("Unavailable")
        if (s === "unknown")
            return qsTr("Unknown")
        s = s.replace(/_/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function colorForState(state) {
        var s = String(state || "").toLowerCase()
        if (s === "home" || s === "on" || s === "open" || s === "unlocked"
                || s === "active" || s === "playing" || s === "detected"
                || s === "occupied" || s === "wet" || s === "motion")
            return "#7CFC00"
        if (s === "not_home" || s === "off" || s === "closed" || s === "locked"
                || s === "idle" || s === "standby" || s === "clear" || s === "dry"
                || s === "empty")
            return "#FF5555"
        if (s === "unavailable" || s === "unknown")
            return Theme.secondaryColor
        var hash = 0
        for (var i = 0; i < s.length; ++i)
            hash = ((hash << 5) - hash) + s.charCodeAt(i)
        var hue = Math.abs(hash) % 360
        return Qt.hsla(hue / 360, 0.55, 0.45, 1)
    }

    function legendStates() {
        var seen = {}
        var out = []
        var src = root.periods
        for (var i = 0; i < src.length; ++i) {
            var s = src[i].state
            if (seen[s])
                continue
            seen[s] = true
            out.push(s)
        }
        return out
    }

    function paintChart(ctx) {
        ctx.clearRect(0, 0, canvas.width, canvas.height)
        if (!root.hasContent || canvas.width < 8 || canvas.height < 8)
            return

        var left = root.plotLeft
        var right = canvas.width - root.plotRight
        var top = root.plotTop
        var bottom = canvas.height - root.plotBottom
        var plotWidth = right - left
        var plotHeight = bottom - top
        if (plotWidth < 4 || plotHeight < 4)
            return

        var bounds = root.windowBounds()
        var start = bounds.start
        var end = bounds.end
        var span = Math.max(1, end - start)

        ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.28)
        ctx.fillStyle = Theme.secondaryColor
        ctx.font = Theme.fontSizeTiny + "px sans-serif"
        ctx.lineWidth = 1

        // Vertical grid + x timestamps
        for (var tick = 0; tick <= 4; ++tick) {
            var tx = left + tick * plotWidth / 4
            ctx.beginPath()
            ctx.moveTo(tx, top)
            ctx.lineTo(tx, bottom)
            ctx.stroke()
            var label = root.timeLabel(start + tick * span / 4)
            var tw = ctx.measureText(label).width
            ctx.fillText(label, Math.max(left, Math.min(right - tw, tx - tw / 2)),
                         canvas.height - 2)
        }

        if (root.numeric)
            root.paintNumeric(ctx, left, right, top, bottom, plotWidth, plotHeight,
                              start, span)
        else
            root.paintCategorical(ctx, left, right, top, bottom, plotWidth,
                                  plotHeight, start, span)
    }

    function paintNumeric(ctx, left, right, top, bottom, plotWidth, plotHeight,
                          start, span) {
        var src = root.samples
        var min = src[0].v
        var max = src[0].v
        for (var i = 1; i < src.length; ++i) {
            if (src[i].v < min)
                min = src[i].v
            if (src[i].v > max)
                max = src[i].v
        }
        if (min === max) {
            min -= 1
            max += 1
        }
        var range = max - min

        // Horizontal grid + y values
        for (var g = 0; g <= 4; ++g) {
            var gy = top + g * plotHeight / 4
            ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.28)
            ctx.beginPath()
            ctx.moveTo(left, gy)
            ctx.lineTo(right, gy)
            ctx.stroke()
            var yLabel = root.fmtNumber(max - g * range / 4)
            if (root.unit.length && (g === 0 || g === 4))
                yLabel += " " + root.unit
            ctx.fillStyle = Theme.secondaryColor
            ctx.fillText(yLabel, 2, gy + Theme.fontSizeTiny / 3)
        }

        ctx.strokeStyle = root.accent
        ctx.lineWidth = 2
        ctx.beginPath()
        var started = false
        for (var j = 0; j < src.length; ++j) {
            var x = left + (src[j].t - start) / span * plotWidth
            var y = top + (max - src[j].v) / range * plotHeight
            if (x < left - 2 || x > right + 2)
                continue
            if (!started) {
                ctx.moveTo(x, y)
                started = true
            } else {
                ctx.lineTo(x, y)
            }
        }
        if (started)
            ctx.stroke()
    }

    function paintCategorical(ctx, left, right, top, bottom, plotWidth,
                              plotHeight, start, span) {
        var barTop = top + plotHeight * 0.2
        var barHeight = Math.max(Theme.paddingMedium, plotHeight * 0.6)

        ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.28)
        ctx.beginPath()
        ctx.moveTo(left, barTop)
        ctx.lineTo(right, barTop)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(left, barTop + barHeight)
        ctx.lineTo(right, barTop + barHeight)
        ctx.stroke()

        var src = root.periods
        for (var i = 0; i < src.length; ++i) {
            var x1 = left + (src[i].start - start) / span * plotWidth
            var x2 = left + (src[i].end - start) / span * plotWidth
            x1 = Math.max(left, Math.min(right, x1))
            x2 = Math.max(left, Math.min(right, x2))
            if (x2 - x1 < 1)
                x2 = x1 + 1
            ctx.fillStyle = root.colorForState(src[i].state)
            ctx.fillRect(x1, barTop, x2 - x1, barHeight)
        }

        ctx.fillStyle = Theme.secondaryColor
        var mid = root.prettyState(src.length ? src[src.length - 1].state : "")
        if (mid.length && !root.compact)
            ctx.fillText(mid, 2, barTop + barHeight / 2 + Theme.fontSizeTiny / 3)
    }
}
