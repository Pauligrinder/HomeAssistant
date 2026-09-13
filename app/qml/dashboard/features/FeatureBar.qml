import QtQuick 2.6
import Sailfish.Silica 1.0

Column {
    id: bar
    property var features: []
    property string entityId: ""
    property var dashboard
    property var mdiIcons
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingSmall
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Repeater {
        model: bar.features
        Loader {
            width: bar.width
            sourceComponent: bar.componentFor(modelData)
            onLoaded: {
                if (!item)
                    return
                item.feature = modelData
                item.entityId = Qt.binding(function() { return bar.entityId })
                item.dashboard = Qt.binding(function() { return bar.dashboard })
            }
        }
    }

    function componentFor(feature) {
        var t = feature && feature.type ? String(feature.type) : ""
        if (t === "toggle" || t === "humidifier-toggle")
            return toggleComp
        if (t === "light-brightness")
            return brightnessComp
        if (t === "target-temperature" || t === "numeric-input" || t === "target-humidity")
            return numericComp
        if (t === "climate-hvac-modes" || t === "alarm-modes" || t === "climate-preset-modes"
                || t === "fan-preset-modes" || t === "humidifier-modes"
                || t === "water-heater-operation-modes")
            return modesComp
        if (t === "cover-open-close" || t === "lock-commands" || t === "valve-open-close"
                || t === "update-actions" || t === "button")
            return buttonsComp
        if (t === "cover-position" || t === "cover-tilt-position" || t === "fan-speed"
                || t === "media-player-volume" || t === "valve-position" || t === "bar-gauge")
            return sliderComp
        if (t === "light-favorite-colors" || t === "light-color")
            return colorsComp
        if (t === "light-color-temp")
            return colorTempComp
        return genericComp
    }

    Component {
        id: toggleComp
        TextSwitch {
            property var feature
            property string entityId
            property var dashboard
            text: "On"
            automaticCheck: false
            checked: (dashboard && bar.rev >= 0) ? dashboard.isOn(entityId) : false
            onClicked: if (dashboard) dashboard.toggle(entityId)
        }
    }

    Component {
        id: brightnessComp
        Slider {
            property var feature
            property string entityId
            property var dashboard
            width: parent.width
            minimumValue: 0
            maximumValue: 100
            value: {
                var b = (dashboard && bar.rev >= 0) ? Number(dashboard.attribute(entityId, "brightness")) : 0
                return b ? Math.round(b * 100 / 255) : 0
            }
            label: "Brightness"
            onReleased: {
                if (dashboard)
                    dashboard.callService("light", "turn_on",
                                          { "brightness_pct": Math.round(value) }, entityId)
            }
        }
    }

    Component {
        id: numericComp
        Row {
            property var feature
            property string entityId
            property var dashboard
            spacing: Theme.paddingSmall
            function attrName() {
                var t = feature && feature.type ? feature.type : ""
                if (t === "target-humidity")
                    return "humidity"
                return "temperature"
            }
            function current() {
                return (dashboard && bar.rev >= 0) ? Number(dashboard.attribute(entityId, attrName())) : 0
            }
            Button {
                text: "−"
                onClicked: {
                    var domain = dashboard.domainOf(entityId)
                    var service = attrName() === "humidity" ? "set_humidity" : "set_temperature"
                    var data = {}
                    data[attrName()] = current() - 1
                    dashboard.callService(domain, service, data, entityId)
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: String(current())
            }
            Button {
                text: "+"
                onClicked: {
                    var domain = dashboard.domainOf(entityId)
                    var service = attrName() === "humidity" ? "set_humidity" : "set_temperature"
                    var data = {}
                    data[attrName()] = current() + 1
                    dashboard.callService(domain, service, data, entityId)
                }
            }
        }
    }

    Component {
        id: modesComp
        Flow {
            property var feature
            property string entityId
            property var dashboard
            width: parent ? parent.width : Screen.width
            spacing: Theme.paddingSmall
            property var modes: {
                if (feature && feature.modes)
                    return feature.modes
                var t = feature && feature.type ? feature.type : ""
                var key = "hvac_modes"
                if (t === "alarm-modes")
                    key = "supported_features"
                if (t === "climate-preset-modes")
                    key = "preset_modes"
                if (t === "fan-preset-modes")
                    key = "preset_modes"
                if (t === "humidifier-modes")
                    key = "available_modes"
                if (t === "water-heater-operation-modes")
                    key = "operation_list"
                var v = (dashboard && bar.rev >= 0) ? dashboard.attribute(entityId, key) : []
                return v || []
            }
            Repeater {
                model: parent.modes
                Button {
                    text: String(modelData).replace(/_/g, " ")
                    onClicked: {
                        var t = feature.type
                        if (t === "alarm-modes") {
                            if (modelData === "disarmed")
                                dashboard.callService("alarm_control_panel", "alarm_disarm", {}, entityId)
                            else
                                dashboard.callService("alarm_control_panel",
                                                      "alarm_arm_" + String(modelData).replace("armed_", ""),
                                                      {}, entityId)
                            return
                        }
                        var domain = dashboard.domainOf(entityId)
                        var service = "set_hvac_mode"
                        var data = { "hvac_mode": String(modelData) }
                        if (t === "climate-preset-modes") {
                            service = "set_preset_mode"
                            data = { "preset_mode": String(modelData) }
                        } else if (t === "fan-preset-modes") {
                            service = "set_preset_mode"
                            data = { "preset_mode": String(modelData) }
                        } else if (t === "humidifier-modes") {
                            service = "set_mode"
                            data = { "mode": String(modelData) }
                        } else if (t === "water-heater-operation-modes") {
                            service = "set_operation_mode"
                            data = { "operation_mode": String(modelData) }
                        }
                        dashboard.callService(domain, service, data, entityId)
                    }
                }
            }
        }
    }

    Component {
        id: buttonsComp
        Row {
            property var feature
            property string entityId
            property var dashboard
            spacing: Theme.paddingSmall
            Button {
                text: {
                    var t = feature && feature.type ? feature.type : ""
                    if (t === "lock-commands")
                        return "Unlock"
                    if (t === "button" || t === "update-actions")
                        return "Run"
                    return "Open"
                }
                onClicked: {
                    var t = feature.type
                    var domain = dashboard.domainOf(entityId)
                    if (t === "lock-commands")
                        dashboard.callService("lock", "unlock", {}, entityId)
                    else if (t === "button")
                        dashboard.toggle(entityId)
                    else if (t === "update-actions")
                        dashboard.callService("update", "install", {}, entityId)
                    else if (domain === "valve")
                        dashboard.callService("valve", "open_valve", {}, entityId)
                    else
                        dashboard.callService("cover", "open_cover", {}, entityId)
                }
            }
            Button {
                visible: feature && feature.type !== "button" && feature.type !== "update-actions"
                text: (feature && feature.type === "lock-commands") ? "Lock" : "Close"
                onClicked: {
                    var t = feature.type
                    var domain = dashboard.domainOf(entityId)
                    if (t === "lock-commands")
                        dashboard.callService("lock", "lock", {}, entityId)
                    else if (domain === "valve")
                        dashboard.callService("valve", "close_valve", {}, entityId)
                    else
                        dashboard.callService("cover", "close_cover", {}, entityId)
                }
            }
        }
    }

    Component {
        id: sliderComp
        Slider {
            property var feature
            property string entityId
            property var dashboard
            width: parent.width
            minimumValue: 0
            maximumValue: 100
            value: {
                var t = feature && feature.type ? feature.type : ""
                var key = "current_position"
                if (t === "cover-tilt-position")
                    key = "current_tilt_position"
                if (t === "fan-speed")
                    key = "percentage"
                if (t === "media-player-volume")
                    key = "volume_level"
                if (t === "valve-position")
                    key = "current_position"
                if (!dashboard || bar.rev < 0)
                    return 0
                if (t === "bar-gauge")
                    return Number(dashboard.entityState(entityId))
                var v = Number(dashboard.attribute(entityId, key))
                if (t === "media-player-volume")
                    return v * 100
                return v
            }
            label: feature && feature.type ? String(feature.type).replace(/-/g, " ") : ""
            onReleased: {
                var t = feature.type
                var domain = dashboard.domainOf(entityId)
                if (t === "cover-position")
                    dashboard.callService("cover", "set_cover_position", { "position": Math.round(value) }, entityId)
                else if (t === "cover-tilt-position")
                    dashboard.callService("cover", "set_cover_tilt_position", { "tilt_position": Math.round(value) }, entityId)
                else if (t === "fan-speed")
                    dashboard.callService("fan", "set_percentage", { "percentage": Math.round(value) }, entityId)
                else if (t === "media-player-volume")
                    dashboard.callService("media_player", "volume_set", { "volume_level": value / 100.0 }, entityId)
                else if (t === "valve-position")
                    dashboard.callService("valve", "set_valve_position", { "position": Math.round(value) }, entityId)
            }
        }
    }

    Component {
        id: colorsComp
        Flow {
            id: swatches
            property var feature
            property string entityId
            property var dashboard
            width: parent ? parent.width : Screen.width
            spacing: Theme.paddingSmall

            function hsToRgb(h, s) {
                var sat = Math.max(0, Math.min(100, Number(s))) / 100
                var hue = ((Number(h) % 360) + 360) % 360
                var c = sat
                var x = c * (1 - Math.abs((hue / 60) % 2 - 1))
                var r = 0, g = 0, b = 0
                if (hue < 60) { r = c; g = x }
                else if (hue < 120) { r = x; g = c }
                else if (hue < 180) { g = c; b = x }
                else if (hue < 240) { g = x; b = c }
                else if (hue < 300) { r = x; b = c }
                else { r = c; b = x }
                return {
                    r: Math.round(r * 255),
                    g: Math.round(g * 255),
                    b: Math.round(b * 255)
                }
            }

            function kelvinRgb(k) {
                var t = Math.max(2000, Math.min(6500, Number(k)))
                var p = (t - 2000) / 4500
                return {
                    r: 255,
                    g: Math.round(147 + p * 108),
                    b: Math.round(41 + p * 214)
                }
            }

            function colorRgb(entry) {
                if (!entry)
                    return { r: 200, g: 200, b: 200 }
                if (entry.rgb_color && entry.rgb_color.length >= 3)
                    return { r: Number(entry.rgb_color[0]), g: Number(entry.rgb_color[1]), b: Number(entry.rgb_color[2]) }
                if (entry.hs_color && entry.hs_color.length >= 2)
                    return swatches.hsToRgb(entry.hs_color[0], entry.hs_color[1])
                if (entry.color_temp_kelvin)
                    return swatches.kelvinRgb(entry.color_temp_kelvin)
                if (entry.color_temp)
                    return swatches.kelvinRgb(1000000 / Math.max(1, Number(entry.color_temp)))
                return { r: 200, g: 200, b: 200 }
            }

            function applyColor(entry) {
                if (!dashboard || !entry)
                    return
                var data = {}
                if (entry.rgb_color)
                    data.rgb_color = entry.rgb_color
                else if (entry.hs_color)
                    data.hs_color = entry.hs_color
                else if (entry.color_temp_kelvin)
                    data.color_temp_kelvin = entry.color_temp_kelvin
                else if (entry.color_temp)
                    data.color_temp = entry.color_temp
                if (entry.brightness)
                    data.brightness = entry.brightness
                dashboard.callService("light", "turn_on", data, entityId)
            }

            readonly property var colors: {
                var list = []
                if (feature && feature.colors)
                    list = feature.colors
                else if (feature && feature.favorite_colors)
                    list = feature.favorite_colors
                else if (dashboard && bar.rev >= 0)
                    list = dashboard.attribute(entityId, "favorite_colors") || []
                return list || []
            }

            Repeater {
                model: swatches.colors
                Rectangle {
                    width: Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    property var rgb: swatches.colorRgb(modelData)
                    color: Qt.rgba(rgb.r / 255, rgb.g / 255, rgb.b / 255, 1)
                    border.width: 1
                    border.color: Theme.rgba(Theme.primaryColor, 0.35)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: swatches.applyColor(modelData)
                    }
                }
            }
        }
    }

    Component {
        id: colorTempComp
        Slider {
            property var feature
            property string entityId
            property var dashboard
            width: parent.width
            minimumValue: {
                var v = (dashboard && bar.rev >= 0) ? Number(dashboard.attribute(entityId, "min_color_temp_kelvin")) : 0
                return v > 0 ? v : 2000
            }
            maximumValue: {
                var v = (dashboard && bar.rev >= 0) ? Number(dashboard.attribute(entityId, "max_color_temp_kelvin")) : 0
                return v > 0 ? v : 6500
            }
            value: (dashboard && bar.rev >= 0) ? Number(dashboard.attribute(entityId, "color_temp_kelvin")) : 0
            label: "Color temperature"
            onReleased: {
                if (dashboard)
                    dashboard.callService("light", "turn_on",
                                          { "color_temp_kelvin": Math.round(value) }, entityId)
            }
        }
    }

    Component {
        id: genericComp
        Label {
            property var feature
            property string entityId
            property var dashboard
            width: parent ? parent.width : Screen.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            text: (feature && feature.type ? String(feature.type) : "feature")
                  + ": " + ((dashboard && bar.rev >= 0) ? dashboard.formatState(entityId) : "")
        }
    }
}
