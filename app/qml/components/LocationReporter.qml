import QtQuick 2.6
import QtPositioning 5.2
import Nemo.DBus 2.0

// Location reporter for mobile_app update_location.
// Does not keep GPS running. Listens for GeoClue PositionChanged from other
// apps (Hybris GPS / Mlsdb-BeaconDB). Runs a bounded acquisition burst when
// the last fix is older than the configured stale interval.
//
// Geoclue's startUpdates() does synchronous D-Bus on the UI thread. Do not
// start a self-request until sensors are already running and the dashboard
// is up, or it wedges the app the same way sensor registration used to.
// GeoClue D-Bus listeners are Loader-gated the same way: instantiating them
// at ApplicationWindow construction activated GPS before the first frame.
Item {
    id: reporter
    property var hassClient
    property bool enabled: hassClient && hassClient.sensors
            ? hassClient.sensors.locationReporting
              && hassClient.sensors.active
              && !hassClient.usingInternalUrl
            : false
    readonly property int staleMinutes: hassClient && hassClient.sensors
            ? hassClient.sensors.locationStaleMinutes : 15
    readonly property int startDelayMs: 4000
    readonly property int seekTimeoutMs: 45000
    readonly property int seekUpdateMs: 5000
    readonly property int staleCheckMs: 60000
    property bool seeking: false
    property double lastFixAtMs: 0
    property double lastSeekAtMs: 0

    function staleMs() {
        return Math.max(5, reporter.staleMinutes) * 60 * 1000
    }

    function nowMs() {
        return Date.now()
    }

    function locationIsStale() {
        if (reporter.lastFixAtMs <= 0)
            return true
        return (reporter.nowMs() - reporter.lastFixAtMs) >= reporter.staleMs()
    }

    function canSelfSeek() {
        if (!reporter.enabled || reporter.seeking)
            return false
        if (!reporter.locationIsStale())
            return false
        if (reporter.lastSeekAtMs <= 0)
            return true
        return (reporter.nowMs() - reporter.lastSeekAtMs) >= reporter.staleMs()
    }

    function accuracyMeters(accuracy) {
        if (accuracy === undefined || accuracy === null)
            return 0
        if (typeof accuracy === "number")
            return accuracy < 0 ? 0 : accuracy
        if (accuracy.horizontal !== undefined && accuracy.horizontal !== null)
            return accuracy.horizontal < 0 ? 0 : accuracy.horizontal
        if (accuracy.length > 1 && accuracy[1] !== undefined)
            return accuracy[1] < 0 ? 0 : accuracy[1]
        return 0
    }

    function acceptFix(latitude, longitude, accuracy, timestampSec) {
        if (!reporter.enabled || !hassClient || !hassClient.sensors)
            return false
        if (latitude === undefined || longitude === undefined)
            return false
        if (!isFinite(latitude) || !isFinite(longitude))
            return false
        if (timestampSec && timestampSec > 0) {
            var ageMs = reporter.nowMs() - (timestampSec * 1000)
            if (ageMs > reporter.staleMs() * 2)
                return false
        }
        var acc = reporter.accuracyMeters(accuracy)
        // A PositionSource burst can first return a cached fix. Preserve its
        // actual age so it cannot postpone the next acquisition as if it had
        // just been measured.
        var fixAtMs = timestampSec && timestampSec > 0
                ? timestampSec * 1000 : reporter.nowMs()
        reporter.lastFixAtMs = Math.min(reporter.nowMs(), fixAtMs)
        hassClient.sensors.updateLocation(latitude, longitude, acc, -1)
        return true
    }

    function acceptGeoclue(fields, timestamp, latitude, longitude, altitude, accuracy) {
        // LatitudePresent = 1, LongitudePresent = 2
        if (fields !== undefined && fields !== null && fields !== 0
                && (fields & 3) !== 3)
            return
        reporter.acceptFix(latitude, longitude, accuracy, timestamp)
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

    function startSeek() {
        if (!reporter.canSelfSeek())
            return
        startDelayTimer.stop()
        reporter.seeking = true
        reporter.lastSeekAtMs = reporter.nowMs()
        seekTimeoutTimer.restart()
        reporter.powerGps()
        positionSource.updateInterval = reporter.seekUpdateMs
        positionSource.active = true
    }

    function stopSeek() {
        startDelayTimer.stop()
        seekTimeoutTimer.stop()
        reporter.seeking = false
        positionSource.active = false
    }

    function applyMode() {
        startDelayTimer.stop()
        if (!reporter.enabled) {
            reporter.stopSeek()
            return
        }
        if (reporter.canSelfSeek())
            startDelayTimer.start()
    }

    function refreshNow() {
        if (!reporter.enabled || reporter.seeking)
            return
        startDelayTimer.stop()
        reporter.seeking = true
        reporter.lastSeekAtMs = reporter.nowMs()
        seekTimeoutTimer.restart()
        reporter.powerGps()
        positionSource.updateInterval = reporter.seekUpdateMs
        positionSource.active = true
    }

    onEnabledChanged: reporter.applyMode()
    onStaleMinutesChanged: {
        if (reporter.enabled && reporter.canSelfSeek())
            reporter.applyMode()
    }

    Timer {
        id: startDelayTimer
        interval: reporter.startDelayMs
        repeat: false
        onTriggered: {
            if (reporter.canSelfSeek())
                reporter.startSeek()
        }
    }

    Timer {
        id: seekTimeoutTimer
        interval: reporter.seekTimeoutMs
        repeat: false
        onTriggered: reporter.stopSeek()
    }

    Timer {
        id: staleCheckTimer
        interval: reporter.staleCheckMs
        repeat: true
        running: reporter.enabled
        onTriggered: {
            if (reporter.canSelfSeek())
                reporter.startSeek()
        }
    }

    PositionSource {
        id: positionSource
        active: false
        preferredPositioningMethods: PositionSource.AllPositioningMethods

        onPositionChanged: {
            var coord = position.coordinate
            if (!coord || !coord.isValid)
                return
            var accuracy = position.horizontalAccuracy
            var ts = 0
            if (position.timestamp)
                ts = position.timestamp.getTime() / 1000
            reporter.acceptFix(coord.latitude, coord.longitude, accuracy, ts)
        }
    }

    DBusInterface {
        id: gpsTech
        bus: DBus.SystemBus
        service: "net.connman"
        path: "/net/connman/technology/gps"
        iface: "net.connman.Technology"
    }

    // Only subscribe once location reporting is actually on. Creating these
    // at window construction D-Bus-activated Hybris GPS before first paint.
    Loader {
        active: reporter.enabled
        sourceComponent: geoclueListeners
    }

    Component {
        id: geoclueListeners
        Item {
            DBusInterface {
                bus: DBus.SessionBus
                service: "org.freedesktop.Geoclue.Providers.Hybris"
                path: "/org/freedesktop/Geoclue/Providers/Hybris"
                iface: "org.freedesktop.Geoclue.Position"
                signalsEnabled: true
                function positionChanged(fields, timestamp, latitude, longitude, altitude, accuracy) {
                    reporter.acceptGeoclue(fields, timestamp, latitude, longitude, altitude, accuracy)
                }
            }

            DBusInterface {
                bus: DBus.SessionBus
                service: "org.freedesktop.Geoclue.Providers.Mlsdb"
                path: "/org/freedesktop/Geoclue/Providers/Mlsdb"
                iface: "org.freedesktop.Geoclue.Position"
                signalsEnabled: true
                function positionChanged(fields, timestamp, latitude, longitude, altitude, accuracy) {
                    reporter.acceptGeoclue(fields, timestamp, latitude, longitude, altitude, accuracy)
                }
            }
        }
    }

    Connections {
        target: hassClient && hassClient.sensors ? hassClient.sensors : null
        onLocationReportingChanged: reporter.applyMode()
        onActiveChanged: reporter.applyMode()
        onLocationStaleMinutesChanged: reporter.applyMode()
        onLocationRefreshRequested: reporter.refreshNow()
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive)
                reporter.applyMode()
        }
    }
}
