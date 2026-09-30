import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    property var pointsByEntity: ({})
    readonly property int hours: {
        if (card && card.hours_to_show)
            return Math.max(1, Number(card.hours_to_show) || 24)
        return 24
    }
    readonly property var entityEntries: {
        if (card && card.entities)
            return card.entities
        if (card && card.entity)
            return [card.entity]
        return []
    }
    readonly property var entityIds: {
        var list = root.entityEntries
        var out = []
        for (var i = 0; i < list.length; ++i) {
            var id = root.entityIdOf(list[i])
            if (id.length)
                out.push(id)
        }
        return out
    }
    readonly property bool showNames: !(card && card.show_names === false)

    function entityIdOf(entry) {
        if (typeof entry === "string")
            return entry
        if (entry && entry.entity)
            return String(entry.entity)
        return ""
    }

    function entityName(entry, entityId) {
        if (entry && typeof entry === "object" && entry.name)
            return String(entry.name)
        if (dashboard)
            return dashboard.friendlyName(entityId)
        return entityId
    }

    function entityColor(entry) {
        if (entry && typeof entry === "object" && entry.color)
            return String(entry.color)
        return Theme.highlightColor
    }

    function entityUnit(entityId) {
        if (!dashboard || !entityId.length)
            return ""
        var u = dashboard.attribute(entityId, "unit_of_measurement")
        return u ? String(u) : ""
    }

    function pointsFor(entityId) {
        var map = root.pointsByEntity
        return (map && map[entityId]) ? map[entityId] : []
    }

    Connections {
        target: dashboard
        onHistoryReady: {
            if (root.entityIds.indexOf(entityId) < 0)
                return
            var next = {}
            var map = root.pointsByEntity || {}
            for (var key in map) {
                if (map.hasOwnProperty(key))
                    next[key] = map[key]
            }
            next[entityId] = points
            root.pointsByEntity = next
        }
    }

    Component.onCompleted: root.refresh()
    onEntityIdsChanged: root.refresh()
    onHoursChanged: root.refresh()

    function refresh() {
        root.pointsByEntity = ({})
        if (dashboard && root.entityIds.length)
            dashboard.fetchHistory(root.entityIds, root.hours)
    }

    Label {
        width: parent.width
        visible: !!(card && card.title)
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Repeater {
        model: root.entityEntries
        HistoryChart {
            width: parent.width
            points: root.pointsFor(root.entityIdOf(modelData))
            hours: root.hours
            unit: root.entityUnit(root.entityIdOf(modelData))
            title: root.showNames
                   ? root.entityName(modelData, root.entityIdOf(modelData)) : ""
            accent: root.entityColor(modelData)
            showTitle: root.showNames
            chartHeight: Theme.itemSizeExtraLarge
        }
    }

    Label {
        width: parent.width
        visible: {
            if (!root.entityIds.length)
                return true
            var map = root.pointsByEntity || {}
            for (var i = 0; i < root.entityIds.length; ++i) {
                var pts = map[root.entityIds[i]]
                if (pts && pts.length)
                    return false
            }
            return true
        }
        text: qsTr("No history")
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
        horizontalAlignment: Text.AlignHCenter
    }
}
