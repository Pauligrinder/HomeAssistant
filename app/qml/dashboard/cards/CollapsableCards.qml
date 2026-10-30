import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// HACS lovelace-collapsable-cards: nested cards behind a toggle.
Column {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingSmall

    // Visual expand state (chevron / title). Nested content is armed separately
    // so the same tap that expands cannot also hit a freshly created map.
    property bool expanded: {
        var v = card ? card.defaultOpen : false
        if (v === true || v === "true")
            return true
        return false
    }
    property bool nestedReady: false

    onExpandedChanged: {
        showNestedTimer.stop()
        if (root.expanded) {
            // defaultOpen path: allow nested content on first frame, but still
            // block the opening click via nestedReady delay when toggled.
            if (nestedReady)
                return
            showNestedTimer.start()
        } else {
            nestedReady = false
        }
    }

    Timer {
        id: showNestedTimer
        interval: 280
        onTriggered: {
            if (root.expanded)
                root.nestedReady = true
        }
    }

    Component.onCompleted: {
        // Start expanded from defaultOpen without waiting for a click.
        if (root.expanded)
            root.nestedReady = true
    }

    BackgroundItem {
        id: toggle
        width: parent.width
        height: Theme.itemSizeSmall
        onClicked: root.expanded = !root.expanded

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

    // Build nested cards only after expand is armed. Creating a map MouseArea
    // in the same event as the toggle click used to open MapPage immediately
    // while the section still looked collapsed.
    Loader {
        id: nestedLoader
        width: parent.width
        active: root.nestedReady
        height: active && item ? item.height : 0
        sourceComponent: nestedComp
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
                    card: modelData
                    dashboard: root.dashboard
                    hassClient: root.hassClient
                    mdiIcons: root.mdiIcons
                }
            }
        }
    }
}
