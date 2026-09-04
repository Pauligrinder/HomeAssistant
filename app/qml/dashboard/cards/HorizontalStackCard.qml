import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardFlow {
    property var card: ({})
    columns: 12
    cards: sizedCards()

    function sizedCards() {
        var src = (card && card.cards) ? card.cards : []
        var n = Math.max(1, src.length)
        var span = Math.max(1, Math.floor(12 / n))
        var out = []
        for (var i = 0; i < src.length; ++i) {
            var c = src[i] || {}
            c._columns = span
            out.push(c)
        }
        return out
    }
}
