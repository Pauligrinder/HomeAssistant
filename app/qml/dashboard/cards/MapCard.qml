import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    contentTopMargin: 0
    contentBottomMargin: fillHeight > 0 ? 0 : Theme.paddingSmall
    contentHorizontalMargin: fillHeight > 0 ? 0 : Theme.paddingMedium
    showBackground: fillHeight <= 0
    // Panel (type: panel) map views fill the page — use MapLibre in-place.
    // Compact cards keep the light raster preview and open MapPage on tap.
    readonly property bool panelMap: root.fillHeight > 0
    readonly property bool showAll: !!(card && card.show_all)
    readonly property bool hasGeoSources: !!(card && card.geo_location_sources
                                             && card.geo_location_sources.length)
    readonly property var entities: {
        var _ = root.rev
        if (!dashboard || !card)
            return []
        return dashboard.mapCardEntities(card)
    }
    property int listTick: 0
    readonly property int rev: root.statesRevision + listTick
    readonly property var located: {
        var _ = root.rev
        return root.locateEntities()
    }

    function entityIdOf(value) {
        if (typeof value === "string")
            return value
        return value && value.entity ? String(value.entity) : ""
    }

    function configNameOf(entityId) {
        if (!card || !card.entities)
            return ""
        var list = card.entities
        for (var i = 0; i < list.length; ++i) {
            var entry = list[i]
            if (typeof entry === "string")
                continue
            if (entry && entry.entity === entityId && entry.name)
                return String(entry.name)
        }
        return ""
    }

    function coordsOf(entityId) {
        var lat = Number(dashboard.attribute(entityId, "latitude"))
        var lon = Number(dashboard.attribute(entityId, "longitude"))
        if (isFinite(lat) && isFinite(lon) && !(lat === 0 && lon === 0))
            return { "lat": lat, "lon": lon }

        var gps = dashboard.attribute(entityId, "gps")
        if (gps) {
            lat = Number(gps[0] !== undefined ? gps[0] : gps.latitude)
            lon = Number(gps[1] !== undefined ? gps[1] : gps.longitude)
            if (isFinite(lat) && isFinite(lon) && !(lat === 0 && lon === 0))
                return { "lat": lat, "lon": lon }
        }

        if (dashboard.domainOf(entityId) !== "person")
            return null
        var inZones = dashboard.attribute(entityId, "in_zones")
        if (!inZones || !inZones.length)
            return null
        for (var i = 0; i < inZones.length; ++i) {
            var zoneId = String(inZones[i] || "")
            if (!zoneId.length)
                continue
            if (dashboard.attribute(zoneId, "passive"))
                continue
            lat = Number(dashboard.attribute(zoneId, "latitude"))
            lon = Number(dashboard.attribute(zoneId, "longitude"))
            if (isFinite(lat) && isFinite(lon) && !(lat === 0 && lon === 0))
                return { "lat": lat, "lon": lon }
        }
        return null
    }

    Connections {
        target: dashboard
        onEntityChanged: {
            if (root.showAll || root.hasGeoSources) {
                root.listTick++
                return
            }
            var list = root.entities
            for (var i = 0; i < list.length; ++i) {
                if (root.entityIdOf(list[i]) === entityId) {
                    root.listTick++
                    return
                }
            }
        }
    }

    function locateEntities() {
        if (!dashboard || root.rev < 0)
            return []
        var list = root.entities
        var out = []
        for (var i = 0; i < list.length; i++) {
            var id = root.entityIdOf(list[i])
            if (!id.length)
                continue
            var coords = root.coordsOf(id)
            if (!coords)
                continue
            var pic = dashboard.mediaPathOf(dashboard.attribute(id, "entity_picture"))
            var name = root.configNameOf(id)
            out.push({
                         "id": id,
                         "lat": coords.lat,
                         "lon": coords.lon,
                         "name": name.length ? name : dashboard.friendlyName(id),
                         "picture": pic ? pic : ""
                     })
        }
        return out
    }

    function openFullscreenMap() {
        if (!pageStack)
            return
        pageStack.push(Qt.resolvedUrl("../../pages/MapPage.qml"), {
                           hassClient: root.hassClient,
                           mdiIcons: root.mdiIcons,
                           markers: root.located,
                           title: (card && card.title) ? String(card.title) : "",
                           autoFit: true
                       })
    }

    Item {
        width: parent.width
        // Prefer chrome height over fillHeight so CardLoader cannot bind-loop
        // fillHeight ↔ contentHeight when this is a panel map.
        height: root.panelMap
                ? Math.max(1, root.height)
                : Math.round(width * 0.75)
        clip: true

        Loader {
            id: mapLoader
            anchors.fill: parent
            // Defer MapLibre until the panel is actually sized; constructing it
            // at fillHeight 0 during layout passes has been crashing on device.
            active: root.panelMap ? root.height > Theme.itemSizeLarge : true
            sourceComponent: root.panelMap ? mapLibreComp : entityMapComp
        }

        Component {
            id: entityMapComp
            Item {
                anchors.fill: parent

                EntityMap {
                    anchors.fill: parent
                    dashboard: root.dashboard
                    markers: root.located
                    autoFit: true
                    interactive: false
                    showZoomControls: false
                    topContentInset: root.topContentInset
                }

                // Above markers: whole-card tap opens MapPage; pins are not links.
                MouseArea {
                    anchors.fill: parent
                    z: 20
                    onClicked: root.openFullscreenMap()
                }
            }
        }

        Component {
            id: mapLibreComp
            MapLibreMap {
                anchors.fill: parent
                dashboard: root.dashboard
                markers: root.located
                autoFit: true
                interactive: true
                topContentInset: root.topContentInset
                onMarkerClicked: {
                    if (root.dashboard)
                        root.dashboard.openMoreInfo(entityId)
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: root.topContentInset
            height: titleLabel.height + 2 * Theme.paddingSmall
            visible: titleLabel.visible
            color: "#000000"
            opacity: 0.55
            z: 5
        }

        Label {
            id: titleLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: root.topContentInset + Theme.paddingSmall
            anchors.leftMargin: Theme.paddingSmall
            anchors.rightMargin: Theme.paddingSmall
            z: 6
            text: (card && card.title) ? String(card.title) : ""
            visible: text.length > 0
            color: "#FFFFFF"
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }
    }
}
