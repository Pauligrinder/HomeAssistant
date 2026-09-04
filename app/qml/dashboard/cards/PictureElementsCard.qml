import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    property string imageUrl: ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    function mediaPath() {
        if (card && card.image)
            return String(card.image)
        if (card && card.camera_image && dashboard)
            return dashboard.cameraPath(String(card.camera_image))
        return ""
    }

    Connections {
        target: dashboard
        onMediaCached: {
            if (path === root.mediaPath())
                root.imageUrl = fileUrl
        }
    }

    Component.onCompleted: {
        if (dashboard && root.mediaPath().length)
            dashboard.prefetchMedia(root.mediaPath())
    }

    Item {
        id: stage
        width: parent.width
        height: width * 0.66

        Image {
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: root.imageUrl
        }

        Repeater {
            model: (card && card.elements) ? card.elements : []
            Item {
                property var el: modelData
                property string entityId: el.entity ? String(el.entity) : ""
                width: Theme.iconSizeMedium
                height: Theme.iconSizeMedium
                x: {
                    var left = 50
                    if (el.style && el.style.left)
                        left = parseFloat(String(el.style.left))
                    return stage.width * left / 100 - width / 2
                }
                y: {
                    var top = 50
                    if (el.style && el.style.top)
                        top = parseFloat(String(el.style.top))
                    return stage.height * top / 100 - height / 2
                }
                visible: !el.conditions
                         || (dashboard && root.rev >= 0 && dashboard.isVisible(el.conditions))

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!dashboard)
                            return
                        if (el.tap_action)
                            dashboard.performAction(el.tap_action, entityId)
                        else if (entityId.length)
                            dashboard.openMoreInfo(entityId)
                    }
                }

                MdiIcon {
                    anchors.centerIn: parent
                    visible: el.type === "state-icon" || el.type === "icon" || el.type === "state-badge"
                    mdiIcons: root.mdiIcons
                    name: el.icon ? el.icon
                          : ((dashboard && root.rev >= 0) ? dashboard.entityIcon(entityId) : "")
                    iconColor: (dashboard && root.rev >= 0 && dashboard.isOn(entityId))
                               ? Theme.highlightColor : "white"
                }
                Label {
                    anchors.centerIn: parent
                    visible: el.type === "state-label" || el.type === "state-badge"
                    color: "white"
                    font.pixelSize: Theme.fontSizeTiny
                    text: (dashboard && entityId.length && root.rev >= 0)
                          ? dashboard.formatState(entityId) : (el.title || "")
                }
            }
        }
    }
}
