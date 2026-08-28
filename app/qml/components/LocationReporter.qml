import QtQuick 2.6
import QtPositioning 5.2
import Nemo.DBus 2.0

// Foreground location reporter for mobile_app update_location.
// Uses GeoClue (GPS + Wi‑Fi/cell via mlsdb/beaconDB). Seeks quickly until
// accuracy is good, then backs off. Prefers tighter GPS after a coarse fix.
//
// Geoclue's startUpdates() does synchronous D-Bus on the UI thread. Do not
// start it until sensors are already running and the dashboard is up, or it
// wedges the app the same way sensor registration used to.
Item {
    id: reporter
    property var hassClient
    property bool enabled: hassClient && hassClient.sensors
            ? hassClient.sensors.locationReporting && hassClient.sensors.active
            : false
    readonly property real goodAccuracyMeters: 50
    readonly property int seekIntervalMs: 2000
    readonly property int cruiseIntervalMs: 30000
    readonly property int startDelayMs: 4000

    function applyInterval() {
        var acc = positionSource.position.horizontalAccuracy
        var good = acc !== undefined && acc !== null && acc > 0 && acc <= reporter.goodAccuracyMeters
        positionSource.updateInterval = good ? reporter.cruiseIntervalMs : reporter.seekIntervalMs
    }

    function powerGps() {
        gpsTech.typedCall("SetProperty",
                          [
                              { "type": "s", "value": "Powered" },
                              { "type": "v", "value": { "type": "b", "value": true } }
                          ],
                          function() {},
                          function() {})
    }

    function applyActive() {
        startDelayTimer.stop()
        if (!reporter.enabled) {
            positionSource.active = false
            return
        }
        if (positionSource.active)
            return
        startDelayTimer.start()
    }

    onEnabledChanged: reporter.applyActive()

    Timer {
        id: startDelayTimer
        interval: reporter.startDelayMs
        repeat: false
        onTriggered: {
            if (!reporter.enabled)
                return
            reporter.powerGps()
            positionSource.updateInterval = reporter.seekIntervalMs
            positionSource.active = true
        }
    }

    PositionSource {
        id: positionSource
        active: false
        updateInterval: reporter.seekIntervalMs
        preferredPositioningMethods: PositionSource.AllPositioningMethods

        onPositionChanged: {
            if (!reporter.enabled || !hassClient || !hassClient.sensors)
                return
            var coord = position.coordinate
            if (!coord || !coord.isValid)
                return
            var accuracy = position.horizontalAccuracy
            if (accuracy === undefined || accuracy === null || accuracy < 0)
                accuracy = 0
            hassClient.sensors.updateLocation(coord.latitude,
                                              coord.longitude,
                                              accuracy,
                                              -1)
            reporter.applyInterval()
        }
    }

    DBusInterface {
        id: gpsTech
        bus: DBus.SystemBus
        service: "net.connman"
        path: "/net/connman/technology/gps"
        iface: "net.connman.Technology"
    }

    Connections {
        target: hassClient && hassClient.sensors ? hassClient.sensors : null
        onLocationReportingChanged: reporter.applyActive()
        onActiveChanged: reporter.applyActive()
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive && reporter.enabled
                    && positionSource.active) {
                reporter.powerGps()
                positionSource.updateInterval = reporter.seekIntervalMs
            }
        }
    }
}
