import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// HACS lovelace-collapsable-cards / expander-card: nested cards behind a toggle.
Column {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingSmall

    // Discrete state — not a binding on card.* — so config rebinds and
    // defaultOpen cannot force the section back open after the user folds it.
    property bool expanded: false
    property bool nestedReady: false
    property bool blockNestedInput: false
    property bool _defaultApplied: false

    function defaultShouldOpen() {
        if (!card)
            return false
        var v = card.defaultOpen
        if (v === true || v === "true" || v === 1 || v === "1")
            return true
        // expander-card uses `expanded` for the initial state.
        v = card.expanded
        if (v === true || v === "true" || v === 1 || v === "1")
            return true
        return false
    }

    function applyDefaultOnce() {
        if (root._defaultApplied)
            return
        root._defaultApplied = true
        if (!root.defaultShouldOpen())
            return
        // Open without the input shield — there is no opening gesture to absorb.
        showNestedTimer.stop()
        clearBlockTimer.stop()
        root.expanded = true
        root.nestedReady = true
        root.blockNestedInput = false
    }

    function toggleExpanded() {
        if (root.expanded)
            root.collapse()
        else
            root.expandFromTap()
    }

    function expandFromTap() {
        root.expanded = true
        // Shield nested input until the opening gesture has fully finished —
        // otherwise the same finger-up lands on a map/card and opens MapPage
        // or eats the next fold tap.
        root.blockNestedInput = true
        root.nestedReady = false
        showNestedTimer.stop()
        clearBlockTimer.stop()
        showNestedTimer.start()
    }

    function collapse() {
        showNestedTimer.stop()
        clearBlockTimer.stop()
        root.expanded = false
        root.nestedReady = false
        root.blockNestedInput = false
    }

    Component.onCompleted: root.applyDefaultOnce()
    onCardChanged: root.applyDefaultOnce()

    Timer {
        id: showNestedTimer
        // Let BackgroundItem finish clicked handling before children exist.
        interval: 1
        onTriggered: {
            if (!root.expanded)
                return
            root.nestedReady = true
            clearBlockTimer.start()
        }
    }

    Timer {
        id: clearBlockTimer
        interval: 450
        onTriggered: {
            if (root.expanded)
                root.blockNestedInput = false
        }
    }

    BackgroundItem {
        id: toggle
        width: parent.width
        height: Theme.itemSizeSmall
        // Above nested content so fold still works if a child draws large.
        z: 2
        onClicked: root.toggleExpanded()

        Label {
            anchors.left: parent.left
            anchors.right: chevron.left
            anchors.rightMargin: Theme.paddingMedium
            anchors.verticalCenter: parent.verticalCenter
            text: (card && card.title) ? String(card.title)
                  : (root.expanded ? i18n.translation("show_less")
                                   : i18n.translation("expand"))
            color: Theme.highlightColor
            truncationMode: TruncationMode.Fade
        }
        Label {
            id: chevron
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.expanded ? "▾" : "▸"
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeLarge
        }
    }

    Item {
        id: nestedHost
        width: parent.width
        height: nestedLoader.active && nestedLoader.item ? nestedLoader.item.height : 0

        Loader {
            id: nestedLoader
            width: parent.width
            active: root.nestedReady
            sourceComponent: nestedComp
        }

        // Absorbs the opening gesture's release and brief follow-up taps.
        MouseArea {
            anchors.fill: parent
            z: 100
            enabled: root.blockNestedInput && nestedLoader.active
            visible: enabled
            onPressed: mouse.accepted = true
            onClicked: mouse.accepted = true
        }
    }

    Component {
        id: nestedComp
        Column {
            width: nestedLoader.width
            spacing: Theme.paddingSmall

            Repeater {
                model: (root.card && root.card.cards) ? root.card.cards : []
                CardLoader {
                    width: parent.width
                    unitWidth: parent.width
                    columns: 12
                    fillHeight: 0
                    panelMap: false
                    card: modelData
                    dashboard: root.dashboard
                    hassClient: root.hassClient
                    mdiIcons: root.mdiIcons
                }
            }
        }
    }
}
