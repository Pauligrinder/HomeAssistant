import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: true

    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: root.statesRevision
    readonly property bool on: (dashboard && entityId.length && rev >= 0) ? dashboard.isOn(entityId) : false
    readonly property var features: (card && card.features) ? card.features : []
    readonly property bool vertical: !!(card && card.vertical)
    // HA: features_position "inline" puts the first feature beside the title.
    // Vertical tiles always keep features below.
    readonly property bool inlineFeatures: !root.vertical
                                           && !!(card && String(card.features_position || "") === "inline")
                                           && root.features && root.features.length > 0
    readonly property var inlineFeature: root.inlineFeatures ? [root.features[0]] : []
    readonly property var belowFeatures: {
        if (!root.features || !root.features.length)
            return []
        if (root.inlineFeatures)
            return root.features.slice(1)
        return root.features
    }
    readonly property bool hideState: !!(card && card.hide_state)
    readonly property string titleText: (card && card.name) ? card.name
                      : ((dashboard && root.rev >= 0) ? dashboard.friendlyName(root.entityId) : root.entityId)
    readonly property string stateText: (dashboard && root.rev >= 0) ? dashboard.formatState(root.entityId) : ""
    readonly property bool isScript: root.entityId.indexOf("script.") === 0
    // Scene state is a last-triggered timestamp; HA tiles leave it blank.
    readonly property bool isScene: root.entityId.indexOf("scene.") === 0
    readonly property bool showStateLabel: !root.hideState && !root.isScript && !root.isScene
                                           && root.stateText.length > 0

    function loadFeatures(loader, list) {
        if (!loader || !loader.item)
            return
        loader.item.features = Qt.binding(function() { return list })
        loader.item.entityId = Qt.binding(function() { return root.entityId })
        loader.item.dashboard = Qt.binding(function() { return root.dashboard })
        loader.item.mdiIcons = Qt.binding(function() { return root.mdiIcons })
        loader.item.compact = Qt.binding(function() { return loader === inlineFeatureLoader })
    }

    // Vertical: icon above name/state. Horizontal: icon | info [| inline feature].
    Column {
        width: parent.width
        spacing: Theme.paddingSmall
        visible: root.vertical

        MouseArea {
            anchors.horizontalCenter: parent.horizontalCenter
            width: vIcon.width
            height: vIcon.height
            opacity: pressed ? root.tapPressOpacity : 1.0
            MdiIcon {
                id: vIcon
                mdiIcons: root.mdiIcons
                name: (dashboard && root.rev >= 0)
                      ? dashboard.entityIcon(root.entityId, card && card.icon ? card.icon : "") : ""
                iconColor: root.on ? Theme.highlightColor : Theme.primaryColor
                width: Theme.iconSizeMedium
            }
            onClicked: root.iconTap()
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.titleText
            truncationMode: TruncationMode.Fade
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.showStateLabel
            text: root.stateText
            truncationMode: TruncationMode.Fade
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
        Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.isScript
            preferredWidth: Theme.buttonWidthExtraSmall
            height: Theme.itemSizeExtraSmall
            text: i18n.translation("run")
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

    Row {
        width: parent.width
        spacing: Theme.paddingMedium
        visible: !root.vertical

        MouseArea {
            width: hIcon.width
            height: hIcon.height
            anchors.verticalCenter: parent.verticalCenter
            opacity: pressed ? root.tapPressOpacity : 1.0
            MdiIcon {
                id: hIcon
                mdiIcons: root.mdiIcons
                name: (dashboard && root.rev >= 0)
                      ? dashboard.entityIcon(root.entityId, card && card.icon ? card.icon : "") : ""
                iconColor: root.on ? Theme.highlightColor : Theme.primaryColor
                width: Theme.iconSizeMedium
            }
            onClicked: root.iconTap()
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: {
                var w = parent.width - hIcon.width - Theme.paddingMedium
                if (inlineFeatureLoader.active && inlineFeatureLoader.item)
                    w -= inlineFeatureLoader.item.width + Theme.paddingMedium
                return Math.max(0, w)
            }
            Label {
                width: parent.width
                text: root.titleText
                truncationMode: TruncationMode.Fade
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                width: parent.width
                visible: root.showStateLabel
                text: root.stateText
                truncationMode: TruncationMode.Fade
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Button {
                visible: root.isScript
                preferredWidth: Theme.buttonWidthExtraSmall
                height: Theme.itemSizeExtraSmall
                text: i18n.translation("run")
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

        Loader {
            id: inlineFeatureLoader
            anchors.verticalCenter: parent.verticalCenter
            active: root.inlineFeatures
            source: active ? Qt.resolvedUrl("../features/FeatureBar.qml") : ""
            onLoaded: root.loadFeatures(inlineFeatureLoader, root.inlineFeature)
        }
    }

    Loader {
        width: parent.width
        active: root.belowFeatures && root.belowFeatures.length > 0
        source: active ? Qt.resolvedUrl("../features/FeatureBar.qml") : ""
        onLoaded: root.loadFeatures(this, root.belowFeatures)
    }
}
