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
    // Home on internal owns the tracker — skip GeoClue seeks while pinned.
    readonly property bool pinnedHome: hassClient && hassClient.sensors
            && hassClient.sensors.homeOnInternal && hassClient.usingInternalUrl
    property bool enabled: hassClient && hassClient.sensors
            ? hassClient.sensors.locationReporting
              && hassClient.sensors.active
              && !reporter.pinnedHome
            : false
    readonly property int staleMinutes: hassClient && hassClient.sensors
            ? hassClient.sensors.locationStaleMinutes : 15
    readonly property int startDelayMs: 4000
    readonly property int seekTimeoutMs: 60000
    readonly property int seekUpdateMs: 5000
    readonly property int staleCheckMs: 60000
    // After a seek that produced nothing usable, retry soon — waiting the full
    // stale interval left daycare pickups with a single failed burst.
    readonly property int failedSeekRetryMs: 75000
    // Never post a fix older than this, even if the user's stale interval is
    // longer. Cached GeoClue dumps from other apps (e.g. an old Helsinki fix)
    // were jumping the device_tracker across the country.
    readonly property int maxPostAgeMs: 120000
    readonly property real maxPostAccuracyM: 120
    readonly property real confirmJumpM: 400
    property bool seeking: false
    property bool lastSeekGotFix: false
    property double lastFixAtMs: 0
    property double lastSeekAtMs: 0
    property double lastPostedLat: 0
    property double lastPostedLon: 0
    property bool havePostedFix: false
    // Large jumps need a second agreeing sample so one MLS blip cannot move us.
    property double pendingLat: 0
    property double pendingLon: 0
    property double pendingAcc: 0
    property double pendingAtMs: 0
    property bool havePending: false

    function staleMs() {
        return Math.max(5, reporter.staleMinutes) * 60 * 1000
    }

    function maxAcceptAgeMs() {
        return Math.min(reporter.staleMs(), reporter.maxPostAgeMs)
    }

    function nowMs() {
        return Date.now()
    }

    function locationIsStale() {
        if (reporter.lastFixAtMs <= 0)
            return true
        return (reporter.nowMs() - reporter.lastFixAtMs) >= reporter.staleMs()
    }

    function seekCooldownMs() {
        if (reporter.lastSeekGotFix)
            return reporter.staleMs()
        return reporter.failedSeekRetryMs
    }

    function canSelfSeek() {
        if (!reporter.enabled || reporter.seeking)
            return false
        if (!reporter.locationIsStale())
            return false
        if (reporter.lastSeekAtMs <= 0)
            return true
        return (reporter.nowMs() - reporter.lastSeekAtMs) >= reporter.seekCooldownMs()
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

    function approxMeters(lat1, lon1, lat2, lon2) {
        var r = 6371000
        var p1 = lat1 * Math.PI / 180
        var p2 = lat2 * Math.PI / 180
        var dp = (lat2 - lat1) * Math.PI / 180
        var dl = (lon2 - lon1) * Math.PI / 180
        var a = Math.sin(dp / 2) * Math.sin(dp / 2)
                + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2)
        return 2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    }

    function clearPending() {
        reporter.havePending = false
        reporter.pendingAtMs = 0
    }

    function acceptFix(latitude, longitude, accuracy, timestampSec, source) {
        if (!reporter.enabled || !hassClient || !hassClient.sensors)
            return false
        if (latitude === undefined || longitude === undefined)
            return false
        if (!isFinite(latitude) || !isFinite(longitude))
            return false

        var now = reporter.nowMs()
        var hasTs = timestampSec !== undefined && timestampSec !== null
                && Number(timestampSec) > 0
        var fixAtMs = hasTs ? Math.min(now, Number(timestampSec) * 1000) : now
        var ageMs = now - fixAtMs
        var acc = reporter.accuracyMeters(accuracy)
        var maxAge = reporter.maxAcceptAgeMs()
        var src = source || "gps"

        // Drop other apps' cached GeoClue positions. A PositionSource burst
        // often surfaces those first; posting them made HA jump to Helsinki.
        if (hasTs && ageMs > maxAge) {
            console.log("Helmsman location: reject stale fix ageSec=",
                        Math.round(ageMs / 1000), "lat=", latitude, "lon=", longitude,
                        "src=", src)
            return false
        }

        // Mlsdb (cell/Wi‑Fi) regularly invents city-scale circles; Hybris GPS
        // is the only source trusted for large moves.
        if (src === "mls") {
            if (acc <= 0 || acc > 80)
                return false
            if (reporter.havePostedFix) {
                var mlsJump = reporter.approxMeters(reporter.lastPostedLat, reporter.lastPostedLon,
                                                    latitude, longitude)
                if (mlsJump > 300)
                    return false
            }
        }

        // Untimestamped first hits while seeking are usually the same cache.
        if (!hasTs && reporter.seeking) {
            var seekAge = now - reporter.lastSeekAtMs
            if (seekAge < 4000 && (acc <= 0 || acc > 75))
                return false
        }

        if (acc > reporter.maxPostAccuracyM) {
            console.log("Helmsman location: reject poor accuracy acc=", acc, "src=", src)
            return false
        }

        // Huge jump from a weak / untimestamped fix: wait for a better one.
        if (reporter.havePostedFix) {
            var jump = reporter.approxMeters(reporter.lastPostedLat, reporter.lastPostedLon,
                                             latitude, longitude)
            if (jump > 2000) {
                if (!hasTs || ageMs > 30000) {
                    console.log("Helmsman location: reject teleport jumpM=",
                                Math.round(jump), "ageSec=", Math.round(ageMs / 1000))
                    return false
                }
                if (acc <= 0 || acc > 100) {
                    console.log("Helmsman location: reject inaccurate teleport acc=", acc)
                    return false
                }
            }

            // Mid-range jumps (neighbourhood bounce / zone flicker) need two
            // agreeing samples, unless the fix is already GPS-tight.
            if (jump > reporter.confirmJumpM && !(acc > 0 && acc <= 35 && ageMs < 20000)) {
                if (!reporter.havePending
                        || (now - reporter.pendingAtMs) > 45000) {
                    reporter.pendingLat = latitude
                    reporter.pendingLon = longitude
                    reporter.pendingAcc = acc
                    reporter.pendingAtMs = now
                    reporter.havePending = true
                    console.log("Helmsman location: hold jump pendingM=",
                                Math.round(jump), "acc=", acc, "src=", src)
                    return false
                }
                var agree = reporter.approxMeters(reporter.pendingLat, reporter.pendingLon,
                                                  latitude, longitude)
                if (agree > 75) {
                    reporter.pendingLat = latitude
                    reporter.pendingLon = longitude
                    reporter.pendingAcc = acc
                    reporter.pendingAtMs = now
                    console.log("Helmsman location: pending disagree agreeM=",
                                Math.round(agree), "src=", src)
                    return false
                }
                reporter.clearPending()
            } else if (jump <= reporter.confirmJumpM) {
                reporter.clearPending()
            }
        }

        // Preserve the real fix age so a cached hit cannot postpone the next
        // acquisition as if it had just been measured.
        reporter.lastFixAtMs = fixAtMs
        reporter.lastPostedLat = latitude
        reporter.lastPostedLon = longitude
        reporter.havePostedFix = true
        reporter.lastSeekGotFix = true
        console.log("Helmsman location: accept", latitude, longitude,
                    "acc=", acc, "ageSec=", Math.round(ageMs / 1000), "src=", src)
        hassClient.sensors.updateLocation(latitude, longitude, acc, -1)

        // Fresh GPS-quality fix: end the burst early.
        if (reporter.seeking && hasTs && ageMs < 30000 && acc > 0 && acc <= 75)
            reporter.stopSeek()
        return true
    }

    function acceptGeoclue(fields, timestamp, latitude, longitude, altitude, accuracy, source) {
        // LatitudePresent = 1, LongitudePresent = 2
        if (fields !== undefined && fields !== null && fields !== 0
                && (fields & 3) !== 3)
            return
        reporter.acceptFix(latitude, longitude, accuracy, timestamp, source)
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
        reporter.lastSeekGotFix = false
        reporter.lastSeekAtMs = reporter.nowMs()
        reporter.clearPending()
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
        if (!reporter.enabled)
            return
        // Force a new acquisition even if the last accepted fix is still
        // within the stale window — "Update location now" / leaving home Wi‑Fi
        // must not reuse a cached fix.
        if (reporter.seeking)
            reporter.stopSeek()
        startDelayTimer.stop()
        reporter.seeking = true
        reporter.lastSeekGotFix = false
        reporter.lastSeekAtMs = reporter.nowMs()
        reporter.clearPending()
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
            if (position.timestamp && !isNaN(position.timestamp.getTime())
                    && position.timestamp.getTime() > 0)
                ts = position.timestamp.getTime() / 1000
            reporter.acceptFix(coord.latitude, coord.longitude, accuracy, ts, "qt")
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
                    reporter.acceptGeoclue(fields, timestamp, latitude, longitude, altitude, accuracy, "hybris")
                }
            }

            DBusInterface {
                bus: DBus.SessionBus
                service: "org.freedesktop.Geoclue.Providers.Mlsdb"
                path: "/org/freedesktop/Geoclue/Providers/Mlsdb"
                iface: "org.freedesktop.Geoclue.Position"
                signalsEnabled: true
                function positionChanged(fields, timestamp, latitude, longitude, altitude, accuracy) {
                    reporter.acceptGeoclue(fields, timestamp, latitude, longitude, altitude, accuracy, "mls")
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
