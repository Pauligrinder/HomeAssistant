import QtQuick 2.6
import Sailfish.Silica 1.0

// thomasloven/lovelace-layout-card column engine (horizontal + vertical).
// Columns = max(1, min(floor(avail / width), max_cols)); width defaults to 300,
// so a phone in portrait is almost always a single stacked column — not a
// side-by-side CardFlow row.
Item {
    id: root
    property var view: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    // "horizontal" — next card goes to the next column (round-robin).
    // "vertical"   — next card stays in the same column until layout-break.
    property string mode: "horizontal"

    readonly property var layoutOpts: {
        if (!view)
            return ({})
        if (view.layout && typeof view.layout === "object")
            return view.layout
        return ({})
    }
    readonly property int configuredWidth: {
        var w = Number(root.layoutOpts.width)
        return (isFinite(w) && w > 0) ? Math.round(w) : 300
    }
    readonly property int configuredMaxWidth: {
        var m = Number(root.layoutOpts.max_width)
        if (isFinite(m) && m > 0)
            return Math.round(m)
        if (root.layoutOpts.width !== undefined && root.layoutOpts.width !== null
                && String(root.layoutOpts.width).length)
            return Math.ceil(root.configuredWidth * 1.5)
        return 500
    }
    readonly property int configuredMaxCols: {
        var m = Number(root.layoutOpts.max_cols)
        return (isFinite(m) && m > 0) ? Math.round(m) : 4
    }
    readonly property bool rtl: !!(root.layoutOpts.rtl === true
                                  || root.layoutOpts.rtl === "true")
    readonly property int columnCount: {
        // Match base-column-layout.ts _updateSize().
        var avail = Math.max(1, Math.floor(root.width))
        var n = Math.floor(avail / root.configuredWidth)
        n = Math.min(n, root.configuredMaxCols)
        return Math.max(1, n)
    }
    // Effective per-column width. On a single-column phone, grow to the view
    // width (layout-card raises max-width under the 2×width media query).
    readonly property int columnPixelWidth: {
        var gaps = Math.max(0, root.columnCount - 1) * Theme.paddingMedium
        var avail = Math.max(1, Math.floor(root.width - gaps))
        var share = Math.floor(avail / root.columnCount)
        var maxW = root.configuredMaxWidth
        if (root.columnCount === 1)
            maxW = Math.max(maxW, root.configuredWidth * 2)
        return Math.max(1, Math.min(share, maxW))
    }
    // Rebuild when width-derived column count or the card list changes.
    readonly property int placeRevision: {
        var _ = root.columnCount
        var __ = root.dashboard ? root.dashboard.statesRevision : 0
        var cards = (root.view && root.view.cards) ? root.view.cards : []
        return cards.length + _ * 1000 + (__ % 1000)
    }
    property var columnCards: []

    width: parent ? parent.width : Screen.width
    implicitHeight: columnsRow.height
    height: implicitHeight

    onPlaceRevisionChanged: root.rebuildColumns()
    onModeChanged: root.rebuildColumns()
    onWidthChanged: root.rebuildColumns()
    Component.onCompleted: root.rebuildColumns()

    function isBreak(card) {
        if (!card)
            return false
        return String(card.type || "") === "custom:layout-break"
    }

    function isGap(card) {
        if (!card)
            return false
        return String(card.type || "") === "custom:gap-card"
    }

    function cardColumnHint(card) {
        if (!card)
            return 0
        var vl = card.view_layout
        if (!vl || typeof vl !== "object")
            return 0
        var col = Number(vl.column)
        if (!isFinite(col) || col < 1)
            return 0
        return Math.round(col)
    }

    function visibleCards() {
        var src = (root.view && root.view.cards) ? root.view.cards : []
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var c = src[i]
            if (!c)
                continue
            if (root.dashboard && !root.dashboard.cardVisible(c))
                continue
            out.push(c)
        }
        return out
    }

    function rebuildColumns() {
        var n = root.columnCount
        var cols = []
        var c
        for (c = 0; c < n; ++c)
            cols.push([])

        var cards = root.visibleCards()
        if (root.mode === "vertical") {
            // vertical.ts: stay on column i until layout-break advances.
            var vi = 1
            for (var v = 0; v < cards.length; ++v) {
                var vc = cards[v]
                var vHint = root.cardColumnHint(vc)
                if (vHint > 0)
                    vi = vHint
                if (root.isBreak(vc)) {
                    vi = vi + 1
                    continue
                }
                cols[(vi - 1) % n].push(vc)
            }
        } else {
            // horizontal.ts: i starts at 0, increments before place, break resets.
            var hi = 0
            for (var h = 0; h < cards.length; ++h) {
                var hc = cards[h]
                hi += 1
                var hHint = root.cardColumnHint(hc)
                if (hHint > 0)
                    hi = hHint
                if (root.isBreak(hc)) {
                    hi = 0
                    continue
                }
                cols[(hi - 1) % n].push(hc)
            }
        }

        var packed = []
        for (c = 0; c < cols.length; ++c) {
            if (cols[c].length)
                packed.push(cols[c])
        }
        if (root.rtl)
            packed.reverse()
        root.columnCards = packed
    }

    Row {
        id: columnsRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.paddingMedium
        width: {
            var n = Math.max(1, root.columnCards.length)
            return n * root.columnPixelWidth
                    + Math.max(0, n - 1) * spacing
        }

        Repeater {
            model: root.columnCards

            Column {
                id: column
                width: root.columnPixelWidth
                spacing: Theme.paddingMedium

                Repeater {
                    model: modelData

                    Item {
                        id: cell
                        width: column.width
                        height: gap.visible ? gap.height : cardLoader.height
                        property var entry: modelData

                        CardLoader {
                            id: cardLoader
                            visible: !root.isGap(cell.entry)
                            width: cell.width
                            unitWidth: width
                            columns: 12
                            card: {
                                var c = cell.entry || ({})
                                // Full column width — ignore sections-grid spans.
                                c._columns = 12
                                return c
                            }
                            dashboard: root.dashboard
                            hassClient: root.hassClient
                            mdiIcons: root.mdiIcons
                        }

                        Item {
                            id: gap
                            visible: root.isGap(cell.entry)
                            width: cell.width
                            height: {
                                if (!visible)
                                    return 0
                                var h = Number(cell.entry && cell.entry.height)
                                if (isFinite(h) && h > 0)
                                    return h
                                return 50
                            }
                        }
                    }
                }
            }
        }
    }
}
