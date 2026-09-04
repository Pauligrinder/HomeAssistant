import QtQuick 2.6
import Sailfish.Silica 1.0

Rectangle {
    id: chrome
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int statesRevision: dashboard ? dashboard.statesRevision : 0
    property bool tapEnabled: true
    property bool showBackground: true
    default property alias contents: body.data

    width: parent ? parent.width : Theme.itemSizeHuge
    implicitHeight: Math.max(Theme.itemSizeMedium, body.height + 2 * Theme.paddingMedium)
    height: implicitHeight
    color: chrome.showBackground
           ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
           : "transparent"
    radius: Theme.paddingSmall
    opacity: (dashboard && card && !dashboard.cardVisible(card)) ? 0 : 1
    visible: !dashboard || !card || dashboard.cardVisible(card)
    clip: true

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
        anchors.margins: Theme.paddingMedium
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
