import QtQuick 2.6
import org.freedesktop.contextkit 1.0

// Reads battery state via ContextKit and pushes Android-aligned values
// into SensorCoordinator through hassClient.sensors.
Item {
    id: monitor
    property var hassClient
    property int level: -1
    property bool charging: false
    property string batteryState: "unknown"
    property string chargerType: "none"

    function publish() {
        if (!hassClient || !hassClient.sensors)
            return
        if (monitor.level < 0)
            return
        hassClient.sensors.updateBattery(monitor.level,
                                         monitor.charging,
                                         monitor.batteryState,
                                         monitor.chargerType)
    }

    function recomputeState() {
        var pct = chargePercentage.value
        if (pct === undefined || pct === null)
            return
        monitor.level = Math.max(0, Math.min(100, Math.round(Number(pct))))

        var isCharging = false
        if (isChargingProp.value !== undefined && isChargingProp.value !== null)
            isCharging = !!isChargingProp.value
        else if (stateProp.value !== undefined && stateProp.value !== null) {
            var raw = String(stateProp.value).toLowerCase()
            isCharging = (raw.indexOf("charg") >= 0 && raw.indexOf("discharg") < 0)
                    || raw === "full"
        }
        monitor.charging = isCharging

        var state = "discharging"
        if (stateProp.value !== undefined && stateProp.value !== null) {
            var s = String(stateProp.value).toLowerCase()
            if (s.indexOf("full") >= 0 || monitor.level >= 100 && isCharging)
                state = "full"
            else if (s.indexOf("charg") >= 0 && s.indexOf("discharg") < 0)
                state = "charging"
            else if (s.indexOf("discharg") >= 0)
                state = "discharging"
            else if (s.indexOf("idle") >= 0 || s.indexOf("not") >= 0)
                state = "not_charging"
            else if (isCharging)
                state = "charging"
        } else if (isCharging) {
            state = monitor.level >= 100 ? "full" : "charging"
        }
        monitor.batteryState = state

        var charger = "none"
        if (chargerTypeProp.value !== undefined && chargerTypeProp.value !== null) {
            var c = String(chargerTypeProp.value).toLowerCase()
            // DCP/CDP/HVDCP are wired USB charging ports, not Qi wireless.
            if (c.indexOf("usb") >= 0 || c === "sdp")
                charger = "usb"
            else if (c.indexOf("dcp") >= 0 || c.indexOf("cdp") >= 0
                     || c.indexOf("hvdcp") >= 0 || c.indexOf("ac") >= 0
                     || c.indexOf("wall") >= 0 || c.indexOf("mains") >= 0)
                charger = isCharging ? "ac" : "none"
            else if (isCharging)
                charger = "ac"
        } else if (isCharging) {
            charger = "ac"
        }
        monitor.chargerType = charger
        monitor.publish()
    }

    ContextProperty {
        id: chargePercentage
        key: "Battery.ChargePercentage"
        onValueChanged: monitor.recomputeState()
    }

    ContextProperty {
        id: isChargingProp
        key: "Battery.IsCharging"
        onValueChanged: monitor.recomputeState()
    }

    ContextProperty {
        id: stateProp
        key: "Battery.State"
        onValueChanged: monitor.recomputeState()
    }

    ContextProperty {
        id: chargerTypeProp
        key: "Battery.ChargerType"
        onValueChanged: monitor.recomputeState()
    }

    // Some devices only expose ChargePercentage; poll a few times after start.
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: monitor.recomputeState()
    }

    Component.onCompleted: monitor.recomputeState()
}
