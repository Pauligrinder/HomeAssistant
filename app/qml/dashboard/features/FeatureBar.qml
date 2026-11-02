import QtQuick 2.6
import Sailfish.Silica 1.0

Column {
    id: bar
    property var features: []
    property string entityId: ""
    property var dashboard
    property var mdiIcons
    // When true (tile features_position: inline), shrink to content width.
    property bool compact: false
    width: bar.compact ? implicitWidth : (parent ? parent.width : Screen.width)
    spacing: Theme.paddingSmall
    property int entityTick: 0
    readonly property int rev: (dashboard ? dashboard.statesRevision : 0) + entityTick

    Connections {
        target: dashboard
        onEntityChanged: {
            if (entityId === bar.entityId)
                bar.entityTick++
        }
    }

    Repeater {
        model: bar.features
        Loader {
            width: bar.compact ? (item ? item.implicitWidth || item.width : 0) : bar.width
            visible: {
                var _ = bar.rev
                if (!modelData)
                    return true
                if (modelData.visibility && bar.dashboard)
                    return !!bar.dashboard.isVisible(modelData.visibility)
                return true
            }
            height: visible && status === Loader.Ready && item ? item.height : 0
            active: visible
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
        if (t === "media-player-playback" || t === "media-player-volume-buttons")
            return mediaButtonsComp
        if (t === "cover-position" || t === "cover-tilt-position" || t === "fan-speed"
                || t === "media-player-volume" || t === "media-player-volume-slider"
                || t === "valve-position" || t === "bar-gauge")
            return sliderComp
        if (t === "light-favorite-colors" || t === "light-color")
            return colorsComp
        if (t === "light-color-temp")
            return colorTempComp
        // Unknown features stay invisible — dumping "type: state" on the tile
        // looked like broken overlapping text.
        return emptyComp
    }

    function sliderLabel(feature) {
        var t = feature && feature.type ? String(feature.type) : ""
        // HA feature sliders are unlabeled; brightness is the exception we keep.
        if (t === "light-brightness")
            return i18n.translation("brightness")
        return ""
    }

    Component {
        id: toggleComp
        Switch {
            property var feature
            property string entityId
            property var dashboard
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
            label: i18n.translation("brightness")
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
                        return i18n.translation("unlock")
                    if (t === "button" || t === "update-actions")
                        return i18n.translation("run")
                    return i18n.translation("open")
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
                text: (feature && feature.type === "lock-commands") ? i18n.translation("lock") : i18n.translation("close")
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
                if (t === "media-player-volume" || t === "media-player-volume-slider")
                    key = "volume_level"
                if (t === "valve-position")
                    key = "current_position"
                if (!dashboard || bar.rev < 0)
                    return 0
                if (t === "bar-gauge")
                    return Number(dashboard.entityState(entityId))
                var v = Number(dashboard.attribute(entityId, key))
                if (t === "media-player-volume" || t === "media-player-volume-slider")
                    return v * 100
                return v
            }
            label: bar.sliderLabel(feature)
            onReleased: {
                var t = feature.type
                var domain = dashboard.domainOf(entityId)
                if (t === "cover-position")
                    dashboard.callService("cover", "set_cover_position", { "position": Math.round(value) }, entityId)
                else if (t === "cover-tilt-position")
                    dashboard.callService("cover", "set_cover_tilt_position", { "tilt_position": Math.round(value) }, entityId)
                else if (t === "fan-speed")
                    dashboard.callService("fan", "set_percentage", { "percentage": Math.round(value) }, entityId)
                else if (t === "media-player-volume" || t === "media-player-volume-slider")
                    dashboard.callService("media_player", "volume_set", { "volume_level": value / 100.0 }, entityId)
                else if (t === "valve-position")
                    dashboard.callService("valve", "set_valve_position", { "position": Math.round(value) }, entityId)
            }
        }
    }

    Component {
        id: mediaButtonsComp
        Row {
            property var feature
            property string entityId
            property var dashboard
            spacing: Theme.paddingSmall
            readonly property string featureType: feature && feature.type ? String(feature.type) : ""
            readonly property bool volumeButtons: featureType === "media-player-volume-buttons"
            readonly property var controls: {
                if (feature && feature.controls)
                    return feature.controls
                if (volumeButtons)
                    return []
                return ["media_previous_track", "media_play_pause", "media_next_track"]
            }
            readonly property bool showMute: {
                if (volumeButtons)
                    return feature && feature.show_mute_button !== false
                var list = controls || []
                for (var i = 0; i < list.length; ++i) {
                    if (String(list[i]) === "volume_mute")
                        return true
                }
                return false
            }
            readonly property real stepPct: {
                var s = feature && feature.step !== undefined ? Number(feature.step) : 5
                return (isFinite(s) && s > 0) ? s : 5
            }
            readonly property bool muted: (dashboard && bar.rev >= 0)
                                         ? !!dashboard.attribute(entityId, "is_volume_muted") : false
            readonly property bool playing: (dashboard && bar.rev >= 0)
                                           ? dashboard.entityState(entityId) === "playing" : false

            function hasControl(name) {
                var list = controls || []
                for (var i = 0; i < list.length; ++i) {
                    if (String(list[i]) === name)
                        return true
                }
                return false
            }

            function nudgeVolume(delta) {
                if (!dashboard)
                    return
                var cur = Number(dashboard.attribute(entityId, "volume_level"))
                if (!isFinite(cur))
                    cur = 0
                var next = Math.max(0, Math.min(1, cur + (delta / 100.0)))
                dashboard.callService("media_player", "volume_set",
                                      { "volume_level": next }, entityId)
            }

            Button {
                visible: parent.showMute
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: parent.muted ? "Unmute" : "Mute"
                onClicked: {
                    if (!dashboard)
                        return
                    dashboard.callService("media_player", "volume_mute",
                                          { "is_volume_muted": !parent.muted }, entityId)
                }
            }
            Button {
                visible: parent.volumeButtons
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: "−"
                onClicked: parent.nudgeVolume(-parent.stepPct)
            }
            Button {
                visible: parent.volumeButtons
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: "+"
                onClicked: parent.nudgeVolume(parent.stepPct)
            }
            Button {
                visible: !parent.volumeButtons && parent.hasControl("media_previous_track")
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: i18n.translation("prev")
                onClicked: if (dashboard) dashboard.callService("media_player", "media_previous_track", {}, entityId)
            }
            Button {
                visible: !parent.volumeButtons && parent.hasControl("media_play_pause")
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: parent.playing ? "Pause" : i18n.translation("play")
                onClicked: if (dashboard) dashboard.callService("media_player", "media_play_pause", {}, entityId)
            }
            Button {
                visible: !parent.volumeButtons && parent.hasControl("media_next_track")
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: i18n.translation("next")
                onClicked: if (dashboard) dashboard.callService("media_player", "media_next_track", {}, entityId)
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
            label: i18n.translation("color_temperature")
            onReleased: {
                if (dashboard)
                    dashboard.callService("light", "turn_on",
                                          { "color_temp_kelvin": Math.round(value) }, entityId)
            }
        }
    }

    Component {
        id: emptyComp
        Item {
            property var feature
            property string entityId
            property var dashboard
            width: 1
            height: 0
        }
    }
}
