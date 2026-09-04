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
                        anchors.horizontalCenter: parent.horizontalCenter
                        mdiIcons: root.mdiIcons
                        name: dashboard ? dashboard.entityIcon(entityId) : ""
                        iconColor: (dashboard && dashboard.isOn(entityId)) ? Theme.highlightColor : Theme.primaryColor
                        width: Theme.iconSizeSmall
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Theme.fontSizeTiny
                        wrapMode: Text.Wrap
                        text: dashboard ? dashboard.formatState(entityId) : ""
                    }
                }
            }
        }
    }
}
