import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    readonly property var entities: (card && card.entities) ? card.entities : []
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Label {
        width: parent.width
        visible: card && card.title && String(card.title).length > 0
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Flow {
        width: parent.width
        spacing: Theme.paddingMedium

        Repeater {
            model: root.entities
            MouseArea {
                width: Theme.itemSizeLarge
                height: col.height
                property string entityId: typeof modelData === "string"
                                          ? modelData
                                          : (modelData.entity ? String(modelData.entity) : "")
                onClicked: {
                    if (dashboard && entityId.length)
                        dashboard.handleCardTap({ "entity": entityId, "tap_action": modelData.tap_action })
                }
                onPressAndHold: {
                    if (dashboard && entityId.length)
                        dashboard.openMoreInfo(entityId)
                }

                Column {
                    id: col
                    width: parent.width
                    spacing: Theme.paddingSmall / 2

                    MdiIcon {
                        x: (parent.width - width) / 2
                        mdiIcons: root.mdiIcons
                        name: (dashboard && root.rev >= 0) ? dashboard.entityIcon(entityId, modelData.icon || "") : ""
                        iconColor: (dashboard && root.rev >= 0 && dashboard.isOn(entityId))
                                   ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.secondaryColor
                        text: (modelData && modelData.name) ? modelData.name
                              : ((dashboard && root.rev >= 0) ? dashboard.friendlyName(entityId) : entityId)
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.primaryColor
                        text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
                    }
                }
            }
        }
    }
}
