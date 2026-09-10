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
    readonly property var entities: {
        if (card && card.entities)
            return card.entities
        return []
    }
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var located: {
        var _ = root.rev
        return root.locateEntities()
    }

    function entityIdOf(value) {
        if (typeof value === "string")
            return value
        return value && value.entity ? String(value.entity) : ""
    }

    function locateEntities() {
        if (!dashboard || root.rev < 0)
            return []
        var list = root.entities.length ? root.entities : []
        var out = []
        for (var i = 0; i < list.length; i++) {
            var id = root.entityIdOf(list[i])
            if (!id.length)
                continue
            var lat = Number(dashboard.attribute(id, "latitude"))
            var lon = Number(dashboard.attribute(id, "longitude"))
            if (!isFinite(lat) || !isFinite(lon) || (lat === 0 && lon === 0)) {
                var gps = dashboard.attribute(id, "gps")
                if (!gps || gps.length < 2)
                    continue
                lat = Number(gps[0] !== undefined ? gps[0] : gps.latitude)
                lon = Number(gps[1] !== undefined ? gps[1] : gps.longitude)
            }
            if (!isFinite(lat) || !isFinite(lon) || (lat === 0 && lon === 0))
                continue
            var pic = dashboard.mediaPathOf(dashboard.attribute(id, "entity_picture"))
            out.push({
                         "id": id,
                         "lat": lat,
                         "lon": lon,
                         "name": dashboard.friendlyName(id),
                         "picture": pic ? pic : ""
                     })
        }
        return out
    }

    Label {
        width: parent.width
        visible: !!(card && card.title) && root.fillHeight <= 0
        text: (card && card.title) ? String(card.title) : ""
        color: Theme.highlightColor
    }

    Item {
        width: parent.width
        height: {
            if (root.fillHeight > 0)
                return root.fillHeight
            return Math.round(width * 0.75)
        }

        EntityMap {
            dashboard: root.dashboard
            markers: root.located
            autoFit: true
            interactive: true
            onMarkerClicked: {
                if (dashboard)
                    dashboard.openMoreInfo(entityId)
            }
        }
    }
}
