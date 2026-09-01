import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.DBus 2.0

Item {
    id: root

    // The events view loader only sets the width, and takes its height from
    // implicitHeight, so the widget has to report its content height there.
    width: parent ? parent.width : Screen.width
    implicitWidth: width
    implicitHeight: column.height
    height: implicitHeight

    property bool active: visible && eventsViewVisible
    property bool expanded: false
    property int collapsedCount: 2

    property var entities: []
    property string errorText: "Helmsman must be running to show the widget"
    property bool appRunning: false

    // Card whose brightness / color / temperature controls are open.
    property string adjustEntityId: ""
    property bool adjustingSlider: false
    // Script card whose Run/Cancel row is open.
    property string scriptEntityId: ""
    property string dragEntityId: ""
    property bool dragIsNotification: false
    property int dragFromIndex: -1
    property int dragInsertIndex: -1
    property int dragCardHeight: 0
    property real dragY: 0
    property bool dragOverTrash: false
    property string dragName: ""
    property string dragBody: ""
    property string dragColor: "#03A9F4"
    readonly property bool dragging: dragEntityId.length > 0

    readonly property var notificationEntities: {
        var out = []
        var src = root.entities || []
        for (var i = 0; i < src.length; ++i) {
            if (src[i] && src[i].kind === "notification")
                out.push(src[i])
        }
        return out
    }
    readonly property var favoriteEntities: {
        var out = []
        var src = root.entities || []
        for (var i = 0; i < src.length; ++i) {
            if (src[i] && src[i].kind !== "notification")
                out.push(src[i])
        }
        return out
    }
    readonly property var visibleEntities: root.notificationEntities.concat(root.favoriteEntities)

    readonly property var colorSwatches: [
        { "r": 255, "g": 0, "b": 0 },
        { "r": 255, "g": 128, "b": 0 },
        { "r": 255, "g": 220, "b": 0 },
        { "r": 0, "g": 200, "b": 0 },
        { "r": 0, "g": 200, "b": 220 },
        { "r": 0, "g": 80, "b": 255 },
        { "r": 140, "g": 0, "b": 255 },
        { "r": 255, "g": 0, "b": 160 }
    ]

    function parseEntities(payload) {
        root.appRunning = true
        if (!payload || payload.length === 0) {
            root.entities = []
            root.errorText = ""
            return
        }
        try {
            var parsed = JSON.parse(payload)
            if (parsed instanceof Array) {
                root.entities = parsed
                root.errorText = ""
            } else {
                root.entities = []
                root.errorText = "Invalid widget data"
            }
        } catch (e) {
            root.entities = []
            root.errorText = "Widget unavailable"
        }
    }

    function stateLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        if (entity.kind === "script")
            return ""
        if (entity.kind === "notification")
            return entity.state || ""
        if (entity.kind === "climate")
            return root.climateLabel(entity)
        if (entity.kind === "graph" || entity.kind === "sensor")
            return root.graphLabel(entity)
        if (entity.dimmable === true && entity.on === true)
            return "On · " + Math.round(Number(entity.brightnessPct) || 0) + "%"
        return entity.on === true ? "On" : "Off"
    }

    function formatGraphValue(value) {
        var n = Number(value)
        if (!isFinite(n))
            return ""
        if (Math.abs(n) >= 100)
            return String(Math.round(n))
        var shown = n.toFixed(2).replace(/\.?0+$/, "")
        return shown.length ? shown : "0"
    }

    function graphLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        var shown = root.formatGraphValue(entity.graphNow)
        if (!shown.length && entity.state && entity.state !== "unknown"
                && entity.state !== "unavailable")
            shown = entity.state
        var unit = entity.graphUnit || ""
        if (!shown.length)
            return unit
        return unit ? (shown + " " + unit) : shown
    }

    function graphBarRgb(v, minV, maxV) {
        var t = (maxV > minV) ? ((v - minV) / (maxV - minV)) : 0.5
        if (t < 0)
            t = 0
        if (t > 1)
            t = 1
        var r
        var g
        var b
        if (t < 0.5) {
            var u = t * 2
            r = Math.round(76 + (255 - 76) * u)
            g = Math.round(175 + (193 - 175) * u)
            b = Math.round(80 + (7 - 80) * u)
        } else {
            var u = (t - 0.5) * 2
            r = Math.round(255 + (229 - 255) * u)
            g = Math.round(193 + (57 - 193) * u)
            b = Math.round(7 + (53 - 7) * u)
        }
        return "rgb(" + r + "," + g + "," + b + ")"
    }

    function graphValueRange(pts, minHint, maxHint) {
        var vmin = Number(minHint)
        var vmax = Number(maxHint)
        if (!(vmax > vmin) && pts && pts.length) {
            vmin = Number(pts[0].v)
            vmax = vmin
            for (var i = 1; i < pts.length; ++i) {
                var pv = Number(pts[i].v)
                if (pv < vmin)
                    vmin = pv
                if (pv > vmax)
                    vmax = pv
            }
        }
        if (!(vmax > vmin)) {
            vmin -= 1
            vmax += 1
        }
        return { "min": vmin, "max": vmax }
    }

    function paintBarWatermark(ctx, w, h, pts, minHint, maxHint, nowMs) {
        if (!pts || pts.length === 0 || w <= 0 || h <= 8)
            return
        var pad = 4
        var plotH = h - pad * 2
        var t0 = Number(pts[0].t)
        var tLast = Number(pts[pts.length - 1].t)
        var interval = pts.length >= 2
                ? Math.max(1, Number(pts[pts.length - 1].t) - Number(pts[pts.length - 2].t))
                : 3600000
        var t1 = tLast + interval
        var span = Math.max(1, t1 - t0)
        var range = root.graphValueRange(pts, minHint, maxHint)
        var vmin = range.min
        var vmax = range.max
        var spread = vmax - vmin
        var tomorrowT = -1
        for (var j = 0; j < pts.length; ++j) {
            if (Number(pts[j].d) === 1) {
                tomorrowT = Number(pts[j].t)
                break
            }
        }
        for (var k = 0; k < pts.length; ++k) {
            var p = pts[k]
            var start = Number(p.t)
            var nextT = (k + 1 < pts.length) ? Number(pts[k + 1].t) : t1
            var x = (start - t0) / span * w
            var bw = Math.max(1, (nextT - start) / span * w - 0.5)
            var yv = (Number(p.v) - vmin) / spread
            if (yv < 0)
                yv = 0
            if (yv > 1)
                yv = 1
            var bh = Math.max(1, yv * plotH)
            ctx.globalAlpha = 0.42
            ctx.fillStyle = root.graphBarRgb(Number(p.v), vmin, vmax)
            ctx.fillRect(x, pad + plotH - bh, bw, bh)
        }
        ctx.globalAlpha = 1
        if (tomorrowT > t0) {
            var dx = (tomorrowT - t0) / span * w
            ctx.strokeStyle = "rgba(255,255,255,0.45)"
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(dx, pad)
            ctx.lineTo(dx, pad + plotH)
            ctx.stroke()
        }
        if (nowMs >= t0 && nowMs <= t1) {
            var nx = (nowMs - t0) / span * w
            ctx.strokeStyle = "rgba(255,255,255,0.9)"
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.moveTo(nx, pad)
            ctx.lineTo(nx, pad + plotH)
            ctx.stroke()
        }
    }

    function paintLineWatermark(ctx, w, h, pts, minHint, maxHint) {
        if (!pts || pts.length < 2 || w <= 0 || h <= 8)
            return
        var pad = 6
        var plotH = h - pad * 2
        var t0 = Number(pts[0].t)
        var t1 = Number(pts[pts.length - 1].t)
        var span = Math.max(1, t1 - t0)
        var range = root.graphValueRange(pts, minHint, maxHint)
        var vmin = range.min
        var vmax = range.max
        var spread = vmax - vmin
        ctx.beginPath()
        var x0 = (Number(pts[0].t) - t0) / span * w
        var yv0 = (Number(pts[0].v) - vmin) / spread
        if (yv0 < 0)
            yv0 = 0
        if (yv0 > 1)
            yv0 = 1
        var y0 = pad + plotH - yv0 * plotH
        ctx.moveTo(x0, pad + plotH)
        ctx.lineTo(x0, y0)
        for (var i = 1; i < pts.length; ++i) {
            var xi = (Number(pts[i].t) - t0) / span * w
            var yvi = (Number(pts[i].v) - vmin) / spread
            if (yvi < 0)
                yvi = 0
            if (yvi > 1)
                yvi = 1
            ctx.lineTo(xi, pad + plotH - yvi * plotH)
        }
        var xLast = (Number(pts[pts.length - 1].t) - t0) / span * w
        ctx.lineTo(xLast, pad + plotH)
        ctx.closePath()
        ctx.fillStyle = "rgba(255,255,255,0.22)"
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(x0, y0)
        for (var j = 1; j < pts.length; ++j) {
            var xj = (Number(pts[j].t) - t0) / span * w
            var yvj = (Number(pts[j].v) - vmin) / spread
            if (yvj < 0)
                yvj = 0
            if (yvj > 1)
                yvj = 1
            ctx.lineTo(xj, pad + plotH - yvj * plotH)
        }
        ctx.strokeStyle = "rgba(255,255,255,0.85)"
        ctx.lineWidth = 2
        ctx.stroke()
    }

    function formatTemp(entity) {
        if (!entity)
            return ""
        var t = Number(entity.targetTemp)
        if (!isFinite(t))
            t = Number(entity.currentTemp)
        if (!isFinite(t))
            return ""
        var step = Number(entity.tempStep) || 0.5
        var shown = step < 1
                    ? (Math.round(t / step) * step).toFixed(1).replace(/\.0$/, "")
                    : String(Math.round(t))
        return shown + (entity.tempUnit || "°")
    }

    function climateLabel(entity) {
        if (!entity || entity.on !== true)
            return "Off"
        var mode = entity.hvacMode || entity.state || ""
        var label = ""
        if (mode === "fan_only")
            label = "Fan"
        else if (mode === "heat_cool")
            label = "Heat/Cool"
        else if (mode === "off")
            return "Off"
        else if (!mode)
            label = "On"
        else
            label = mode.charAt(0).toUpperCase() + mode.slice(1)
        var temp = entity.supportsTargetTemp === true ? root.formatTemp(entity) : ""
        return temp ? (label + " · " + temp) : label
    }

    function hvacSupported(entity, mode) {
        if (!entity)
            return false
        var modes = entity.hvacModes
        if (!modes || modes.length === 0)
            return true
        for (var i = 0; i < modes.length; ++i) {
            if (modes[i] === mode)
                return true
        }
        return false
    }

    function acLevelMode(levels, level) {
        if (!levels || level < 1 || level > levels.length)
            return ""
        var mode = levels[level - 1]
        return mode ? String(mode) : ""
    }

    function acHasLevels(levels) {
        if (!levels)
            return false
        for (var i = 0; i < levels.length; ++i) {
            if (levels[i])
                return true
        }
        return false
    }

    // Repaint the card straight away; the app confirms with EntitiesChanged.
    function patchEntity(entityId, patch) {
        var next = []
        for (var i = 0; i < root.entities.length; ++i) {
            var item = root.entities[i]
            if (item.entityId !== entityId) {
                next.push(item)
                continue
            }
            var copy = {}
            for (var key in item)
                copy[key] = item[key]
            for (var field in patch)
                copy[field] = patch[field]
            next.push(copy)
        }
        root.entities = next
    }

    function toggleLight(entity) {
        if (!entity || entity.available === false)
            return
        if (entity.kind === "script" || entity.kind === "graph" || entity.kind === "sensor")
            return
        if (entity.kind === "climate") {
            var climateOn = !(entity.on === true)
            var climatePatch = { "on": climateOn }
            if (!climateOn) {
                climatePatch.state = "off"
                climatePatch.hvacMode = "off"
            }
            root.patchEntity(entity.entityId, climatePatch)
            widgetIface.call("ToggleLight", [entity.entityId])
            return
        }
        var on = !(entity.on === true)
        root.patchEntity(entity.entityId,
                         { "on": on,
                           "state": on ? "on" : "off",
                           "brightnessPct": on ? (Number(entity.brightnessPct) || 100) : 0 })
        widgetIface.call("ToggleLight", [entity.entityId])
    }

    function runScript(entity) {
        if (!entity || entity.available === false)
            return
        widgetIface.call("RunScript", [entity.entityId])
        root.scriptEntityId = ""
    }

    function cancelScript(entity) {
        if (!entity || entity.available === false)
            return
        widgetIface.call("CancelScript", [entity.entityId])
        root.scriptEntityId = ""
    }

    function activateNotification(entity) {
        if (!entity)
            return
        widgetIface.call("DismissNotification", [entity.entityId])
        widgetIface.call("OpenApp", [])
    }

    function activateCard(entity) {
        if (!entity || entity.available === false)
            return
        if (entity.kind === "notification") {
            root.activateNotification(entity)
            return
        }
        if (entity.kind === "script") {
            root.adjustEntityId = ""
            root.scriptEntityId = root.scriptEntityId === entity.entityId
                    ? ""
                    : entity.entityId
            return
        }
        if (entity.kind === "graph" || entity.kind === "sensor")
            return
        root.scriptEntityId = ""
        root.toggleLight(entity)
    }

    function setBrightness(entity, pct) {
        if (!entity || entity.available === false)
            return
        pct = Math.max(0, Math.min(100, Math.round(pct)))
        root.patchEntity(entity.entityId,
                         { "on": pct > 0,
                           "state": pct > 0 ? "on" : "off",
                           "brightnessPct": pct })
        widgetIface.call("SetBrightnessPct", [entity.entityId, pct])
    }

    function setColorTemp(entity, kelvin) {
        if (!entity || entity.available === false)
            return
        kelvin = Math.round(kelvin)
        root.patchEntity(entity.entityId,
                         { "on": true,
                           "state": "on",
                           "colorTempKelvin": kelvin,
                           "colorMode": "color_temp" })
        widgetIface.call("SetColorTempKelvin", [entity.entityId, kelvin])
    }

    function setRgbColor(entity, r, g, b) {
        if (!entity || entity.available === false)
            return
        root.patchEntity(entity.entityId,
                         { "on": true,
                           "state": "on",
                           "rgbR": r,
                           "rgbG": g,
                           "rgbB": b,
                           "colorMode": "rgb" })
        widgetIface.call("SetRgbColor", [entity.entityId, r, g, b])
    }

    function setHvacMode(entity, mode) {
        if (!entity || entity.available === false)
            return
        root.patchEntity(entity.entityId,
                         { "on": mode !== "off",
                           "state": mode,
                           "hvacMode": mode })
        widgetIface.call("SetHvacMode", [entity.entityId, mode])
    }

    function setFanLevel(entity, level) {
        if (!entity || entity.available === false)
            return
        if (level === 0) {
            if (!entity.fanAutoMode)
                return
        } else if (!root.acLevelMode(entity.fanLevels, level)) {
            return
        }
        root.patchEntity(entity.entityId,
                         { "fanLevel": level > 0 ? level : 0,
                           "fanIsAuto": level === 0,
                           "on": true })
        widgetIface.call("SetFanLevel", [entity.entityId, level])
    }

    function setVaneVertical(entity, level) {
        if (!entity || entity.available === false)
            return
        if (level === 0) {
            if (!entity.vaneVerticalAutoMode)
                return
        } else if (level < 0) {
            if (!entity.vaneVerticalSwingMode)
                return
        } else if (!root.acLevelMode(entity.vaneVerticalLevels, level)) {
            return
        }
        root.patchEntity(entity.entityId,
                         { "vaneVertical": level > 0 ? level : 0,
                           "vaneVerticalIsAuto": level === 0,
                           "vaneVerticalIsSwing": level < 0 })
        widgetIface.call("SetVaneVertical", [entity.entityId, level])
    }

    function setVaneHorizontal(entity, level) {
        if (!entity || entity.available === false)
            return
        if (level === 0) {
            if (!entity.vaneHorizontalAutoMode)
                return
        } else if (level < 0) {
            if (!entity.vaneHorizontalSwingMode)
                return
        } else if (!root.acLevelMode(entity.vaneHorizontalLevels, level)) {
            return
        }
        root.patchEntity(entity.entityId,
                         { "vaneHorizontal": level > 0 ? level : 0,
                           "vaneHorizontalIsAuto": level === 0,
                           "vaneHorizontalIsSwing": level < 0 })
        widgetIface.call("SetVaneHorizontal", [entity.entityId, level])
    }

    function setTargetTemp(entity, temp) {
        if (!entity || entity.available === false)
            return
        if (entity.supportsTargetTemp !== true)
            return
        var minT = Number(entity.minTemp)
        var maxT = Number(entity.maxTemp)
        temp = Number(temp)
        if (!isFinite(temp))
            return
        if (isFinite(minT) && isFinite(maxT) && maxT > minT)
            temp = Math.max(minT, Math.min(maxT, temp))
        root.patchEntity(entity.entityId,
                         { "targetTemp": temp, "on": true })
        widgetIface.call("SetTargetTemp", [entity.entityId, temp + 0.0])
    }

    function colorSwatchSelected(entity, swatch) {
        if (!entity || entity.colorMode === "color_temp")
            return false
        var er = Number(entity.rgbR)
        var eg = Number(entity.rgbG)
        var eb = Number(entity.rgbB)
        if (er < 0 || eg < 0 || eb < 0)
            return false
        return Math.abs(er - swatch.r) < 40
                && Math.abs(eg - swatch.g) < 40
                && Math.abs(eb - swatch.b) < 40
    }

    function hasAdjusters(entity) {
        if (!entity || entity.kind === "script" || entity.kind === "notification"
                || entity.kind === "graph" || entity.kind === "sensor")
            return false
        return entity.dimmable === true
                || entity.supportsColor === true
                || entity.supportsColorTemp === true
                || entity.kind === "climate"
    }

    function favoriteIndexOf(entityId) {
        var favs = root.favoriteEntities
        for (var i = 0; i < favs.length; ++i) {
            if (favs[i].entityId === entityId)
                return i
        }
        return -1
    }

    function beginDrag(entity, cardItem) {
        if (!entity || !entity.entityId || root.dragging)
            return
        root.adjustEntityId = ""
        root.scriptEntityId = ""
        root.dragEntityId = entity.entityId
        root.dragIsNotification = entity.kind === "notification"
        root.dragFromIndex = root.dragIsNotification ? -1 : root.favoriteIndexOf(entity.entityId)
        root.dragInsertIndex = root.dragFromIndex
        root.dragCardHeight = cardItem ? Math.max(cardItem.height, Theme.itemSizeSmall)
                                       : Theme.itemSizeLarge
        root.dragName = entity.name || entity.entityId
        root.dragBody = root.stateLabel(entity)
        root.dragColor = (entity.kind === "notification" && entity.color)
                         ? entity.color : "#03A9F4"
        root.dragOverTrash = false
    }

    function updateDrag(rootX, rootY) {
        if (!root.dragging)
            return
        root.dragY = Math.max(0, rootY - root.dragCardHeight / 2)
        var trash = trashBin.mapToItem(root, 0, 0)
        root.dragOverTrash = trashBin.height > 0
                && rootY >= trash.y
                && rootY <= trash.y + trashBin.height
        if (root.dragIsNotification || root.dragOverTrash)
            return
        var pointerY = column.mapFromItem(root, rootX, rootY).y
        var insert = root.favoriteEntities.length
        var favIdx = 0
        for (var i = 0; i < cardRepeater.count; ++i) {
            var item = cardRepeater.itemAt(i)
            if (!item || item.isNotification)
                continue
            if (item.entity && item.entity.entityId === root.dragEntityId) {
                favIdx += 1
                continue
            }
            var visualMid = item.y + item.dragShift + item.height / 2
            if (pointerY < visualMid) {
                insert = favIdx
                break
            }
            favIdx += 1
        }
        root.dragInsertIndex = insert
    }

    function endDrag() {
        if (!root.dragging)
            return
        var entityId = root.dragEntityId
        var isNotif = root.dragIsNotification
        var from = root.dragFromIndex
        var to = root.dragInsertIndex
        var overTrash = root.dragOverTrash
        root.dragEntityId = ""
        root.dragOverTrash = false
        root.dragFromIndex = -1
        root.dragInsertIndex = -1
        if (overTrash) {
            if (isNotif)
                widgetIface.call("DismissNotification", [entityId])
            else
                root.removeFavorite(entityId)
            return
        }
        if (isNotif || from < 0)
            return
        if (to > from)
            to -= 1
        if (to === from || to < 0)
            return
        root.moveFavorite(entityId, to)
    }

    function cancelDrag() {
        root.dragEntityId = ""
        root.dragOverTrash = false
        root.dragFromIndex = -1
        root.dragInsertIndex = -1
    }

    function removeFavorite(entityId) {
        var next = []
        var src = root.entities || []
        for (var i = 0; i < src.length; ++i) {
            if (src[i] && src[i].entityId !== entityId)
                next.push(src[i])
        }
        root.entities = next
        widgetIface.call("RemoveEventsViewEntity", [entityId])
    }

    function moveFavorite(entityId, destIndex) {
        var notifs = root.notificationEntities
        var favs = []
        var src = root.favoriteEntities
        var moving = null
        for (var i = 0; i < src.length; ++i) {
            if (src[i].entityId === entityId)
                moving = src[i]
            else
                favs.push(src[i])
        }
        if (!moving)
            return
        if (destIndex < 0)
            destIndex = 0
        if (destIndex > favs.length)
            destIndex = favs.length
        favs.splice(destIndex, 0, moving)
        root.entities = notifs.concat(favs)
        widgetIface.call("ReorderEventsViewEntity", [entityId, destIndex])
    }

    function toggleAdjusters(entity) {
        if (!entity || entity.available === false || !root.hasAdjusters(entity))
            return
        root.scriptEntityId = ""
        root.adjustEntityId = root.adjustEntityId === entity.entityId
                ? ""
                : entity.entityId
    }

    function pingWidgetPresent() {
        widgetIface.call("WidgetPresent", [])
    }

    function refresh() {
        // Replacing the model rebuilds the delegates, which would fight a drag.
        if (!root.active || root.adjustingSlider || root.scriptEntityId.length > 0
                || root.dragging)
            return
        root.pingWidgetPresent()
        widgetIface.call("Refresh", [])
        widgetIface.call("GetEntitiesJson", [],
                         function(result) { root.parseEntities(result) },
                         function() {
                             root.appRunning = false
                             root.entities = []
                             root.errorText = "Helmsman must be running to show the widget"
                         })
    }

    function reload() {
        refresh()
    }

    function save() {
    }

    Component.onCompleted: {
        root.pingWidgetPresent()
        if (active)
            refresh()
    }
    Component.onDestruction: widgetIface.call("WidgetGone", [])
    onActiveChanged: {
        if (active) {
            refresh()
        } else {
            root.adjustEntityId = ""
            root.scriptEntityId = ""
        }
    }

    Timer {
        id: presenceTimer
        interval: 8000
        repeat: true
        running: true
        onTriggered: root.pingWidgetPresent()
    }

    Timer {
        id: refreshTimer
        interval: 8000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    DBusInterface {
        id: widgetIface
        service: "org.helmsman.harbour-helmsman"
        path: "/widget"
        iface: "org.helmsman.Widget"
        signalsEnabled: root.active
        // Nemo.DBus maps the D-Bus signal EntitiesChanged to a lowercase-initial handler.
        function entitiesChanged() {
            root.refresh()
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            text: "Helmsman"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeMedium
            font.family: Theme.fontFamilyHeading
            truncationMode: TruncationMode.Fade
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: root.favoriteEntities.length === 0
                     && root.notificationEntities.length === 0
            text: {
                if (!root.appRunning)
                    return "Helmsman must be running to show the widget"
                if (root.errorText.length > 0)
                    return root.errorText
                return "No favorites selected yet."
            }
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.Wrap
        }

        Repeater {
            id: cardRepeater
            model: root.visibleEntities

            delegate: Item {
                id: card

                property bool dimmable: modelData.dimmable === true
                property bool available: modelData.available !== false
                property bool isScript: modelData.kind === "script"
                property bool isClimate: modelData.kind === "climate"
                property bool isNotification: modelData.kind === "notification"
                property bool isGraph: modelData.kind === "graph"
                property bool isSensor: modelData.kind === "sensor"
                property int favoriteIndex: {
                    if (card.isNotification)
                        return -1
                    var favs = root.favoriteEntities
                    var id = modelData.entityId
                    for (var i = 0; i < favs.length; ++i) {
                        if (favs[i].entityId === id)
                            return i
                    }
                    return -1
                }
                property bool showFavorite: card.isNotification
                                            || root.expanded
                                            || root.dragging
                                            || card.favoriteIndex < root.collapsedCount
                property real dragShift: {
                    if (!root.dragging || root.dragIsNotification || card.isNotification)
                        return 0
                    if (root.dragOverTrash)
                        return 0
                    var from = root.dragFromIndex
                    var to = root.dragInsertIndex
                    var idx = card.favoriteIndex
                    if (idx < 0 || idx === from)
                        return 0
                    var h = root.dragCardHeight + Theme.paddingSmall
                    if (from < to && idx > from && idx < to)
                        return -h
                    if (from > to && idx >= to && idx < from)
                        return h
                    return 0
                }
                property var entity: modelData
                property bool supportsColor: modelData.supportsColor === true
                property bool supportsColorTemp: modelData.supportsColorTemp === true
                property bool hasAdjusters: !card.isNotification && !card.isGraph && !card.isSensor
                                            && (card.dimmable
                                                || card.supportsColor
                                                || card.supportsColorTemp
                                                || card.isClimate)
                property bool hasWatermarkGraph: {
                    if (card.isGraph && modelData.graphPoints && modelData.graphPoints.length > 1)
                        return true
                    if (card.isSensor && modelData.historyPoints && modelData.historyPoints.length > 1)
                        return true
                    return false
                }
                property bool showAdjusters: card.hasAdjusters
                                             && card.available
                                             && root.adjustEntityId === modelData.entityId
                property bool showScriptActions: card.isScript
                                                 && card.available
                                                 && root.scriptEntityId === modelData.entityId
                property var colorChoices: {
                    var list = []
                    var src = root.colorSwatches
                    for (var i = 0; i < src.length; ++i)
                        list.push(src[i])
                    if (!card.supportsColorTemp)
                        list.push({ "r": 255, "g": 255, "b": 255 })
                    return list
                }
                property int swatchSize: {
                    var n = card.colorChoices.length
                    var gap = Theme.paddingSmall
                    if (n <= 0)
                        return Theme.iconSizeSmall
                    return Math.max(Theme.iconSizeSmall,
                                    Math.floor((cardColumn.width - (n - 1) * gap) / n))
                }
                property int acCellSize: {
                    var n = 5
                    var gap = Theme.paddingSmall
                    return Math.max(Theme.iconSizeMedium,
                                    Math.floor((cardColumn.width - (n - 1) * gap) / n))
                }
                property int acFanCellCount: (card.entity.fanAutoMode ? 1 : 0) + 5
                property int acFanCellSize: {
                    var n = Math.max(1, card.acFanCellCount)
                    var gap = Theme.paddingSmall
                    return Math.max(Theme.iconSizeSmall,
                                    Math.floor((cardColumn.width - (n - 1) * gap) / n))
                }
                property var hvacChoices: {
                    var all = [
                        { "id": "cool", "label": "Cool" },
                        { "id": "heat", "label": "Heat" },
                        { "id": "dry", "label": "Dry" },
                        { "id": "fan_only", "label": "Fan" }
                    ]
                    var out = []
                    for (var i = 0; i < all.length; ++i) {
                        if (root.hvacSupported(card.entity, all[i].id))
                            out.push(all[i])
                    }
                    return out
                }

                x: Theme.horizontalPageMargin
                width: column.width - 2 * Theme.horizontalPageMargin
                visible: card.showFavorite
                height: card.showFavorite
                        ? Math.max(cardColumn.height + 2 * Theme.paddingMedium,
                                   ((card.isGraph || card.isSensor) ? Theme.itemSizeLarge : 0)
                                   + 2 * Theme.paddingMedium)
                        : 0
                clip: true
                opacity: (root.dragging && root.dragEntityId === modelData.entityId) ? 0.35 : 1
                z: (root.dragging && root.dragEntityId === modelData.entityId) ? 2 : 0
                transform: Translate {
                    y: card.dragShift
                    Behavior on y { NumberAnimation { duration: 120 } }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingMedium
                    color: card.isNotification
                           ? (modelData.color && String(modelData.color).length > 0
                              ? modelData.color : "#03A9F4")
                           : "#03A9F4"
                    opacity: tapArea.pressed
                             ? 0.5
                             : (card.isNotification
                                ? 0.72
                                : ((card.isGraph || card.isSensor
                                    || (card.isScript ? card.showScriptActions
                                                      : modelData.on === true)) ? 0.32 : 0.16))
                }

                // Graph watermark (history or today/tomorrow series) plus the
                // MDI icon when there is no series to draw.
                Item {
                    anchors.fill: parent
                    clip: true

                    Canvas {
                        id: graphCanvas
                        anchors.fill: parent
                        visible: card.hasWatermarkGraph
                        antialiasing: true
                        renderStrategy: Canvas.Immediate
                        property var barPoints: modelData.graphPoints || []
                        property var linePoints: modelData.historyPoints || []
                        property real barMin: Number(modelData.graphMin)
                        property real barMax: Number(modelData.graphMax)
                        property real lineMin: Number(modelData.historyMin)
                        property real lineMax: Number(modelData.historyMax)
                        property real nowMs: Date.now()
                        property bool useBars: card.isGraph

                        onBarPointsChanged: requestPaint()
                        onLinePointsChanged: requestPaint()
                        onBarMinChanged: requestPaint()
                        onBarMaxChanged: requestPaint()
                        onLineMinChanged: requestPaint()
                        onLineMaxChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()

                        Timer {
                            interval: 60000
                            running: graphCanvas.visible && root.active
                            repeat: true
                            onTriggered: {
                                graphCanvas.nowMs = Date.now()
                                graphCanvas.requestPaint()
                            }
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            if (graphCanvas.useBars)
                                root.paintBarWatermark(ctx, graphCanvas.width, graphCanvas.height,
                                                       graphCanvas.barPoints, graphCanvas.barMin,
                                                       graphCanvas.barMax, graphCanvas.nowMs)
                            else
                                root.paintLineWatermark(ctx, graphCanvas.width, graphCanvas.height,
                                                        graphCanvas.linePoints, graphCanvas.lineMin,
                                                        graphCanvas.lineMax)
                        }
                    }

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.right
                        height: parent.height - 2 * Theme.paddingSmall
                        width: height
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        opacity: (card.isGraph || card.isSensor || card.isNotification || card.isScript
                                  ? card.showScriptActions || card.isNotification || card.isGraph || card.isSensor
                                  : modelData.on === true) ? 0.34 : 0.22
                        visible: !card.hasWatermarkGraph && status === Image.Ready
                        source: modelData.iconPath
                                ? "file://" + modelData.iconPath
                                : ""
                    }
                }

                Column {
                    id: cardColumn

                    x: Theme.paddingLarge
                    y: Theme.paddingMedium
                    width: parent.width - 2 * Theme.paddingLarge
                    spacing: Theme.paddingSmall

                    // Only the labels toggle, so the slider below keeps its drags.
                    MouseArea {
                        id: tapArea

                        width: parent.width
                        height: (card.isGraph || card.isSensor)
                                ? Math.max(labels.height, Theme.itemSizeLarge)
                                : labels.height
                        enabled: true
                        preventStealing: drag.active || (root.dragging
                                         && root.dragEntityId === modelData.entityId)
                        drag.target: (card.showAdjusters || card.showScriptActions)
                                     ? null : dragDummy
                        drag.axis: Drag.YAxis
                        drag.threshold: Theme.paddingLarge

                        Item {
                            id: dragDummy
                            width: 1
                            height: 1
                            visible: false
                        }

                        onClicked: {
                            if (drag.active || root.dragging)
                                return
                            if (card.available)
                                root.activateCard(modelData)
                        }
                        onPressAndHold: {
                            if (drag.active || root.dragging)
                                return
                            root.toggleAdjusters(modelData)
                        }
                        onPositionChanged: {
                            if (!pressed || card.showAdjusters || card.showScriptActions)
                                return
                            if (drag.active && !root.dragging)
                                root.beginDrag(modelData, card)
                            if (root.dragging && root.dragEntityId === modelData.entityId) {
                                var p = tapArea.mapToItem(root, mouse.x, mouse.y)
                                root.updateDrag(p.x, p.y)
                            }
                        }
                        onReleased: {
                            if (root.dragging && root.dragEntityId === modelData.entityId)
                                root.endDrag()
                            dragDummy.x = 0
                            dragDummy.y = 0
                        }
                        onCanceled: {
                            if (root.dragging && root.dragEntityId === modelData.entityId)
                                root.cancelDrag()
                            dragDummy.x = 0
                            dragDummy.y = 0
                        }

                            Column {
                                id: labels
                                width: parent.width

                            Row {
                                width: parent.width
                                spacing: Theme.paddingSmall

                                Label {
                                    width: parent.width - grip.width - parent.spacing
                                    truncationMode: TruncationMode.Fade
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.bold: !card.isScript && (card.isNotification || card.isGraph || card.isSensor || modelData.on === true)
                                    text: modelData.name || modelData.entityId
                                }

                                Column {
                                    id: grip
                                    width: Theme.paddingLarge
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    opacity: 0.7

                                    Repeater {
                                        model: 3
                                        Rectangle {
                                            width: grip.width
                                            height: 2
                                            radius: 1
                                            color: Theme.secondaryColor
                                        }
                                    }
                                }
                            }

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                visible: labelText.length > 0
                                property string labelText: {
                                    if (card.isNotification)
                                        return root.stateLabel(modelData)
                                    if (card.isScript) {
                                        if (!card.available)
                                            return root.stateLabel(modelData)
                                        return card.showScriptActions
                                                ? ""
                                                : "Tap for Run or Cancel"
                                    }
                                    if (card.hasAdjusters && card.available && !card.showAdjusters)
                                        return root.stateLabel(modelData) + " · hold to adjust"
                                    return root.stateLabel(modelData)
                                }
                                text: labelText
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.paddingMedium
                        visible: card.showScriptActions

                        Button {
                            width: (parent.width - parent.spacing) / 2
                            text: "Run"
                            onClicked: root.runScript(modelData)
                        }

                        Button {
                            width: (parent.width - parent.spacing) / 2
                            text: "Cancel"
                            onClicked: root.cancelScript(modelData)
                        }
                    }

                    Slider {
                        id: dimmer

                        width: parent.width
                        visible: card.showAdjusters && card.dimmable
                        minimumValue: 0
                        maximumValue: 100
                        stepSize: 1
                        valueText: Math.round(value) + "%"
                        label: "Brightness"

                        Binding {
                            target: dimmer
                            property: "value"
                            value: Number(modelData.brightnessPct) || 0
                            when: !dimmer.down
                        }

                        onDownChanged: {
                            root.adjustingSlider = down
                            if (!down)
                                root.setBrightness(modelData, dimmer.value)
                        }
                    }

                    Slider {
                        id: temperature

                        width: parent.width
                        visible: card.showAdjusters && card.supportsColorTemp
                        minimumValue: Number(modelData.minKelvin) || 2000
                        maximumValue: Number(modelData.maxKelvin) || 6500
                        stepSize: 50
                        valueText: Math.round(value) + " K"
                        label: "Temperature"

                        Binding {
                            target: temperature
                            property: "value"
                            value: {
                                var k = Number(modelData.colorTempKelvin) || 0
                                if (k <= 0)
                                    return (temperature.minimumValue + temperature.maximumValue) / 2
                                return k
                            }
                            when: !temperature.down
                        }

                        onDownChanged: {
                            root.adjustingSlider = down
                            if (!down)
                                root.setColorTemp(modelData, temperature.value)
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall
                        visible: card.showAdjusters && card.supportsColor

                        Label {
                            width: parent.width
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Color"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall

                            Repeater {
                                model: card.colorChoices
                                delegate: Rectangle {
                                    width: card.swatchSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    color: Qt.rgba(modelData.r / 255,
                                                   modelData.g / 255,
                                                   modelData.b / 255, 1)
                                    property bool selected: root.colorSwatchSelected(card.entity, modelData)
                                    property bool isWhite: modelData.r === 255
                                                           && modelData.g === 255
                                                           && modelData.b === 255
                                    border.width: selected ? 3 : (isWhite ? 1 : 0)
                                    border.color: selected
                                                  ? (isWhite ? "#222222" : "#FFFFFF")
                                                  : "#80FFFFFF"

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setRgbColor(card.entity,
                                                                    modelData.r,
                                                                    modelData.g,
                                                                    modelData.b)
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall
                        visible: card.showAdjusters && card.isClimate

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: card.hvacChoices.length > 0

                            Repeater {
                                model: card.hvacChoices
                                delegate: Rectangle {
                                    width: card.hvacChoices.length > 0
                                           ? (parent.width - (card.hvacChoices.length - 1) * parent.spacing)
                                             / card.hvacChoices.length
                                           : parent.width
                                    height: Theme.itemSizeExtraSmall
                                    radius: Theme.paddingSmall
                                    color: (card.entity.hvacMode === modelData.id)
                                           ? "#73FFFFFF" : "#28FFFFFF"

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setHvacMode(card.entity, modelData.id)
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        color: Theme.primaryColor
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        font.bold: card.entity.hvacMode === modelData.id
                                        text: modelData.label
                                    }
                                }
                            }
                        }

                        Slider {
                            id: climateTemp

                            width: parent.width
                            visible: card.entity.supportsTargetTemp === true
                            minimumValue: Number(card.entity.minTemp) || 16
                            maximumValue: Number(card.entity.maxTemp) || 30
                            stepSize: Number(card.entity.tempStep) || 0.5
                            label: "Temperature"
                            valueText: {
                                var step = Number(card.entity.tempStep) || 0.5
                                var shown = step < 1
                                            ? Number(value).toFixed(1)
                                            : String(Math.round(value))
                                return shown + (card.entity.tempUnit || "°")
                            }

                            Binding {
                                target: climateTemp
                                property: "value"
                                value: {
                                    var t = Number(card.entity.targetTemp)
                                    if (!isFinite(t))
                                        t = Number(card.entity.currentTemp)
                                    if (!isFinite(t))
                                        return (climateTemp.minimumValue + climateTemp.maximumValue) / 2
                                    return t
                                }
                                when: !climateTemp.down
                            }

                            onDownChanged: {
                                root.adjustingSlider = down
                                if (!down)
                                    root.setTargetTemp(card.entity, climateTemp.value)
                            }
                        }

                        Label {
                            width: parent.width
                            visible: card.entity.supportsFan === true
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Fan"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: card.entity.supportsFan === true

                            Rectangle {
                                visible: !!card.entity.fanAutoMode
                                width: card.acFanCellSize
                                height: width
                                radius: Theme.paddingSmall
                                property bool selected: card.entity.fanIsAuto === true
                                color: selected ? "#73FFFFFF" : "#28FFFFFF"

                                Label {
                                    anchors.fill: parent
                                    anchors.margins: Theme.paddingSmall / 2
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    wrapMode: Text.Wrap
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    font.bold: parent.selected
                                    text: "Auto"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.setFanLevel(card.entity, 0)
                                }
                            }

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: card.acFanCellSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    property int level: index + 1
                                    property bool enabledLevel: root.acLevelMode(card.entity.fanLevels, level).length > 0
                                    property bool selected: card.entity.fanIsAuto !== true
                                                            && Number(card.entity.fanLevel) === level
                                    color: selected ? "#73FFFFFF" : "#28FFFFFF"
                                    opacity: enabledLevel ? 1 : 0.35

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: width * 0.16
                                        property int barCount: level
                                        Repeater {
                                            model: 5
                                            Rectangle {
                                                width: Math.max(2, Math.round(parent.width * 0.12))
                                                height: parent.height * (0.3 + index * 0.14)
                                                x: index * (parent.width / 5)
                                                y: parent.height - height
                                                radius: 1
                                                color: "#FFFFFF"
                                                opacity: index < parent.barCount ? 1 : 0.22
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: enabledLevel
                                        onClicked: root.setFanLevel(card.entity, level)
                                    }
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            visible: card.entity.supportsVaneVertical === true
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Vertical vanes"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: !!card.entity.vaneVerticalAutoMode
                                     || !!card.entity.vaneVerticalSwingMode
                            property int chipCount: (card.entity.vaneVerticalAutoMode ? 1 : 0)
                                                    + (card.entity.vaneVerticalSwingMode ? 1 : 0)
                            property int chipWidth: {
                                var n = Math.max(chipCount, 2)
                                return Math.floor((width - (n - 1) * spacing) / n)
                            }

                            Rectangle {
                                visible: !!card.entity.vaneVerticalAutoMode
                                width: parent.chipWidth
                                height: Theme.itemSizeExtraSmall
                                radius: Theme.paddingSmall
                                property bool selected: card.entity.vaneVerticalIsAuto === true
                                color: selected ? "#73FFFFFF" : "#28FFFFFF"

                                Label {
                                    anchors.centerIn: parent
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    font.bold: parent.selected
                                    text: "Auto"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.setVaneVertical(card.entity, 0)
                                }
                            }

                            Rectangle {
                                visible: !!card.entity.vaneVerticalSwingMode
                                width: parent.chipWidth
                                height: Theme.itemSizeExtraSmall
                                radius: Theme.paddingSmall
                                property bool selected: card.entity.vaneVerticalIsSwing === true
                                color: selected ? "#73FFFFFF" : "#28FFFFFF"

                                Label {
                                    anchors.centerIn: parent
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    font.bold: parent.selected
                                    text: "Swing"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.setVaneVertical(card.entity, -1)
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: root.acHasLevels(card.entity.vaneVerticalLevels)

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: card.acCellSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    property int level: index + 1
                                    property bool enabledLevel: root.acLevelMode(card.entity.vaneVerticalLevels, level).length > 0
                                    property bool selected: card.entity.vaneVerticalIsAuto !== true
                                                            && card.entity.vaneVerticalIsSwing !== true
                                                            && Number(card.entity.vaneVertical) === level
                                    property real vaneAngle: -50 + (level - 1) * 25
                                    color: selected ? "#73FFFFFF" : "#28FFFFFF"
                                    opacity: enabledLevel ? 1 : 0.35

                                    Item {
                                        anchors.fill: parent
                                        property real angle: vaneAngle
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: parent.width * 0.7
                                                height: Math.max(2, Math.round(parent.height * 0.07))
                                                radius: height / 2
                                                color: "#FFFFFF"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: parent.height * 0.22 + index * parent.height * 0.2
                                                rotation: parent.angle
                                                transformOrigin: Item.Center
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: enabledLevel
                                        onClicked: root.setVaneVertical(card.entity, level)
                                    }
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            visible: card.entity.supportsVaneHorizontal === true
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Horizontal vanes"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: !!card.entity.vaneHorizontalAutoMode
                                     || !!card.entity.vaneHorizontalSwingMode
                            property int chipCount: (card.entity.vaneHorizontalAutoMode ? 1 : 0)
                                                    + (card.entity.vaneHorizontalSwingMode ? 1 : 0)
                            property int chipWidth: {
                                var n = Math.max(chipCount, 2)
                                return Math.floor((width - (n - 1) * spacing) / n)
                            }

                            Rectangle {
                                visible: !!card.entity.vaneHorizontalAutoMode
                                width: parent.chipWidth
                                height: Theme.itemSizeExtraSmall
                                radius: Theme.paddingSmall
                                property bool selected: card.entity.vaneHorizontalIsAuto === true
                                color: selected ? "#73FFFFFF" : "#28FFFFFF"

                                Label {
                                    anchors.centerIn: parent
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    font.bold: parent.selected
                                    text: "Auto"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.setVaneHorizontal(card.entity, 0)
                                }
                            }

                            Rectangle {
                                visible: !!card.entity.vaneHorizontalSwingMode
                                width: parent.chipWidth
                                height: Theme.itemSizeExtraSmall
                                radius: Theme.paddingSmall
                                property bool selected: card.entity.vaneHorizontalIsSwing === true
                                color: selected ? "#73FFFFFF" : "#28FFFFFF"

                                Label {
                                    anchors.centerIn: parent
                                    color: Theme.primaryColor
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    font.bold: parent.selected
                                    text: "Swing"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.setVaneHorizontal(card.entity, -1)
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: root.acHasLevels(card.entity.vaneHorizontalLevels)

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: card.acCellSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    property int level: index + 1
                                    property bool enabledLevel: root.acLevelMode(card.entity.vaneHorizontalLevels, level).length > 0
                                    property bool selected: card.entity.vaneHorizontalIsAuto !== true
                                                            && card.entity.vaneHorizontalIsSwing !== true
                                                            && Number(card.entity.vaneHorizontal) === level
                                    property real vaneAngle: -50 + (level - 1) * 25
                                    color: selected ? "#73FFFFFF" : "#28FFFFFF"
                                    opacity: enabledLevel ? 1 : 0.35

                                    Item {
                                        anchors.fill: parent
                                        property real angle: vaneAngle
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: Math.max(2, Math.round(parent.width * 0.08))
                                                height: parent.height * 0.62
                                                radius: width / 2
                                                color: "#FFFFFF"
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: parent.width * 0.22 + index * parent.width * 0.22
                                                rotation: parent.angle
                                                transformOrigin: Item.Center
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: enabledLevel
                                        onClicked: root.setVaneHorizontal(card.entity, level)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        BackgroundItem {
            id: chooseFavorites

            width: parent.width
            height: Theme.itemSizeExtraSmall
            visible: root.appRunning && root.favoriteEntities.length === 0
                     && root.errorText.length === 0
            onClicked: widgetIface.call("OpenFavorites", [])

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                color: chooseFavorites.highlighted ? Theme.highlightColor : Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Choose favorites"
            }
        }

        BackgroundItem {
            id: showMore

            width: parent.width
            height: Theme.itemSizeExtraSmall
            visible: !root.dragging && root.favoriteEntities.length > root.collapsedCount
            onClicked: root.expanded = !root.expanded

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                color: showMore.highlighted ? Theme.highlightColor : Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: root.expanded
                      ? "Show less"
                      : ("Show more (" + (root.favoriteEntities.length - root.collapsedCount) + ")")
            }
        }

        Item {
            id: trashBin
            width: parent.width
            height: visible ? (root.dragging ? Theme.itemSizeLarge : Theme.itemSizeMedium)
                            : 0
            visible: root.appRunning
                     && (root.favoriteEntities.length > 0
                         || root.notificationEntities.length > 0)

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 2 * Theme.horizontalPageMargin,
                                root.dragging ? Theme.itemSizeLarge * 2.2
                                              : Theme.itemSizeLarge * 1.6)
                height: root.dragging ? Theme.itemSizeMedium : Theme.itemSizeSmall
                radius: height / 2
                color: root.dragOverTrash ? "#C62828" : "#40FFFFFF"

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.paddingSmall

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-delete"
                        sourceSize.width: Theme.iconSizeSmall
                        sourceSize.height: Theme.iconSizeSmall
                        opacity: 0.9
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.dragging
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: root.dragOverTrash ? "Release to remove" : "Drop here to remove"
                    }
                }
            }
        }
    }

    Item {
        id: dragProxy
        visible: root.dragging
        z: 100
        x: Theme.horizontalPageMargin
        y: root.dragY
        width: column.width - 2 * Theme.horizontalPageMargin
        height: Math.max(root.dragCardHeight, Theme.itemSizeSmall)
        opacity: root.dragOverTrash ? 0.45 : 0.92

        Rectangle {
            anchors.fill: parent
            radius: Theme.paddingMedium
            color: root.dragColor
            opacity: root.dragIsNotification ? 0.72 : 0.4
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.paddingLarge
            spacing: Theme.paddingSmall

            Label {
                width: parent.width
                truncationMode: TruncationMode.Fade
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                text: root.dragName
            }

            Label {
                width: parent.width
                visible: root.dragBody.length > 0
                truncationMode: TruncationMode.Fade
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: root.dragBody
            }
        }
    }
}
