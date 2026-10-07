import QtQuick 2.6
import Sailfish.Silica 1.0
import harbour.helmsman 1.0
import "../dashboard"

Page {
    id: page
    property var hassClient
    property var mdiIcons
    property string entityId: ""
    property int hours: 24
    property var dashboard: hassClient ? hassClient.lovelace : null
    property var points: []
    property bool loading: true

    readonly property var periods: {
        var src = page.points
        return page.buildPeriods(src)
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.periods
        spacing: Theme.paddingMedium
        header: PageHeader {
            title: i18n.translation("history")
            description: page.hours === 24 ? i18n.translation("last_24_hours")
                                           : i18n.translation("last_hours").arg(page.hours)
        }

        ViewPlaceholder {
            enabled: !page.loading && page.periods.length === 0
            text: i18n.translation("no_history")
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && page.periods.length === 0
        }

        delegate: Item {
            id: row
            width: list.width
            height: Math.max(card.implicitHeight, Theme.itemSizeMedium)

            readonly property string stateValue: String(modelData.state || "")
            readonly property var startDate: modelData.start
            readonly property var endDate: modelData.end
            readonly property bool isZone: page.isZoneState(row.stateValue)
            readonly property string zoneIcon: page.zoneIconFor(row.stateValue)
            readonly property color accent: page.colorForState(row.stateValue)

            // Timeline rail
            Rectangle {
                id: rail
                anchors.top: index === 0 ? dot.verticalCenter : parent.top
                anchors.bottom: index === list.count - 1 ? dot.verticalCenter : parent.bottom
                x: Theme.horizontalPageMargin + Theme.paddingSmall
                width: Math.max(2, Math.round(Theme.paddingSmall / 2))
                color: Theme.rgba(Theme.secondaryColor, 0.4)
            }

            Rectangle {
                id: dot
                width: Theme.paddingMedium + Theme.paddingSmall
                height: width
                radius: width / 2
                anchors.horizontalCenter: rail.horizontalCenter
                anchors.top: card.top
                anchors.topMargin: Theme.paddingLarge
                color: row.accent
                border.width: 2
                border.color: Theme.rgba(Theme.primaryColor, 0.25)
            }

            Rectangle {
                id: card
                anchors.left: rail.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: contentCol.height + Theme.paddingMedium * 2
                radius: Theme.paddingMedium
                color: Theme.rgba(row.accent, Theme.colorScheme === Theme.LightOnDark
                                               ? 0.28 : 0.18)
                border.width: 1
                border.color: Theme.rgba(row.accent, 0.55)

                Row {
                    id: contentCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.rightMargin: Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingMedium

                    MdiIcon {
                        visible: row.zoneIcon.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        mdiIcons: page.mdiIcons
                        name: row.zoneIcon
                        width: Theme.iconSizeSmall
                        height: width
                        iconColor: row.accent
                    }

                    Label {
                        width: Math.max(0, contentCol.width
                                        - (row.zoneIcon.length > 0
                                           ? Theme.iconSizeSmall + Theme.paddingMedium
                                           : 0))
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.Wrap
                        color: Theme.primaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        text: page.formatPeriod(row.stateValue, row.startDate, row.endDate)
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }

    Connections {
        target: dashboard
        onHistoryReady: {
            if (entityId !== page.entityId)
                return
            page.points = points
            page.loading = false
        }
    }

    onEntityIdChanged: page.refresh()
    onDashboardChanged: page.refresh()
    Component.onCompleted: page.refresh()

    function refresh() {
        page.points = []
        page.loading = true
        if (dashboard && page.entityId.length)
            dashboard.fetchHistory([page.entityId], page.hours > 0 ? page.hours : 24)
        else
            page.loading = false
    }

    function parseTime(stamp) {
        if (!stamp)
            return null
        if (stamp instanceof Date)
            return isNaN(stamp.getTime()) ? null : stamp
        var t = Date.parse(stamp)
        return isNaN(t) ? null : new Date(t)
    }

    function buildPeriods(src) {
        src = src || []
        var out = []
        var now = new Date()
        for (var i = 0; i < src.length; ++i) {
            var start = page.parseTime(src[i].last_changed)
            if (!start)
                continue
            var end = (i + 1 < src.length)
                      ? page.parseTime(src[i + 1].last_changed) : now
            if (!end)
                end = now
            out.push({
                         "state": src[i].state,
                         "start": start,
                         "end": end
                     })
        }
        out.reverse()
        return out
    }

    function prettyState(state) {
        var s = String(state || "")
        if (!s.length)
            return i18n.translation("unknown")
        if (s === "unavailable")
            return i18n.translation("unavailable")
        if (s === "unknown")
            return i18n.translation("unknown")
        s = s.replace(/_/g, " ")
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
                && a.getMonth() === b.getMonth()
                && a.getDate() === b.getDate()
    }

    function dayLabel(d) {
        return Qt.formatDate(d, "d MMM")
    }

    function timeLabel(d) {
        return Qt.formatTime(d, "hh:mm")
    }

    function formatRange(start, end) {
        if (!start || !end)
            return ""
        var today = new Date()
        var startTime = page.timeLabel(start)
        var endTime = page.timeLabel(end)
        if (page.sameDay(start, end)) {
            if (page.sameDay(start, today))
                return startTime + " - " + endTime
            return page.dayLabel(start) + " " + startTime + " - " + endTime
        }
        return page.dayLabel(start) + " " + startTime
                + " - " + page.dayLabel(end) + " " + endTime
    }

    function formatPeriod(state, start, end) {
        return page.prettyState(state) + " - " + page.formatRange(start, end)
    }

    function zoneEntityId(state) {
        var s = String(state || "")
        if (!s.length || s === "not_home" || s === "unavailable" || s === "unknown")
            return ""
        if (s === "home")
            return "zone.home"
        if (!dashboard)
            return "zone." + s
        var direct = "zone." + s
        var ent = dashboard.entity(direct)
        if (ent && (ent.state !== undefined || ent.entity_id))
            return direct
        var slug = "zone." + s.toLowerCase().replace(/ /g, "_")
        ent = dashboard.entity(slug)
        if (ent && (ent.state !== undefined || ent.entity_id))
            return slug
        var zones = dashboard.zones() || []
        for (var i = 0; i < zones.length; ++i) {
            var z = zones[i]
            if (!z)
                continue
            var id = String(z.entity_id || "")
            var attrs = z.attributes || {}
            var name = String(attrs.friendly_name || attrs.name || "")
            if (name === s || name.toLowerCase() === s.toLowerCase())
                return id
            if (id === direct || id === slug)
                return id
        }
        return slug
    }

    function isZoneState(state) {
        if (!dashboard)
            return false
        var id = page.zoneEntityId(state)
        if (!id.length)
            return false
        if (id === "zone.home")
            return true
        var ent = dashboard.entity(id)
        return !!(ent && (ent.state !== undefined || ent.entity_id))
    }

    function zoneIconFor(state) {
        var s = String(state || "")
        if (s === "home") {
            if (dashboard) {
                var homeIcon = dashboard.attribute("zone.home", "icon")
                if (homeIcon)
                    return String(homeIcon)
            }
            return "mdi:home"
        }
        if (s === "not_home")
            return "mdi:home-off"
        if (!page.isZoneState(s))
            return ""
        if (dashboard) {
            var icon = dashboard.attribute(page.zoneEntityId(s), "icon")
            if (icon)
                return String(icon)
        }
        return "mdi:map-marker-radius"
    }

    function colorForState(state) {
        var s = String(state || "").toLowerCase()
        if (s === "home" || s === "on" || s === "open" || s === "unlocked"
                || s === "active" || s === "playing" || s === "detected"
                || s === "occupied" || s === "wet" || s === "motion")
            return "#7CFC00"
        if (s === "not_home" || s === "off" || s === "closed" || s === "locked"
                || s === "idle" || s === "standby" || s === "clear" || s === "dry"
                || s === "empty")
            return "#FF5555"
        if (s === "unavailable" || s === "unknown")
            return Theme.secondaryColor
        if (page.isZoneState(state))
            return "#FFD700"
        // Stable tint from state text so categorical values stay distinct.
        var hash = 0
        for (var i = 0; i < s.length; ++i)
            hash = ((hash << 5) - hash) + s.charCodeAt(i)
        var hue = Math.abs(hash) % 360
        return Qt.hsla(hue / 360, 0.55, 0.45, 1)
    }
}
