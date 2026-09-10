import QtQuick 2.6
import QtGraphicalEffects 1.0
import Sailfish.Silica 1.0

// Raster OSM tiles fetched through LovelaceCoordinator so the request has a
// real User-Agent. Qt Location's osm plugin is a blank grey box on Sailfish.
Item {
    id: root
    anchors.fill: parent
    property var dashboard
    property real latitude: NaN
    property real longitude: NaN
    property real accuracy: 0
    property var markers: []
    property bool autoFit: false
    property bool interactive: true
    property int zoom: 15
    property int tileSize: 256
    property string tileKey: ""
    property real centerLat: NaN
    property real centerLon: NaN
    property bool userZoomed: false

    readonly property real viewLat: (root.autoFit && isFinite(root.centerLat))
                                    ? root.centerLat : root.latitude
    readonly property real viewLon: (root.autoFit && isFinite(root.centerLon))
                                    ? root.centerLon : root.longitude
    readonly property bool valid: isFinite(root.viewLat) && isFinite(root.viewLon)
                                  && Math.abs(root.viewLat) <= 90
                                  && Math.abs(root.viewLon) <= 180
    readonly property int avatarSize: Theme.iconSizeMedium

    signal markerClicked(string entityId)

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

    function wrapTileX(x, z) {
        var n = Math.pow(2, z)
        return ((Math.floor(x) % n) + n) % n
    }

    function tilePath(x, y, z) {
        return "https://tile.openstreetmap.org/" + z + "/"
                + root.wrapTileX(x, z) + "/" + y + ".png"
    }

    function metersPerPixel() {
        if (!root.valid)
            return 1
        return 156543.03392 * Math.cos(root.viewLat * Math.PI / 180.0)
                / Math.pow(2, root.zoom)
    }

    function markerX(lat, lon) {
        return root.width / 2
                + (root.lon2tile(lon, root.zoom) - root.lon2tile(root.viewLon, root.zoom))
                * root.tileSize
    }

    function markerY(lat, lon) {
        return root.height / 2
                + (root.lat2tile(lat, root.zoom) - root.lat2tile(root.viewLat, root.zoom))
                * root.tileSize
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

    function zoomToFit(pts) {
        if (!pts.length)
            return 15
        if (pts.length === 1)
            return 15
        var pad = Math.max(root.avatarSize * 2, Math.min(root.width, root.height) * 0.12)
        var availW = Math.max(32, root.width - 2 * pad)
        var availH = Math.max(32, root.height - 2 * pad)
        for (var z = 17; z >= 2; z--) {
            var minX = Infinity
            var maxX = -Infinity
            var minY = Infinity
            var maxY = -Infinity
            for (var i = 0; i < pts.length; i++) {
                var x = root.lon2tile(pts[i].lon, z) * root.tileSize
                var y = root.lat2tile(pts[i].lat, z) * root.tileSize
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
        root.centerLon = (minLon + maxLon) / 2
        root.centerLat = root.tile2lat((root.lat2tile(minLat, 20) + root.lat2tile(maxLat, 20)) / 2, 20)
        if (!root.userZoomed)
            root.zoom = root.zoomToFit(pts)
    }

    function rebuildMarkers() {
        var list = root.sortedMarkers()
        while (markerModel.count > list.length)
            markerModel.remove(markerModel.count - 1)
        for (var i = 0; i < list.length; i++) {
            var m = list[i]
            var pic = m.picture ? String(m.picture) : ""
            var url = (pic.length && dashboard) ? dashboard.cachedMediaUrl(pic) : ""
            if (i < markerModel.count && markerModel.get(i).picture === pic
                    && markerModel.get(i).imageUrl && !url)
                url = markerModel.get(i).imageUrl
            if (pic.length && dashboard && !url)
                dashboard.prefetchMedia(pic)
            var mid = String(m.id || "")
            var lat = Number(m.lat)
            var lon = Number(m.lon)
            var name = String(m.name || "")
            var acc = Number(m.accuracy) || 0
            if (i < markerModel.count) {
                markerModel.setProperty(i, "mid", mid)
                markerModel.setProperty(i, "lat", lat)
                markerModel.setProperty(i, "lon", lon)
                markerModel.setProperty(i, "name", name)
                markerModel.setProperty(i, "picture", pic)
                if (url)
                    markerModel.setProperty(i, "imageUrl", url)
                else if (markerModel.get(i).picture !== pic)
                    markerModel.setProperty(i, "imageUrl", "")
                markerModel.setProperty(i, "accuracy", acc)
            } else {
                markerModel.append({
                                       "mid": mid,
                                       "lat": lat,
                                       "lon": lon,
                                       "name": name,
                                       "picture": pic,
                                       "imageUrl": url ? url : "",
                                       "accuracy": acc
                                   })
            }
        }
        if (root.autoFit)
            root.fitToMarkers()
        root.scheduleRebuild()
    }

    function rebuildTiles() {
        if (!root.valid || root.width < 8 || root.height < 8)
            return
        var z = root.zoom
        var n = Math.pow(2, z)
        var cx = root.lon2tile(root.viewLon, z)
        var cy = root.lat2tile(root.viewLat, z)
        var minX = Math.floor(cx - root.width / (2 * root.tileSize)) - 1
        var maxX = Math.floor(cx + root.width / (2 * root.tileSize)) + 1
        var minY = Math.max(0, Math.floor(cy - root.height / (2 * root.tileSize)) - 1)
        var maxY = Math.min(n - 1, Math.floor(cy + root.height / (2 * root.tileSize)) + 1)
        var key = z + ":" + minX + ":" + maxX + ":" + minY + ":" + maxY
        if (key === root.tileKey && tileModel.count > 0)
            return
        root.tileKey = key
        tileModel.clear()
        for (var x = minX; x <= maxX; x++) {
            for (var y = minY; y <= maxY; y++) {
                var path = root.tilePath(x, y, z)
                var cached = dashboard ? dashboard.cachedMediaUrl(path) : ""
                tileModel.append({
                                     "tx": x,
                                     "ty": y,
                                     "path": path,
                                     "imageUrl": cached ? cached : ""
                                 })
                if (dashboard && !(cached && cached.length))
                    dashboard.prefetchMedia(path)
            }
        }
    }

    function scheduleRebuild() {
        rebuildTimer.restart()
    }

    function scheduleMarkers() {
        markerTimer.restart()
    }

    onValidChanged: root.scheduleRebuild()
    onViewLatChanged: root.scheduleRebuild()
    onViewLonChanged: root.scheduleRebuild()
    onZoomChanged: {
        root.tileKey = ""
        root.scheduleRebuild()
    }
    onWidthChanged: {
        if (root.autoFit)
            root.scheduleMarkers()
        else
            root.scheduleRebuild()
    }
    onHeightChanged: {
        if (root.autoFit)
            root.scheduleMarkers()
        else
            root.scheduleRebuild()
    }
    onDashboardChanged: {
        root.tileKey = ""
        root.scheduleMarkers()
    }
    onMarkersChanged: root.scheduleMarkers()
    onAutoFitChanged: root.scheduleMarkers()
    Component.onCompleted: root.scheduleMarkers()

    Timer {
        id: rebuildTimer
        interval: 40
        repeat: false
        onTriggered: root.rebuildTiles()
    }

    Timer {
        id: markerTimer
        interval: 40
        repeat: false
        onTriggered: root.rebuildMarkers()
    }

    ListModel {
        id: tileModel
    }

    ListModel {
        id: markerModel
    }

    Connections {
        target: dashboard
        onMediaCached: {
            var i
            for (i = 0; i < tileModel.count; i++) {
                if (tileModel.get(i).path === path) {
                    tileModel.setProperty(i, "imageUrl", fileUrl)
                    break
                }
            }
            for (i = 0; i < markerModel.count; i++) {
                if (markerModel.get(i).picture === path) {
                    markerModel.setProperty(i, "imageUrl", fileUrl)
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
        clip: true

        Repeater {
            model: tileModel
            Image {
                width: root.tileSize
                height: root.tileSize
                sourceSize.width: root.tileSize
                sourceSize.height: root.tileSize
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                source: model.imageUrl
                x: Math.round((model.tx - root.lon2tile(root.viewLon, root.zoom))
                              * root.tileSize + root.width / 2)
                y: Math.round((model.ty - root.lat2tile(root.viewLat, root.zoom))
                              * root.tileSize + root.height / 2)
            }
        }

        Rectangle {
            visible: root.valid && markerModel.count <= 1 && root.accuracy > 0
            width: Math.max(8, root.accuracy / Math.max(0.5, root.metersPerPixel()) * 2)
            height: width
            radius: width / 2
            x: root.width / 2 - width / 2
            y: root.height / 2 - height / 2
            color: Theme.rgba(Theme.highlightColor, 0.18)
            border.color: Theme.highlightColor
            border.width: 2
        }

        Repeater {
            model: markerModel
            Item {
                width: root.avatarSize
                height: root.avatarSize + Theme.paddingSmall
                visible: isFinite(model.lat) && isFinite(model.lon)
                x: root.markerX(model.lat, model.lon) - width / 2
                y: root.markerY(model.lat, model.lon) - height
                z: index + 1

                Item {
                    id: avatarWrap
                    width: root.avatarSize
                    height: width
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: model.imageUrl && model.imageUrl.length

                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: model.imageUrl
                        sourceSize.width: root.avatarSize * 2
                        sourceSize.height: root.avatarSize * 2
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        layer.enabled: status === Image.Ready
                        layer.effect: OpacityMask { maskSource: avatarMask }
                    }

                    Rectangle {
                        id: avatarMask
                        anchors.fill: parent
                        radius: width / 2
                        visible: false
                        layer.enabled: true
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
                        text: model.name && model.name.length ? model.name.charAt(0).toUpperCase() : ""
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

                MouseArea {
                    anchors.fill: parent
                    enabled: root.interactive && model.mid && model.mid.length
                    preventStealing: true
                    onClicked: root.markerClicked(model.mid)
                }
            }
        }

        Column {
            visible: root.valid && markerModel.count === 0
            x: root.width / 2 - width / 2
            y: root.height / 2 - height
            Rectangle {
                width: Theme.iconSizeSmall
                height: width
                radius: width / 2
                color: Theme.highlightColor
                anchors.horizontalCenter: parent.horizontalCenter
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.35
                    height: width
                    radius: width / 2
                    color: "white"
                }
            }
            Rectangle {
                width: Math.max(2, Math.round(Theme.paddingSmall / 2))
                height: Theme.paddingMedium
                color: Theme.highlightColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: !root.valid
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeSmall
        text: "Waiting for location…"
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.paddingSmall
        spacing: Theme.paddingSmall

        IconButton {
            icon.source: "image://theme/icon-m-remove"
            enabled: root.zoom > 3
            onClicked: {
                root.userZoomed = true
                root.zoom = Math.max(3, root.zoom - 1)
            }
        }
        IconButton {
            icon.source: "image://theme/icon-m-add"
            enabled: root.zoom < 19
            onClicked: {
                root.userZoomed = true
                root.zoom = Math.min(19, root.zoom + 1)
            }
        }
    }

    Label {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Theme.paddingSmall
        font.pixelSize: Theme.fontSizeTiny
        color: Theme.secondaryColor
        text: "© OpenStreetMap"
    }
}
