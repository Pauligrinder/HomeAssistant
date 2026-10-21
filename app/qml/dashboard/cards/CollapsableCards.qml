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

    property bool expanded: {
        var v = card ? card.defaultOpen : false
        if (v === true || v === "true")
            return true
        // desktop-only / contain-toggled → start collapsed on the phone.
        return false
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

    Column {
        width: parent.width
        spacing: Theme.paddingSmall
        visible: root.expanded
        height: visible ? implicitHeight : 0
        clip: true

        Repeater {
            model: (root.card && root.card.cards) ? root.card.cards : []
            CardLoader {
                width: root.width
                unitWidth: root.width
                columns: 12
                card: modelData
                dashboard: root.dashboard
                hassClient: root.hassClient
                mdiIcons: root.mdiIcons
            }
        }
    }
}
