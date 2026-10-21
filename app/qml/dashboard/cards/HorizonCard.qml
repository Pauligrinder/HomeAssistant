import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// HACS lovelace-horizon-card: sun rise/set times from the Sun integration.
// Full SVG path graph is omitted; times and elevation cover the useful bits.
CardChrome {
    id: root
    tapEnabled: false
    readonly property string sunId: "sun.sun"
    readonly property int rev: root.statesRevision

    function sunAttr(key) {
        if (!dashboard || root.rev < 0)
            return ""
        var v = dashboard.attribute(root.sunId, key)
        if (v === undefined || v === null)
            return ""
        return String(v)
    }

    function formatTime(iso) {
        if (!iso || iso.length < 16)
            return "—"
        // 2024-06-01T05:42:00+02:00 → local clock HH:MM
        var t = iso.indexOf("T")
        if (t < 0)
            return iso
        return iso.substring(t + 1, t + 6)
    }

    Label {
        width: parent.width
        visible: !!(card && card.title && String(card.title).length)
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
        truncationMode: TruncationMode.Fade
    }

    Item {
        width: parent.width
        height: Theme.itemSizeMedium

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 2
            color: Theme.rgba(Theme.highlightColor, 0.35)
        }
        Rectangle {
            id: sunDot
            width: Theme.paddingLarge
            height: width
            radius: width / 2
            color: Theme.highlightColor
            anchors.verticalCenter: parent.verticalCenter
            // Map elevation (−90…90) onto the row; 0 = horizon centre.
            x: {
                var el = Number(root.sunAttr("elevation"))
                if (!isFinite(el))
                    el = 0
                var t = Math.max(0, Math.min(1, (el + 90) / 180))
                return t * (parent.width - width)
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.paddingMedium

        Column {
            width: (parent.width - parent.spacing) / 2
            Label {
                text: i18n.translation("sunrise")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Label {
                text: root.formatTime(root.sunAttr("next_rising"))
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }
        Column {
            width: (parent.width - parent.spacing) / 2
            Label {
                anchors.right: parent.right
                text: i18n.translation("sunset")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
            Label {
                anchors.right: parent.right
                text: root.formatTime(root.sunAttr("next_setting"))
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
