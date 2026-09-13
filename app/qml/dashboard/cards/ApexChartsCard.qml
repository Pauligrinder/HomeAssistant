import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// Native implementation of the Nordpool ApexCharts configuration used by the
// dashboard. It reads attributes.data directly, avoiding browser-side EVAL.
CardChrome {
    id: root
    tapEnabled: false
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var series: (card && card.series) ? card.series : []
    property date now: new Date()
    readonly property date rangeStart: chartStart()
    readonly property date rangeEnd: new Date(rangeStart.getTime() + graphHours() * 3600000)
    readonly property real plotLeft: Theme.itemSizeSmall
    readonly property real plotRight: Theme.paddingSmall
    readonly property real plotTop: Theme.paddingSmall
    readonly property real plotBottom: Theme.itemSizeSmall

    function graphHours() {
        var span = card && card.graph_span ? String(card.graph_span) : "24h"
        var match = /^\s*([0-9.]+)\s*([mhdw])\s*$/.exec(span)
        if (!match)
            return 24
        var n = Number(match[1])
        if (match[2] === "m")
            return n / 60
        if (match[2] === "d")
            return n * 24
        if (match[2] === "w")
            return n * 24 * 7
        return n
    }

    function chartStart() {
        var d = new Date(root.now.getTime())
        var start = card && card.span && card.span.start
                    ? String(card.span.start) : ""
        if (start === "hour")
            d.setMinutes(0, 0, 0)
        else if (start === "day")
            d.setHours(0, 0, 0, 0)
        return d
    }

    function rawData(seriesConfig) {
        if (!dashboard || !seriesConfig || !seriesConfig.entity)
            return []
        var value = dashboard.attribute(String(seriesConfig.entity), "data")
        return value && typeof value.length !== "undefined" ? value : []
    }

    function isToday(date) {
        // This intentionally mirrors the supplied data_generator.
        return date.getDate() === root.now.getDate()
               && date.getMonth() === root.now.getMonth()
               && date.getFullYear() === root.now.getFullYear()
    }

    function pointsFor(index) {
        if (index < 0 || index >= series.length)
            return []
        var config = series[index]
        var source = rawData(config)
        var generator = config.data_generator ? String(config.data_generator) : ""
        var tomorrow = generator.indexOf("notToday") >= 0
        var todayOnly = !tomorrow && generator.indexOf("isToday") >= 0
        var result = []
        for (var i = 0; i < source.length; ++i) {
            var item = source[i]
            if (!item || !item.start)
                continue
            var date = new Date(String(item.start))
            var value = Number(item.price)
            if (isNaN(date.getTime()) || isNaN(value))
                continue
            if ((tomorrow && root.isToday(date))
                    || (todayOnly && !root.isToday(date)))
                continue
            result.push({ "time": date.getTime() + 1800000, "value": value })
        }
        result.sort(function(a, b) { return a.time - b.time })
        return result
    }

    function visiblePoints(index) {
        var source = pointsFor(index)
        var result = []
        var start = rangeStart.getTime()
        var end = rangeEnd.getTime()
        for (var i = 0; i < source.length; ++i) {
            if (source[i].time >= start && source[i].time <= end)
                result.push(source[i])
        }
        return result
    }

    function extrema(index) {
        var points = visiblePoints(index)
        if (!points.length)
            return { "min": 0, "max": 0 }
        var min = points[0].value
        var max = min
        for (var i = 1; i < points.length; ++i) {
            min = Math.min(min, points[i].value)
            max = Math.max(max, points[i].value)
        }
        return { "min": min, "max": max }
    }

    function chartExtrema() {
        var found = false
        var min = 0
        var max = 0
        for (var s = 0; s < series.length; ++s) {
            var points = visiblePoints(s)
            for (var i = 0; i < points.length; ++i) {
                var value = points[i].value
                if (!found) {
                    min = max = value
                    found = true
                } else {
                    min = Math.min(min, value)
                    max = Math.max(max, value)
                }
            }
        }
        if (!found)
            return { "min": 0, "max": 1 }
        if (min === max)
            return { "min": min - 1, "max": max + 1 }
        return { "min": Math.min(0, min), "max": max }
    }

    function thresholdColor(seriesConfig, value) {
        var thresholds = seriesConfig && seriesConfig.color_threshold
                         ? seriesConfig.color_threshold : []
        var color = seriesConfig && seriesConfig.color
                    ? String(seriesConfig.color) : Theme.highlightColor
        for (var i = 0; i < thresholds.length; ++i) {
            if (value >= Number(thresholds[i].value))
                color = String(thresholds[i].color)
        }
        return color
    }

    function currentValue(index) {
        var points = pointsFor(index)
        if (!points.length)
            return NaN
        var now = root.now.getTime()
        var best = points[0]
        var distance = Math.abs(best.time - now)
        for (var i = 1; i < points.length; ++i) {
            var nextDistance = Math.abs(points[i].time - now)
            if (nextDistance < distance) {
                best = points[i]
                distance = nextDistance
            }
        }
        return best.value
    }

    function unitFor(config) {
        return config && config.unit ? String(config.unit) : ""
    }

    Column {
        width: parent.width
        visible: !card || !card.header || card.header.show !== false

        Label {
            width: parent.width
            text: card && card.header && card.header.title
                  ? String(card.header.title) : "Chart"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }

            Repeater {
            model: (card && card.header && card.header.show_states) ? root.series : []
            Label {
                readonly property real value: {
                    var _ = root.rev
                    var __ = root.now
                    return root.currentValue(index)
                }
                width: parent.width
                visible: !modelData.show || modelData.show.in_header !== false
                text: isNaN(value) ? "—" : value.toFixed(1) + " " + root.unitFor(modelData)
                color: (card.header.colorize_states && !isNaN(value))
                       ? root.thresholdColor(modelData, value) : Theme.primaryColor
                font.pixelSize: Theme.fontSizeLarge
            }
        }
    }

    Canvas {
        id: chart
        width: parent.width
        height: (card && card.apex_config && card.apex_config.chart
                 && card.apex_config.chart.height)
                ? Number(card.apex_config.chart.height) : 320

        onPaint: {
            // Reading rev makes state attribute changes repaint the chart.
            var revision = root.rev
            var clock = root.now
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var left = root.plotLeft
            var right = width - root.plotRight
            var top = root.plotTop
            var bottom = height - root.plotBottom
            var plotWidth = right - left
            var plotHeight = bottom - top
            var limits = root.chartExtrema()
            var range = limits.max - limits.min

            ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.25)
            ctx.fillStyle = Theme.secondaryColor
            ctx.font = Theme.fontSizeTiny + "px sans-serif"
            ctx.lineWidth = 1
            for (var g = 0; g <= 4; ++g) {
                var gy = top + g * plotHeight / 4
                ctx.beginPath()
                ctx.moveTo(left, gy)
                ctx.lineTo(right, gy)
                ctx.stroke()
                var label = (limits.max - g * range / 4).toFixed(1)
                ctx.fillText(label, 0, gy + Theme.fontSizeTiny / 2)
            }

            var start = root.rangeStart.getTime()
            var end = root.rangeEnd.getTime()
            for (var tick = 0; tick <= 4; ++tick) {
                var tx = left + tick * plotWidth / 4
                var time = new Date(start + tick * (end - start) / 4)
                var hours = time.getHours()
                var minutes = time.getMinutes()
                var timeLabel = (hours < 10 ? "0" : "") + hours + ":"
                              + (minutes < 10 ? "0" : "") + minutes
                ctx.fillText(timeLabel, tx - Theme.paddingLarge, height - 2)
            }

            for (var s = 0; s < root.series.length; ++s) {
                var config = root.series[s]
                if (config.show && config.show.in_chart === false)
                    continue
                var points = root.visiblePoints(s)
                var lowest = -1
                var highest = -1
                for (var p = 0; p < points.length; ++p) {
                    var point = points[p]
                    var nextTime = p + 1 < points.length
                                   ? points[p + 1].time : point.time + 3600000
                    var x1 = left + (point.time - start) / (end - start) * plotWidth
                    var x2 = left + (nextTime - start) / (end - start) * plotWidth
                    var barWidth = Math.max(1, (x2 - x1) * 0.95)
                    var zeroY = top + (limits.max - 0) / range * plotHeight
                    var valueY = top + (limits.max - point.value) / range * plotHeight
                    ctx.fillStyle = root.thresholdColor(config, point.value)
                    ctx.fillRect(x1 - barWidth / 2, Math.min(zeroY, valueY),
                                 barWidth, Math.max(1, Math.abs(zeroY - valueY)))
                    if (lowest < 0 || point.value < points[lowest].value)
                        lowest = p
                    if (highest < 0 || point.value > points[highest].value)
                        highest = p
                }

                if (!(config.show && config.show.extremas) || lowest < 0)
                    continue
                // Mark the cheapest and priciest hour, as show.extremas does.
                var marks = [lowest, highest]
                for (var m = 0; m < marks.length; ++m) {
                    var mark = points[marks[m]]
                    var mx = left + (mark.time - start) / (end - start) * plotWidth
                    var my = top + (limits.max - mark.value) / range * plotHeight
                    var text = mark.value.toFixed(1)
                    var textWidth = ctx.measureText(text).width
                    var tx = Math.max(left, Math.min(right - textWidth, mx - textWidth / 2))
                    var above = mark.value >= 0
                    ctx.fillStyle = root.thresholdColor(config, mark.value)
                    ctx.fillText(text, tx,
                                 above ? Math.max(top + Theme.fontSizeTiny,
                                                  my - Theme.paddingSmall / 2)
                                       : Math.min(bottom, my + Theme.fontSizeTiny))
                }
            }

            if (root.card && root.card.now && root.card.now.show) {
                var now = root.now.getTime()
                if (now >= start && now <= end) {
                    var nx = left + (now - start) / (end - start) * plotWidth
                    ctx.strokeStyle = root.card.now.color
                                      ? String(root.card.now.color) : Theme.highlightColor
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(nx, top)
                    ctx.lineTo(nx, bottom)
                    ctx.stroke()
                    ctx.fillStyle = ctx.strokeStyle
                    ctx.fillText(root.card.now.label ? String(root.card.now.label) : "Now",
                                 nx + Theme.paddingSmall, top + Theme.fontSizeTiny)
                }
            }
        }

        Connections {
            target: root
            onRevChanged: chart.requestPaint()
            onNowChanged: chart.requestPaint()
        }
        Component.onCompleted: requestPaint()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Flow {
        width: parent.width
        spacing: Theme.paddingMedium

            Repeater {
            model: root.series
            Label {
                readonly property var limits: {
                    var _ = root.rev
                    var __ = root.now
                    return root.extrema(index)
                }
                visible: !modelData.show || modelData.show.in_legend !== false
                text: (modelData.name ? String(modelData.name) : String(modelData.entity))
                      + ": " + limits.min.toFixed(1) + "–" + limits.max.toFixed(1)
                      + root.unitFor(modelData)
                color: modelData.color ? String(modelData.color) : Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }
    }
}
