import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// Climate controls matching the expanded entity in the events view: mode
// pills, a target temperature slider, and fan/swing pills when the entity
// supports them.
CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    function attr(name) {
        return (dashboard && root.rev >= 0) ? dashboard.attribute(entityId, name) : undefined
    }

    function numberAttr(name, fallback) {
        var value = Number(root.attr(name))
        return isFinite(value) ? value : fallback
    }

    function listAttr(name) {
        var value = root.attr(name)
        return (value && value.length) ? value : []
    }

    readonly property string mode: (dashboard && root.rev >= 0)
                                   ? dashboard.entityState(entityId) : ""
    readonly property string unit: {
        var raw = String(root.attr("temperature_unit") || "")
        if (raw.indexOf("F") >= 0)
            return "°F"
        return raw.indexOf("°") >= 0 ? raw : "°C"
    }
    readonly property bool fahrenheit: unit.indexOf("F") >= 0
    readonly property real minTemp: numberAttr("min_temp", fahrenheit ? 60 : 16)
    readonly property real maxTemp: numberAttr("max_temp", fahrenheit ? 86 : 30)
    readonly property real step: {
        var configured = numberAttr("target_temp_step", 0)
        return configured > 0 ? configured : (fahrenheit ? 1 : 0.5)
    }
    readonly property real target: numberAttr("temperature", NaN)
    readonly property real current: numberAttr("current_temperature", NaN)
    readonly property bool hasTarget: isFinite(target)
                                      || (root.attr("min_temp") !== undefined
                                          && root.attr("max_temp") !== undefined)

    function formatTemp(value) {
        if (!isFinite(value))
            return "—"
        return (root.step < 1 ? Number(value).toFixed(1) : String(Math.round(value))) + root.unit
    }

    Label {
        width: parent.width
        text: (dashboard && root.rev >= 0) ? root.configName(entityId, "") : entityId
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
        truncationMode: TruncationMode.Fade
    }

    Row {
        width: parent.width
        spacing: Theme.paddingMedium

        Label {
            id: stateLabel
            text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
        }

        Label {
            anchors.baseline: stateLabel.baseline
            visible: isFinite(root.current)
            text: qsTr("Now %1").arg(root.formatTemp(root.current))
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
    }

    ModeChips {
        modes: root.listAttr("hvac_modes")
        current: root.mode
        onPicked: {
            if (dashboard)
                dashboard.callService("climate", "set_hvac_mode",
                                      { "hvac_mode": mode }, root.entityId)
        }
    }

    Slider {
        id: targetSlider
        width: parent.width
        visible: root.hasTarget
        minimumValue: root.minTemp
        maximumValue: root.maxTemp
        stepSize: root.step
        label: qsTr("Temperature")
        valueText: root.formatTemp(value)

        // The slider owns its value while dragged, so the binding only feeds
        // it Home Assistant's value the rest of the time.
        Binding {
            target: targetSlider
            property: "value"
            when: !targetSlider.down
            value: {
                if (isFinite(root.target))
                    return root.target
                if (isFinite(root.current))
                    return root.current
                return (root.minTemp + root.maxTemp) / 2
            }
        }

        onDownChanged: {
            if (!down && dashboard)
                dashboard.callService("climate", "set_temperature",
                                      { "temperature": targetSlider.value }, root.entityId)
        }
    }

    ModeChips {
        title: qsTr("Fan")
        modes: root.listAttr("fan_modes")
        current: String(root.attr("fan_mode") || "")
        onPicked: {
            if (dashboard)
                dashboard.callService("climate", "set_fan_mode",
                                      { "fan_mode": mode }, root.entityId)
        }
    }

    ModeChips {
        title: qsTr("Swing")
        modes: root.listAttr("swing_modes")
        current: String(root.attr("swing_mode") || "")
        onPicked: {
            if (dashboard)
                dashboard.callService("climate", "set_swing_mode",
                                      { "swing_mode": mode }, root.entityId)
        }
    }

    ModeChips {
        title: qsTr("Preset")
        modes: root.listAttr("preset_modes")
        current: String(root.attr("preset_mode") || "")
        onPicked: {
            if (dashboard)
                dashboard.callService("climate", "set_preset_mode",
                                      { "preset_mode": mode }, root.entityId)
        }
    }
}
