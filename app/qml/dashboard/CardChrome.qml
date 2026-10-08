import QtQuick 2.6
import Sailfish.Silica 1.0

Rectangle {
    id: chrome
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    // Accessors have no NOTIFY. statesRevision bumps only for visibility /
    // filter / pending changes; entityTick covers this card's primary entity
    // so content still refreshes without rebinding the whole dashboard.
    property int entityTick: 0
    readonly property int statesRevision: (dashboard ? dashboard.statesRevision : 0)
                                          + entityTick
    property bool tapEnabled: true
    // Optional override for cards that tap something other than handleCardTap.
    property var tapHandler
    property bool showBackground: true
    property int fillHeight: 0
    property int minContentHeight: 0
    property real contentTopMargin: Theme.paddingMedium
    property real contentBottomMargin: Theme.paddingMedium
    property real contentHorizontalMargin: Theme.paddingMedium
    default property alias contents: body.data

    width: parent ? parent.width : Theme.itemSizeHuge
    implicitHeight: Math.max(Theme.itemSizeMedium,
                             body.height + contentTopMargin + contentBottomMargin,
                             minContentHeight)
    height: fillHeight > 0 ? fillHeight : implicitHeight
    color: chrome.showBackground
           ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
           : "transparent"
    radius: Theme.paddingSmall
    readonly property string trackedEntityId: {
        if (!card)
            return ""
        if (card.entity)
            return String(card.entity)
        if (card.camera_image)
            return String(card.camera_image)
        return ""
    }
    readonly property bool actionPending: (dashboard && trackedEntityId.length && statesRevision >= 0)
                                          ? dashboard.isPending(trackedEntityId) : false
    // Pressed tappable cards dim; 0.6 stays above the 0.45 unavailable fade.
    readonly property real tapPressOpacity: 0.6

    function withPressOpacity(baseOpacity, isPressed) {
        var base = Number(baseOpacity)
        if (!isFinite(base))
            base = 1
        return isPressed ? base * chrome.tapPressOpacity : base
    }

    opacity: {
        if (dashboard && card && statesRevision >= 0 && !dashboard.cardVisible(card))
            return 0
        var base = 1
        if (dashboard && trackedEntityId.length && statesRevision >= 0
                && dashboard.entityDimmed(trackedEntityId))
            base = 0.45
        return chrome.withPressOpacity(base, tapArea.pressed && chrome.tapEnabled)
    }
    visible: !dashboard || !card || (statesRevision >= 0 && dashboard.cardVisible(card))
    clip: true

    Connections {
        target: dashboard
        onEntityChanged: {
            if (chrome.trackedEntityId.length
                    && entityId === chrome.trackedEntityId)
                chrome.entityTick++
        }
    }

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
        return chrome.trackedEntityId
    }

    function mergeConfirmation(action, confirmation) {
        var out = {}
        if (action) {
            for (var key in action)
                out[key] = action[key]
        }
        if (!out.action)
            out.action = "toggle"
        if (confirmation !== undefined && confirmation !== null
                && out.confirmation === undefined)
            out.confirmation = confirmation
        return out
    }

    function iconTap() {
        if (!dashboard || !card)
            return
        var action = card.icon_tap_action
        if (action) {
            dashboard.performAction(chrome.mergeConfirmation(action), chrome.entityId())
            return
        }
        if (dashboard.isToggleable(chrome.entityId()))
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
        anchors.leftMargin: chrome.contentHorizontalMargin
        anchors.rightMargin: chrome.contentHorizontalMargin
        anchors.topMargin: chrome.contentTopMargin
        spacing: Theme.paddingSmall
        opacity: chrome.actionPending ? 0.72 : 1.0
    }

    PendingIndicator {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.paddingSmall / 2
        dashboard: chrome.dashboard
        entityId: chrome.trackedEntityId
        size: BusyIndicatorSize.Small
        z: 2
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        enabled: chrome.tapEnabled && chrome.visible
        z: 0
        onClicked: {
            if (typeof chrome.tapHandler === "function") {
                chrome.tapHandler()
                return
            }
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
