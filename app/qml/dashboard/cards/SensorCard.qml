import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Label {
        width: parent.width
        text: (card && card.name) ? card.name
              : (dashboard ? dashboard.friendlyName(entityId) : entityId)
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }
    Label {
        width: parent.width
        text: dashboard ? dashboard.formatState(entityId) : ""
        color: Theme.primaryColor
        font.pixelSize: Theme.fontSizeLarge
    }

    Component.onCompleted: {
        if (dashboard && entityId.length)
            dashboard.fetchHistory([entityId], 24)
    }
}
