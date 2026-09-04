import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardFlow {
    property var card: ({})
    columns: 12
    cards: sizedCards()

    function sizedCards() {
        var src = (card && card.cards) ? card.cards : []
        var cols = (card && card.columns) ? Number(card.columns) : 3
        if (cols < 1)
            cols = 3
        var span = Math.max(1, Math.floor(12 / cols))
        var square = card && card.square
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var c = src[i] || {}
            if (!c._columns || c._columns === 12)
                c._columns = span
            if (square && !c._rows)
                c._rows = 1
            out.push(c)
        }
        return out
    }
}
