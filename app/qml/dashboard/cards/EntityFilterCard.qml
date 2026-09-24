import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var entities: (dashboard && rev >= 0) ? dashboard.filterEntities(card || {}) : []

    // The filter returns plain entity ids, so a name set on the card's entity
    // list has to be looked up again here.
    function rowName(entityId) {
        var list = (card && card.entities) ? card.entities : []
        for (var i = 0; i < list.length; ++i) {
            var e = list[i]
            if (e && typeof e === "object" && String(e.entity || "") === entityId && e.name)
                return String(e.name)
        }
        return (dashboard && root.rev >= 0) ? dashboard.friendlyName(entityId) : entityId
    }

    Label {
        width: parent.width
        visible: !!(card && card.title && String(card.title).length > 0)
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
    }
    Repeater {
        model: root.entities
        BackgroundItem {
            width: parent.width
            height: Theme.itemSizeSmall
            opacity: (dashboard && root.rev >= 0
                      && dashboard.entityDimmed(String(modelData))) ? 0.45 : 1.0
            onClicked: dashboard.openMoreInfo(String(modelData))
            Label {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (dashboard && root.rev >= 0) ? root.rowName(String(modelData)) : String(modelData)
                truncationMode: TruncationMode.Fade
                width: parent.width * 0.6
            }
            Label {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: String(modelData).indexOf("script.") !== 0
                text: (dashboard && root.rev >= 0) ? dashboard.formatState(String(modelData)) : ""
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Button {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: String(modelData).indexOf("script.") === 0
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: qsTr("Run")
                onClicked: {
                    if (!dashboard)
                        return
                    dashboard.performAction({ "action": "toggle" }, String(modelData))
                }
            }
        }
    }
}
