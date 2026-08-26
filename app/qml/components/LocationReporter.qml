import QtQuick 2.6
import QtPositioning 5.2
import Nemo.DBus 2.0

// Foreground location reporter for mobile_app update_location.
// Uses GeoClue (GPS + Wi‑Fi/cell via mlsdb/beaconDB). Seeks quickly until
// accuracy is good, then backs off. Prefers tighter GPS after a coarse fix.
Item {
    id: reporter
    property var hassClient
    property bool enabled: hassClient && hassClient.sensors
            ? hassClient.sensors.locationReporting && hassClient.sensors.active
            : false
    readonly property real goodAccuracyMeters: 50
    readonly property int seekIntervalMs: 2000
    readonly property int cruiseIntervalMs: 30000

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

    onEnabledChanged: {
        positionSource.active = reporter.enabled
        if (reporter.enabled) {
            reporter.powerGps()
            positionSource.updateInterval = reporter.seekIntervalMs
        }
    }

    PositionSource {
        id: positionSource
        active: reporter.enabled
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
        onLocationReportingChanged: {
            positionSource.active = reporter.enabled
        }
        onActiveChanged: {
            positionSource.active = reporter.enabled
        }
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive && reporter.enabled) {
                reporter.powerGps()
                positionSource.updateInterval = reporter.seekIntervalMs
            }
        }
    }
}
