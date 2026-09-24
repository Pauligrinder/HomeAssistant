import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

PictureEntityCard {
    id: root

    Flow {
        width: parent.width
        spacing: Theme.paddingSmall
        Repeater {
            model: {
                var list = (card && card.entities) ? card.entities : []
                var rev = root.rev
                if (!dashboard || rev < 0 || !list || !list.length)
                    return list || []
                var out = []
                for (var i = 0; i < list.length; ++i) {
                    if (dashboard.entityEntryVisible(list[i]))
                        out.push(list[i])
                }
                return out
            }
            MouseArea {
                width: Theme.itemSizeMedium
                height: Theme.itemSizeMedium
                opacity: (entityId.length && dashboard && root.rev >= 0
                          && dashboard.entityDimmed(entityId)) ? 0.45 : 1.0
                property string entityId: typeof modelData === "string" ? modelData
                                          : (modelData.entity ? String(modelData.entity) : "")
                onClicked: {
                    if (dashboard && entityId.length)
                        dashboard.openMoreInfo(entityId)
                }
                Column {
                    anchors.fill: parent
                    Item {
                        x: (parent.width - width) / 2
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        MdiIcon {
                            anchors.fill: parent
                            mdiIcons: root.mdiIcons
                            name: (dashboard && root.rev >= 0) ? dashboard.entityIcon(entityId) : ""
                            iconColor: (dashboard && root.rev >= 0 && dashboard.isOn(entityId))
                                       ? Theme.highlightColor : Theme.primaryColor
                            width: Theme.iconSizeSmall
                            opacity: (dashboard && root.rev >= 0 && dashboard.isPending(entityId)) ? 0.55 : 1.0
                        }
                        PendingIndicator {
                            anchors.centerIn: parent
                            dashboard: root.dashboard
                            entityId: entityId
                        }
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
