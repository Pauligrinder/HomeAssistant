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
    // Re-pack only when visibility or column span changes — not on every entity
    // state tick (that was destroying CardLoaders after MoreInfo).
    readonly property string rowLayoutKey: {
        var _ = flow.rev
        var list = flow.cards || []
        var key = ""
        for (var i = 0; i < list.length; ++i) {
            var c = list[i]
            if (!c)
                continue
            if (flow.dashboard && !flow.dashboard.cardVisible(c))
                key += "h"
            else
                key += "v" + String(c._columns ? c._columns : 12)
            key += ";"
        }
        return key
    }
    property string _cachedRowLayoutKey: ""
    property var _cachedCardsSource: null
    property var _cachedRows: []
    property var rows: flow._cachedRows

    width: parent ? parent.width : Screen.width
    implicitHeight: column.height
    height: implicitHeight

    onRowLayoutKeyChanged: flow.repackRows()
    onCardsChanged: flow.repackRows()
    onColumnsChanged: flow.repackRows()
    Component.onCompleted: flow.repackRows()

    function repackRows() {
        var key = flow.rowLayoutKey + "|" + String(flow.columns)
        var cardsRef = flow.cards
        if (key === flow._cachedRowLayoutKey && flow._cachedRows.length
                && cardsRef === flow._cachedCardsSource)
            return
        flow._cachedRowLayoutKey = key
        flow._cachedCardsSource = cardsRef
        flow._cachedRows = flow.packRows(flow.cards, flow.columns)
    }

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
