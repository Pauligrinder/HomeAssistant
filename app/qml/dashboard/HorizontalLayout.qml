import QtQuick 2.6
import Sailfish.Silica 1.0

// layout-card's custom:horizontal-layout and similar: pack cards into wrapping
// equal-width rows instead of the default full-width masonry stack.
CardFlow {
    id: layout
    property var view: ({})
    columns: 12
    cards: layout.sizedCards()

    function sizedCards() {
        var src = (view && view.cards) ? view.cards : []
        var n = Math.max(1, src.length)
        // Cap per-row count so a long dashboard still wraps instead of
        // squeezing every card into a single unreadably narrow row.
        var perRow = Math.min(n, 4)
        var span = Math.max(1, Math.floor(12 / perRow))
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var c = src[i] || {}
            c._columns = span
            out.push(c)
        }
        return out
    }
}
