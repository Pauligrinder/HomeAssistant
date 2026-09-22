import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: true

    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property bool on: (dashboard && entityId.length && rev >= 0) ? dashboard.isOn(entityId) : false
    readonly property var features: (card && card.features) ? card.features : []

    Row {
        width: parent.width
        spacing: Theme.paddingMedium

        MouseArea {
            width: icon.width
            height: icon.height
            MdiIcon {
                id: icon
                mdiIcons: root.mdiIcons
                name: (dashboard && root.rev >= 0)
                      ? dashboard.entityIcon(root.entityId, card && card.icon ? card.icon : "") : ""
                iconColor: root.on ? Theme.highlightColor : Theme.primaryColor
                width: Theme.iconSizeMedium
            }
            onClicked: root.iconTap()
        }

        Column {
            width: parent.width - icon.width - Theme.paddingMedium
            Label {
                width: parent.width
                text: (card && card.name) ? card.name
                      : ((dashboard && root.rev >= 0) ? dashboard.friendlyName(root.entityId) : root.entityId)
                truncationMode: TruncationMode.Fade
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                width: parent.width
                visible: root.entityId.indexOf("script.") !== 0
                text: (dashboard && root.rev >= 0) ? dashboard.formatState(root.entityId) : ""
                truncationMode: TruncationMode.Fade
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Button {
                visible: root.entityId.indexOf("script.") === 0
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: qsTr("Run")
                onClicked: {
                    if (!dashboard || !root.entityId.length)
                        return
                    var confirm = card && card.confirmation
                    if (confirm === undefined && card && card.tap_action)
                        confirm = card.tap_action.confirmation
                    dashboard.performAction(root.mergeConfirmation({ "action": "toggle" }, confirm),
                                           root.entityId)
                }
            }
        }
    }

    Loader {
        width: parent.width
        active: root.features && root.features.length > 0
        source: active ? Qt.resolvedUrl("../features/FeatureBar.qml") : ""
        onLoaded: {
            if (!item)
                return
            item.features = Qt.binding(function() { return root.features })
            item.entityId = Qt.binding(function() { return root.entityId })
            item.dashboard = Qt.binding(function() { return root.dashboard })
            item.mdiIcons = Qt.binding(function() { return root.mdiIcons })
        }
    }
}
