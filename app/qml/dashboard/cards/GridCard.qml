import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardFlow {
    property var card: ({})
    // Pack against the grid's own column count. Children are one cell each
    // (_columns = 1 from LovelaceCoordinator::decorateCard). Mapping those
    // cells onto a 12-column flow made 3 buttons with default span 6 wrap 2+1.
    columns: {
        var n = 3
        if (card && card.columns !== undefined && card.columns !== null && card.columns !== "")
            n = Number(card.columns)
        if (!isFinite(n) || n < 1)
            n = 3
        return Math.max(1, Math.round(n))
    }
    cards: (card && card.cards) ? card.cards : []
}
