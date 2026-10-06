import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardFlow {
    property var card: ({})
    columns: 12
    // Grid span / square flags are applied in LovelaceCoordinator::decorateCard
    // so QML never mutates live view card maps (which dropped title after MoreInfo).
    cards: (card && card.cards) ? card.cards : []
}
