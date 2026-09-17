import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: flow
    property var cards: []
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    property int columns: 12
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    property var rows: flow.packRows(flow.cards, flow.columns, flow.rev)

    width: parent ? parent.width : Screen.width
    implicitHeight: column.height
    height: implicitHeight

    // rev is unused here beyond forcing a re-pack when card visibility
    // conditions change with entity state.
    function packRows(list, colCount, rev) {
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
        spacing: Theme.paddingMedium

        Repeater {
            model: flow.rows
            Row {
                id: cardRow
                width: column.width
                spacing: Theme.paddingMedium
                property int maxNatural: 0

                function refreshRowHeight() {
                    var h = 0
                    for (var i = 0; i < rowRepeater.count; ++i) {
                        var child = rowRepeater.itemAt(i)
                        if (child && child.naturalHeight)
                            h = Math.max(h, child.naturalHeight)
                    }
                    if (cardRow.maxNatural !== h)
                        cardRow.maxNatural = h
                }

                Repeater {
                    id: rowRepeater
                    model: modelData
                    CardLoader {
                        card: modelData
                        dashboard: flow.dashboard
                        hassClient: flow.hassClient
                        mdiIcons: flow.mdiIcons
                        columns: flow.columns
                        unitWidth: column.width
                        rowHeight: cardRow.maxNatural
                        onNaturalHeightChanged: cardRow.refreshRowHeight()
                        Component.onCompleted: cardRow.refreshRowHeight()
                        Component.onDestruction: cardRow.refreshRowHeight()
                    }
                }
            }
        }
    }
}
