import QtQuick 2.6
import QtPositioning 5.4
import Sailfish.Silica 1.0
import MapboxMap 1.0

// Interactive MapLibre / OpenFreeMap basemap for fullscreen entity maps.
// Dashboard cards keep the lighter raster EntityMap and open this via MapPage.
Item {
    id: root
    anchors.fill: parent

    property var dashboard
    property var markers: []
    // Valid defaults until markers/autoFit set the camera (NaN crashes MapLibre).
    property real latitude: 64.95
    property real longitude: 25.75
    property real zoom: 5
    property bool autoFit: true
    property bool interactive: true
    property int topContentInset: 0
    property bool layersReady: false
    property bool userMoved: false

    readonly property int avatarSize: Theme.iconSizeMedium
    readonly property string accentHex: root.cssHex(Theme.highlightColor)
    readonly property bool valid: {
        if (root.autoFit && markerModel.count > 0)
            return true
        return isFinite(root.latitude) && isFinite(root.longitude)
                && Math.abs(root.latitude) <= 90
                && Math.abs(root.longitude) <= 180
    }

    signal markerClicked(string entityId)
    signal mapClicked()

    ListModel { id: markerModel }

    // MapLibre paint props need "#rrggbb"; Theme.color / #aarrggbb throws domain_error.
    function cssHex(c) {
        if (c === undefined || c === null)
            return "#1E88E5"
        var r = Math.max(0, Math.min(255, Math.round(Number(c.r) * 255)))
        var g = Math.max(0, Math.min(255, Math.round(Number(c.g) * 255)))
        var b = Math.max(0, Math.min(255, Math.round(Number(c.b) * 255)))
        function h(n) {
            var s = n.toString(16)
            return s.length < 2 ? ("0" + s) : s
        }
        return "#" + h(r) + h(g) + h(b)
    }

    function lon2tile(lon, z) {
        return (Number(lon) + 180.0) / 360.0 * Math.pow(2, z)
    }

    function lat2tile(lat, z) {
        var rad = Number(lat) * Math.PI / 180.0
        return (1.0 - Math.log(Math.tan(rad) + 1.0 / Math.cos(rad)) / Math.PI) / 2.0
                * Math.pow(2, z)
    }

    function tile2lat(y, z) {
        var n = Math.PI - 2.0 * Math.PI * y / Math.pow(2, z)
        return 180.0 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))
    }

    function zoomToFit(pts) {
        if (!pts.length)
            return 15
        if (pts.length === 1)
            return 15
        var pad = Math.max(root.avatarSize * 2, Math.min(root.width, root.height) * 0.12)
        var topPad = Math.max(pad, root.topContentInset + pad * 0.5)
        var availW = Math.max(32, root.width - 2 * pad)
        var availH = Math.max(32, root.height - topPad - pad)
        var tilePx = 512
        for (var z = 17; z >= 2; z--) {
            var minX = Infinity
            var maxX = -Infinity
            var minY = Infinity
            var maxY = -Infinity
            for (var i = 0; i < pts.length; i++) {
                var x = root.lon2tile(pts[i].lon, z) * tilePx
                var y = root.lat2tile(pts[i].lat, z) * tilePx
                minX = Math.min(minX, x)
                maxX = Math.max(maxX, x)
                minY = Math.min(minY, y)
                maxY = Math.max(maxY, y)
            }
            if ((maxX - minX) <= availW && (maxY - minY) <= availH)
                return z
        }
        return 2
    }

    function setCenter(lat, lon, z) {
        if (isFinite(lat) && isFinite(lon)) {
            root.latitude = lat
            root.longitude = lon
            map.center = QtPositioning.coordinate(lat, lon)
        }
        if (z !== undefined && z !== null && isFinite(z)) {
            var zz = Math.max(map.minimumZoomLevel, Math.min(map.maximumZoomLevel, Number(z)))
            root.zoom = zz
            map.zoomLevel = zz
        }
    }

    function fitToMarkers() {
        var pts = []
        for (var i = 0; i < markerModel.count; i++) {
            var m = markerModel.get(i)
            if (isFinite(m.lat) && isFinite(m.lon))
                pts.push({ "lat": m.lat, "lon": m.lon })
        }
        if (!pts.length || root.width < 8 || root.height < 8)
            return
        var minLat = pts[0].lat
        var maxLat = pts[0].lat
        var minLon = pts[0].lon
        var maxLon = pts[0].lon
        for (var p = 1; p < pts.length; p++) {
            minLat = Math.min(minLat, pts[p].lat)
            maxLat = Math.max(maxLat, pts[p].lat)
            minLon = Math.min(minLon, pts[p].lon)
            maxLon = Math.max(maxLon, pts[p].lon)
        }
        var centerLon = (minLon + maxLon) / 2
        var centerLat = root.tile2lat((root.lat2tile(minLat, 20) + root.lat2tile(maxLat, 20)) / 2, 20)
        root.setCenter(centerLat, centerLon, root.zoomToFit(pts))
    }

    function modelIndexById(id) {
        for (var i = 0; i < markerModel.count; i++) {
            if (markerModel.get(i).mid === id)
                return i
        }
        return -1
    }

    function sortedMarkers() {
        var list = root.markers || []
        var out = []
        for (var i = 0; i < list.length; i++) {
            if (!list[i] || !isFinite(Number(list[i].lat)) || !isFinite(Number(list[i].lon)))
                continue
            out.push(list[i])
        }
        out.sort(function(a, b) {
            return Number(b.lat) - Number(a.lat)
        })
        return out
    }

    function rebuildMarkers() {
        if (root.width < 8 || root.height < 8)
            return
        // trackLocation / fit before the style is ready aborts with domain_error.
        if (!root.layersReady)
            return
        if (map.gestureInProgress)
            return

        var list = root.sortedMarkers()
        var keep = {}
        for (var i = 0; i < list.length; i++) {
            var m = list[i]
            var mid = String(m.id || "")
            if (!mid.length)
                continue
            keep[mid] = true
            var pic = m.picture ? String(m.picture) : ""
            var url = (pic.length && dashboard) ? dashboard.cachedMediaUrl(pic) : ""
            var idx = root.modelIndexById(mid)
            if (idx >= 0 && markerModel.get(idx).picture === pic
                    && markerModel.get(idx).imageUrl && !url)
                url = markerModel.get(idx).imageUrl
            if (pic.length && dashboard && !url)
                dashboard.prefetchMedia(pic)

            var lat = Number(m.lat)
            var lon = Number(m.lon)
            var name = String(m.name || "")
            var acc = Number(m.accuracy) || 0
            var rec = {
                "mid": mid,
                "lat": lat,
                "lon": lon,
                "name": name,
                "picture": pic,
                "imageUrl": url ? url : "",
                "accuracy": acc,
                "mapVisible": false,
                "sx": 0,
                "sy": 0
            }
            if (idx >= 0) {
                rec.mapVisible = markerModel.get(idx).mapVisible
                rec.sx = markerModel.get(idx).sx
                rec.sy = markerModel.get(idx).sy
                if (!rec.imageUrl.length && markerModel.get(idx).picture === pic)
                    rec.imageUrl = markerModel.get(idx).imageUrl
                markerModel.set(idx, rec)
            } else {
                markerModel.append(rec)
            }
            map.trackLocation(mid, QtPositioning.coordinate(lat, lon))
        }

        for (var j = markerModel.count - 1; j >= 0; j--) {
            var id = markerModel.get(j).mid
            if (!keep[id]) {
                map.removeLocationTracking(id)
                markerModel.remove(j)
            }
        }

        if (root.autoFit && list.length && !root.userMoved)
            root.fitToMarkers()
        else if (!root.autoFit && !root.userMoved
                 && isFinite(root.latitude) && isFinite(root.longitude))
            root.setCenter(root.latitude, root.longitude, root.zoom)

        root.pushAccuracy()
    }

    function scheduleMarkers() {
        if (map.gestureInProgress)
            return
        markerTimer.restart()
    }

    function emptyCollection() {
        return { "type": "FeatureCollection", "features": [] }
    }

    function ensureLayers() {
        if (root.layersReady)
            return
        if (!(map.metersPerPixel > 0) || root.width < 8 || root.height < 8)
            return
        map.addSource("accuracy", {
                           "type": "geojson",
                           "data": root.emptyCollection()
                       })
        map.addLayer("accuracy-circle", { "type": "circle", "source": "accuracy" })
        map.setPaintProperty("accuracy-circle", "circle-radius", 20)
        map.setPaintProperty("accuracy-circle", "circle-color", root.accentHex)
        map.setPaintProperty("accuracy-circle", "circle-opacity", 0.18)
        map.setPaintProperty("accuracy-circle", "circle-stroke-width", 2)
        map.setPaintProperty("accuracy-circle", "circle-stroke-color", root.accentHex)
        root.layersReady = true
        root.pushAccuracy()
        root.scheduleMarkers()
    }

    function pushAccuracy() {
        if (!root.layersReady)
            return
        if (markerModel.count !== 1) {
            map.updateSource("accuracy", {
                                  "type": "geojson",
                                  "data": root.emptyCollection()
                              })
            return
        }
        var m = markerModel.get(0)
        var acc = Number(m.accuracy) || 0
        if (!(acc > 0) || !isFinite(m.lat) || !isFinite(m.lon)) {
            map.updateSource("accuracy", {
                                  "type": "geojson",
                                  "data": root.emptyCollection()
                              })
            return
        }
        var accuracyPx = 20
        if (map.metersPerPixel > 0)
            accuracyPx = Math.max(12, Math.min(root.width * 0.75, acc / map.metersPerPixel))
        map.updateSource("accuracy", {
                              "type": "geojson",
                              "data": {
                                  "type": "Feature",
                                  "properties": {},
                                  "geometry": {
                                      "type": "Point",
                                      "coordinates": [m.lon, m.lat]
                                  }
                              }
                          })
        map.setPaintProperty("accuracy-circle", "circle-radius", accuracyPx)
    }

    function hitMarker(coord, degLatPerPixel, degLonPerPixel) {
        if (!coord || !isFinite(coord.latitude) || !isFinite(coord.longitude))
            return ""
        var thrLat = Math.max(degLatPerPixel || 0.01, 1e-6) * root.avatarSize
        var thrLon = Math.max(degLonPerPixel || 0.01, 1e-6) * root.avatarSize
        var best = ""
        var bestScore = 1e18
        for (var i = 0; i < markerModel.count; i++) {
            var m = markerModel.get(i)
            var dLat = Math.abs(m.lat - coord.latitude)
            var dLon = Math.abs(m.lon - coord.longitude)
            if (dLat > thrLat || dLon > thrLon)
                continue
            var score = (dLat / thrLat) * (dLat / thrLat) + (dLon / thrLon) * (dLon / thrLon)
            if (score < bestScore) {
                bestScore = score
                best = m.mid
            }
        }
        return best
    }

    function applyLocationPixel(id, visible, pixel) {
        var idx = root.modelIndexById(id)
        if (idx < 0)
            return
        markerModel.setProperty(idx, "mapVisible", visible)
        if (visible && pixel) {
            markerModel.setProperty(idx, "sx", pixel.x)
            markerModel.setProperty(idx, "sy", pixel.y)
        }
    }

    onMarkersChanged: root.scheduleMarkers()
    onDashboardChanged: root.scheduleMarkers()
    onAutoFitChanged: root.scheduleMarkers()
    onWidthChanged: root.scheduleMarkers()
    onHeightChanged: root.scheduleMarkers()
    // Do not push lat/lon back into map.center while the user pans — that
    // fights MapLibre's gesture and rubber-bands the camera. External property
    // updates still apply via rebuildMarkers when !userMoved.

    Connections {
        // Avoid binding while dashboard is still undefined (warns onMediaCached).
        target: root.dashboard ? root.dashboard : null
        ignoreUnknownSignals: true
        onMediaCached: {
            for (var i = 0; i < markerModel.count; i++) {
                if (markerModel.get(i).picture === path)
                    markerModel.setProperty(i, "imageUrl", fileUrl)
            }
        }
    }

    Timer {
        id: markerTimer
        interval: 120
        repeat: false
        onTriggered: root.rebuildMarkers()
    }

    Timer {
        id: styleReadyTimer
        interval: 400
        repeat: true
        running: true
        property int tries: 0
        onTriggered: {
            tries += 1
            if (!root.layersReady)
                root.ensureLayers()
            if (root.layersReady || tries >= 25)
                running = false
            if (root.layersReady)
                root.scheduleMarkers()
        }
    }

    MapboxMap {
        id: map
        anchors.fill: parent
        minimumZoomLevel: 3
        maximumZoomLevel: 18
        pixelRatio: Theme.pixelRatio > 0 ? Theme.pixelRatio : 1.0
        styleUrl: "https://tiles.openfreemap.org/styles/liberty"
        cacheDatabaseDefaultPath: true
        cacheDatabaseMaximalSize: 48 * 1024 * 1024

        onCenterChanged: {
            if (isFinite(center.latitude))
                root.latitude = center.latitude
            if (isFinite(center.longitude))
                root.longitude = center.longitude
        }
        onZoomLevelChanged: {
            root.zoom = zoomLevel
            root.pushAccuracy()
        }
        onGestureInProgressChanged: {
            if (gestureInProgress) {
                root.userMoved = true
                markerTimer.stop()
            } else {
                root.scheduleMarkers()
            }
        }
        onMetersPerPixelChanged: {
            if (!root.layersReady && metersPerPixel > 0)
                root.ensureLayers()
            root.pushAccuracy()
        }
        onLocationChanged: root.applyLocationPixel(id, visible, pixel)
        onErrorChanged: console.log("Helmsman MapLibre error:", error)

        Component.onCompleted: {
            // Never seed MapLibre with NaN — that aborts the process on device.
            var lat = isFinite(root.latitude) ? root.latitude : 64.95
            var lon = isFinite(root.longitude) ? root.longitude : 25.75
            var z = isFinite(root.zoom) ? root.zoom : 5
            map.center = QtPositioning.coordinate(lat, lon)
            map.zoomLevel = Math.max(map.minimumZoomLevel,
                                     Math.min(map.maximumZoomLevel, z))
        }

    }

    // Markers above the map; gestures sit above markers so pan/pinch still work.
    Item {
        anchors.fill: parent
        z: 10

        Repeater {
            model: markerModel
            delegate: Item {
                width: root.avatarSize
                height: root.avatarSize + Theme.paddingSmall
                x: model.sx - width / 2
                y: model.sy - height
                visible: model.mapVisible
                z: index + 1

                Item {
                    id: avatarWrap
                    width: root.avatarSize
                    height: width
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: model.imageUrl && model.imageUrl.length

                    RoundedImage {
                        id: avatar
                        anchors.fill: parent
                        source: model.imageUrl
                        sourceSize.width: root.avatarSize * 2
                        fillMode: Image.PreserveAspectCrop
                        cornerRadius: width / 2
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: "white"
                        visible: avatar.status === Image.Ready
                    }
                }

                Rectangle {
                    width: root.avatarSize
                    height: width
                    radius: width / 2
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.highlightColor
                    visible: !avatarWrap.visible || avatar.status !== Image.Ready

                    Label {
                        anchors.centerIn: parent
                        text: model.name && model.name.length
                              ? model.name.charAt(0).toUpperCase() : ""
                        color: "white"
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }
                }

                Rectangle {
                    width: Math.max(2, Math.round(Theme.paddingSmall / 2))
                    height: Theme.paddingSmall
                    color: Theme.highlightColor
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                }
            }
        }
    }

    MapboxMapGestureArea {
        anchors.fill: parent
        z: 20
        map: map
        enabled: root.interactive
        activeClickedGeo: true
        activeDoubleClickedGeo: true
        onClickedGeo: {
            var hit = root.hitMarker(geocoordinate, degLatPerPixel, degLonPerPixel)
            if (hit.length)
                root.markerClicked(hit)
            else
                root.mapClicked()
        }
        onDoubleClickedGeo: {
            map.setZoomLevel(Math.min(map.maximumZoomLevel, map.zoomLevel + 1),
                             Qt.point(map.width / 2, map.height / 2))
        }
    }

    Label {
        anchors.centerIn: parent
        visible: !root.valid && root.layersReady
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeSmall
        z: 20
        text: i18n.translation("waiting_for_location")
    }

    Label {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Theme.paddingSmall
        font.pixelSize: Theme.fontSizeTiny
        color: "#FFFFFF"
        text: i18n.translation("openfreemap")
        style: Text.Outline
        styleColor: Theme.rgba("#000000", 0.7)
        z: 30
    }
}
