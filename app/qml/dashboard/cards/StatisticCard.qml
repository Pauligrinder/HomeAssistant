import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && (card.entity || card.stat_id)
                                       ? String(card.entity || card.stat_id) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId, "Statistic") : "Statistic"
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.formatState(entityId) : ""
        font.pixelSize: Theme.fontSizeLarge
    }
}
