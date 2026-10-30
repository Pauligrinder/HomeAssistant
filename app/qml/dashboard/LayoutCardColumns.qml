import QtQuick 2.6
import Sailfish.Silica 1.0

// thomasloven/lovelace-layout-card column engine (horizontal + vertical).
// layout-card measures getBoundingClientRect() in CSS px (width default 300).
// Sailfish QML is denser: AtlanticDashboardWebView uses pixelRatio * 1.2 as the
// CSS↔panel scale. pixelRatio alone left phones at floor(~650/300)=2 columns
// while the webview (same scale) stayed at 1.
Item {
    id: root
    property var view: ({})
    // When embedded as a card (CardLoader), the config arrives as `card`.
    property var card: null
    property var dashboard
    property var hassClient
    property var mdiIcons
    // "horizontal" — next card goes to the next column (round-robin).
    // "vertical"   — next card stays in the same column until layout-break.
    property string mode: "horizontal"

    // Same factor as AtlanticDashboardWebView.contentScale.
    readonly property real cssScale: Math.max(Theme.pixelRatio, 1.0) * 1.2
    readonly property var config: {
        if (root.card && typeof root.card === "object")
            return root.card
        if (root.view && typeof root.view === "object")
            return root.view
        return ({})
    }
    readonly property var layoutOpts: {
        if (root.config.layout && typeof root.config.layout === "object")
            return root.config.layout
        return ({})
    }
    // Configured sizes are CSS pixels from layout-card.
    readonly property int configuredWidthCss: {
        var w = Number(root.layoutOpts.width)
        return (isFinite(w) && w > 0) ? Math.round(w) : 300
    }
    readonly property int configuredMaxWidthCss: {
        var m = Number(root.layoutOpts.max_width)
        if (isFinite(m) && m > 0)
            return Math.round(m)
        if (root.layoutOpts.width !== undefined && root.layoutOpts.width !== null
                && String(root.layoutOpts.width).length)
            return Math.ceil(root.configuredWidthCss * 1.5)
        return 500
    }
    readonly property int configuredMaxCols: {
        var m = Number(root.layoutOpts.max_cols)
        return (isFinite(m) && m > 0) ? Math.round(m) : 4
    }
    readonly property bool rtl: !!(root.layoutOpts.rtl === true
                                  || root.layoutOpts.rtl === "true")
    // layout-card defaults: margin "0px 4px 0px 4px", padding "4px 0px 4px 0px".
    readonly property real horizontalChromeCss: {
        return root.boxHorizontalCss(root.layoutOpts.margin, 4, 4)
                + root.boxHorizontalCss(root.layoutOpts.padding, 0, 0)
    }
    readonly property int columnCount: {
        // Fit n columns of (width * cssScale) plus inter-column gaps and the
        // layout margin/padding chrome — not raw floor(qmlWidth/scale/300),
        // which over-counted on HD phones (2 cols vs web's 1).
        var gap = Theme.paddingMedium
        var chrome = root.horizontalChromeCss * root.cssScale
        var colQml = root.configuredWidthCss * root.cssScale
        var avail = Math.max(0, root.width - chrome)
        var stride = colQml + gap
        if (stride < 1)
            stride = 1
        // n * colQml + (n - 1) * gap <= avail  →  n <= (avail + gap) / stride
        var n = Math.floor((avail + gap) / stride)
        n = Math.min(n, root.configuredMaxCols)
        return Math.max(1, n)
    }
    // Per-column width in QML px. One column fills the view (layout-card uses
    // width:100% with max-width only capping multi-column growth).
    readonly property int columnPixelWidth: {
        var gap = Theme.paddingMedium
        var chrome = root.horizontalChromeCss * root.cssScale
        var gaps = Math.max(0, root.columnCount - 1) * gap
        var avail = Math.max(1, Math.floor(root.width - chrome - gaps))
        var share = Math.floor(avail / root.columnCount)
        if (root.columnCount === 1)
            return Math.max(1, share)
        var maxW = Math.round(root.configuredMaxWidthCss * root.cssScale)
        return Math.max(1, Math.min(share, maxW))
    }
    // Rebuild when width-derived column count or the card list changes.
    readonly property int placeRevision: {
        var _ = root.columnCount
        var __ = root.dashboard ? root.dashboard.statesRevision : 0
        var cards = root.config.cards || []
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

    // Sum of left+right from a CSS box shorthand (px/unitless). Defaults when
    // unset match layout-card (margin 4+4, padding 0+0 horizontally).
    function boxHorizontalCss(value, defaultLeft, defaultRight) {
        if (value === undefined || value === null || value === "")
            return defaultLeft + defaultRight
        if (typeof value === "number") {
            if (!isFinite(value) || value < 0)
                return defaultLeft + defaultRight
            return value * 2
        }
        var parts = String(value).trim().split(/\s+/)
        function pxPart(s) {
            var n = parseFloat(s)
            return (isFinite(n) && n >= 0) ? n : 0
        }
        if (parts.length === 1)
            return 2 * pxPart(parts[0])
        if (parts.length === 2 || parts.length === 3)
            return 2 * pxPart(parts[1])
        if (parts.length >= 4)
            return pxPart(parts[3]) + pxPart(parts[1])
        return defaultLeft + defaultRight
    }

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
        var src = root.config.cards || []
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
                            fillHeight: 0
                            panelMap: false
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
