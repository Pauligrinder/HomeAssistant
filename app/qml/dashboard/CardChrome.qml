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
    // Only the primary entity. camera_image must not be tracked here: camera
    // entities refresh access_token often, and bumping entityTick rebuilds
    // glance/entity children hard enough to freeze the dashboard on open.
    readonly property string trackedEntityId: {
        if (!card || !card.entity)
            return ""
        return String(card.entity)
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

    // When double_tap_action is set, defer the single-tap so a second tap can
    // claim the gesture (HA waits ~250ms). Without that action, tap is immediate.
    readonly property bool hasDoubleTapAction: {
        if (!card || !card.double_tap_action)
            return false
        var t = String(card.double_tap_action.action || "")
        return t !== "none" && t !== "no-op"
    }
    property bool suppressDoubleClick: false
    readonly property int doubleTapWaitMs: 280

    function runCardTap() {
        if (typeof chrome.tapHandler === "function") {
            chrome.tapHandler()
            return
        }
        if (dashboard && card)
            dashboard.handleCardTap(card)
    }

    function runCardDoubleTap() {
        if (dashboard && card)
            dashboard.handleCardDoubleTap(card)
    }

    Timer {
        id: pendingTapTimer
        interval: chrome.doubleTapWaitMs
        repeat: false
        onTriggered: chrome.runCardTap()
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        enabled: chrome.tapEnabled && chrome.visible
        z: 0
        onClicked: {
            if (!chrome.hasDoubleTapAction) {
                chrome.runCardTap()
                return
            }
            // Second click inside the wait window → double tap.
            if (pendingTapTimer.running) {
                pendingTapTimer.stop()
                chrome.suppressDoubleClick = true
                chrome.runCardDoubleTap()
                return
            }
            pendingTapTimer.start()
        }
        onPressAndHold: {
            pendingTapTimer.stop()
            if (dashboard && card)
                dashboard.handleCardHold(card)
        }
        onDoubleClicked: {
            // Usually already handled in onClicked; ignore the echo.
            if (chrome.suppressDoubleClick) {
                chrome.suppressDoubleClick = false
                return
            }
            pendingTapTimer.stop()
            chrome.runCardDoubleTap()
        }
        onCanceled: pendingTapTimer.stop()
    }
}
