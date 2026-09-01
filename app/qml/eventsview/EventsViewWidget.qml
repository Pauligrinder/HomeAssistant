import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root
    property var entities: []
    property string statusText: ""

    width: parent ? parent.width : Screen.width
    implicitWidth: width
    implicitHeight: visible ? column.height : 0
    height: implicitHeight
    visible: (entities && entities.length > 0) || statusText.length > 0

    function stateLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        if (entity.kind === "script")
            return ""
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
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: root.statusText.length > 0 && (!root.entities || root.entities.length === 0)
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            text: root.statusText
        }

        Repeater {
            model: root.entities || []
            delegate: Column {
                x: Theme.horizontalPageMargin
                width: column.width - 2 * x

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: modelData.kind !== "script"
                               && (modelData.kind === "graph"
                                   || modelData.kind === "sensor"
                                   || modelData.on === true)
                    text: modelData.name || modelData.entityId
                }

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    visible: text.length > 0
                    text: root.stateLabel(modelData)
                }
            }
        }
    }
}
