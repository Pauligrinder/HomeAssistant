import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string areaId: card && (card.area || card.entity) ? String(card.area || card.entity) : ""
    property int listTick: 0
    readonly property int rev: root.statesRevision + listTick

    Connections {
        target: dashboard
        onEntityChanged: root.listTick++
    }

    Label {
        width: parent.width
        text: (dashboard && root.rev >= 0) ? dashboard.areaName(root.areaId) : root.areaId
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeMedium
    }
    Label {
        width: parent.width
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
        text: {
            if (!dashboard || root.rev < 0)
                return ""
            var ids = dashboard.areaEntities(root.areaId)
            return ids.length + " entities"
        }
    }
}
