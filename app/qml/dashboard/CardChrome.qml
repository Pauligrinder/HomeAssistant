import QtQuick 2.6
import Sailfish.Silica 1.0

Rectangle {
    id: chrome
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    // The coordinator's entity accessors are plain slots with no change
    // notification, so a binding that only calls them never re-runs. Cards
    // read a revision counter (this, or their own rev) inside those bindings
    // so Home Assistant state updates reach the UI. Removing those reads
    // silently freezes the card at its first value.
    property int statesRevision: dashboard ? dashboard.statesRevision : 0
    property bool tapEnabled: true
    property bool showBackground: true
    property real contentTopMargin: Theme.paddingMedium
    property real contentBottomMargin: Theme.paddingMedium
    default property alias contents: body.data

    width: parent ? parent.width : Theme.itemSizeHuge
    implicitHeight: Math.max(Theme.itemSizeMedium,
                             body.height + contentTopMargin + contentBottomMargin)
    height: implicitHeight
    color: chrome.showBackground
           ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
           : "transparent"
    radius: Theme.paddingSmall
    opacity: (dashboard && card && statesRevision >= 0 && !dashboard.cardVisible(card)) ? 0 : 1
    visible: !dashboard || !card || (statesRevision >= 0 && dashboard.cardVisible(card))
    clip: true

    // Lovelace lets a card rename the entity it shows, and that name has to win
    // over the friendly name coming from Home Assistant.
    function configName(entityId, fallback) {
        if (card && card.name)
            return String(card.name)
        if (!dashboard)
            return fallback ? fallback : entityId
        return dashboard.friendlyName(entityId, fallback ? fallback : "")
    }

    function entityId() {
        if (!card)
            return ""
        if (card.entity)
            return String(card.entity)
        if (card.camera_image)
            return String(card.camera_image)
        return ""
    }

    function iconTap() {
        if (!dashboard || !card)
            return
        var action = card.icon_tap_action
        if (action && action.action)
            dashboard.performAction(action, chrome.entityId())
        else if (dashboard.isToggleable(chrome.entityId()))
            dashboard.toggle(chrome.entityId())
        else
            dashboard.handleCardTap(card)
    }

    Column {
        id: body
        z: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Theme.paddingMedium
        anchors.rightMargin: Theme.paddingMedium
        anchors.topMargin: chrome.contentTopMargin
        spacing: Theme.paddingSmall
    }

    MouseArea {
        anchors.fill: parent
        enabled: chrome.tapEnabled && chrome.visible
        z: 0
        onClicked: {
            if (dashboard && card)
                dashboard.handleCardTap(card)
        }
        onPressAndHold: {
            if (dashboard && card)
                dashboard.handleCardHold(card)
        }
        onDoubleClicked: {
            if (dashboard && card)
                dashboard.handleCardDoubleTap(card)
        }
    }
}
