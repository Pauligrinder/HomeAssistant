import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

PictureEntityCard {
    id: root

    Flow {
        width: parent.width
        spacing: Theme.paddingSmall
        Repeater {
            model: (card && card.entities) ? card.entities : []
            MouseArea {
                width: Theme.itemSizeMedium
                height: Theme.itemSizeMedium
                property string entityId: typeof modelData === "string" ? modelData
                                          : (modelData.entity ? String(modelData.entity) : "")
                onClicked: {
                    if (dashboard && entityId.length)
                        dashboard.openMoreInfo(entityId)
                }
                Column {
                    anchors.fill: parent
                    MdiIcon {
                        x: (parent.width - width) / 2
                        mdiIcons: root.mdiIcons
                        name: (dashboard && root.rev >= 0) ? dashboard.entityIcon(entityId) : ""
                        iconColor: (dashboard && root.rev >= 0 && dashboard.isOn(entityId))
                                   ? Theme.highlightColor : Theme.primaryColor
                        width: Theme.iconSizeSmall
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeTiny
                        wrapMode: Text.Wrap
                        text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
                    }
                }
            }
        }
    }
}
