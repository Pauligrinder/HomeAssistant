import QtQuick 2.6
import Sailfish.Silica 1.0

// 24h (or N-hour) history plot for more-info. Numeric entities get a line
// chart; categorical entities get a horizontal state bar.
Item {
    id: root
    property var dashboard
    property string entityId: ""
    property int hours: 24
    property var points: []

    readonly property string unit: {
        if (!dashboard || !root.entityId.length)
            return ""
        var u = dashboard.attribute(root.entityId, "unit_of_measurement")
        return u ? String(u) : ""
    }

    width: parent ? parent.width : 0
    height: chart.height
    visible: chart.hasContent
    clip: true

    function refresh() {
        root.points = []
        if (dashboard && root.entityId.length)
            dashboard.fetchHistory([root.entityId], root.hours > 0 ? root.hours : 24)
    }

    Connections {
        target: dashboard
        onHistoryReady: {
            if (entityId === root.entityId)
                root.points = points
        }
    }

    onEntityIdChanged: root.refresh()
    onDashboardChanged: root.refresh()
    onHoursChanged: root.refresh()
    Component.onCompleted: root.refresh()

    HistoryChart {
        id: chart
        width: parent.width
        points: root.points
        hours: root.hours > 0 ? root.hours : 24
        unit: root.unit
        title: root.hours === 24 ? i18n.translation("last_24_hours")
                                 : i18n.translation("last_hours").arg(root.hours)
        accent: Theme.highlightColor
        chartHeight: Theme.itemSizeExtraLarge
    }
}
