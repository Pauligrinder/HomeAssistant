import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: flow
    property var cards: []
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int columns: 12
    property var rows: flow.packRows(flow.cards, flow.columns)

    width: parent ? parent.width : Screen.width
    implicitHeight: column.height
    height: implicitHeight

    function packRows(list, colCount) {
        var src = list || []
        var packed = []
        var row = []
        var used = 0
        for (var i = 0; i < src.length; ++i) {
            var card = src[i]
            if (!card)
                continue
            if (dashboard && !dashboard.cardVisible(card))
                continue
            var span = card._columns ? card._columns : 12
            if (span > colCount)
                span = colCount
            if (used > 0 && used + span > colCount) {
                packed.push(row)
                row = []
                used = 0
            }
            row.push(card)
            used += span
            if (used >= colCount) {
                packed.push(row)
                row = []
                used = 0
            }
        }
        if (row.length)
            packed.push(row)
        return packed
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingSmall

        Repeater {
            model: flow.rows
            Row {
                width: column.width
                spacing: Theme.paddingSmall

                Repeater {
                    model: modelData
                    CardLoader {
                        card: modelData
                        dashboard: flow.dashboard
                        hassClient: flow.hassClient
                        mdiIcons: flow.mdiIcons
                        columns: flow.columns
                        unitWidth: column.width
                    }
                }
            }
        }
    }
}
