import QtQuick 2.6
import Sailfish.Silica 1.0

CardFlow {
    id: layout
    property var view: ({})
    cards: (view && view.cards) ? view.cards : []
    columns: 12
}
