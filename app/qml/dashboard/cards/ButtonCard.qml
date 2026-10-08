import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: root.statesRevision
    readonly property bool on: (dashboard && root.entityId.length && root.rev >= 0)
                               ? dashboard.isOn(root.entityId) : false
    readonly property bool showName: !card || card.show_name !== false
    readonly property bool showIcon: !card || card.show_icon !== false
    readonly property bool showState: !!(card && card.show_state === true)
    readonly property string iconName: {
        if (card && card.icon)
            return String(card.icon)
        if (root.entityId.length && dashboard && root.rev >= 0)
            return dashboard.entityIcon(root.entityId)
        return "mdi:gesture-tap-button"
    }
    readonly property int iconPixelSize: {
        var _ = root.width
        var h = card ? card.icon_height : undefined
        return root.resolveIconSize()
    }
    readonly property var iconTint: {
        var _ = root.rev
        var __ = root.on
        var c = card ? card.color : undefined
        return root.resolveIconColor()
    }

    // HA default is 40% of the card; icon_height overrides (px, em, or %).
    function resolveIconSize() {
        var fallback = Math.max(8, Math.round(root.width * 0.4))
        if (!card || card.icon_height === undefined || card.icon_height === null)
            return fallback
        var s = String(card.icon_height).trim()
        if (!s.length || s.toLowerCase() === "auto")
            return fallback
        if (s.indexOf("%") >= 0) {
            var pct = parseFloat(s)
            return (isFinite(pct) && pct > 0)
                    ? Math.max(8, Math.round(root.width * pct / 100)) : fallback
        }
        var n = parseFloat(s)
        if (!isFinite(n) || n <= 0)
            return fallback
        if (s.indexOf("em") >= 0)
            return Math.max(8, Math.round(n * Theme.fontSizeMedium))
        return Math.max(8, Math.round(n))
    }

    function resolveIconColor() {
        var _ = root.rev
        var configured = (card && card.color !== undefined && card.color !== null)
                         ? String(card.color).trim() : ""
        var active = !root.entityId.length || root.on
        if (configured === "none")
            return Theme.primaryColor
        if (configured.length && configured !== "state") {
            if (!active)
                return Theme.primaryColor
            if (configured === "primary")
                return Theme.primaryColor
            if (configured === "accent" || configured === "highlight")
                return Theme.highlightColor
            if (configured === "disabled")
                return Theme.secondaryColor
            return configured
        }
        if (active && root.entityId.length && dashboard && root.rev >= 0) {
            var rgb = dashboard.attribute(root.entityId, "rgb_color")
            if (rgb && rgb.length >= 3)
                return Qt.rgba(Number(rgb[0]) / 255, Number(rgb[1]) / 255,
                               Number(rgb[2]) / 255, 1)
            if (root.on)
                return Theme.highlightColor
        }
        return Theme.primaryColor
    }

    MdiIcon {
        visible: root.showIcon
        x: (parent.width - width) / 2
        mdiIcons: root.mdiIcons
        name: root.iconName
        iconColor: root.iconTint
        width: root.showIcon ? Math.min(root.iconPixelSize, parent.width) : 0
        height: width
    }
    Label {
        width: parent.width
        visible: root.showName
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: (card && card.name) ? card.name
              : ((dashboard && root.rev >= 0)
                 ? dashboard.friendlyName(root.entityId, "Button") : "Button")
        color: Theme.primaryColor
        font.pixelSize: Theme.fontSizeSmall
    }
    Label {
        width: parent.width
        visible: root.showState && root.entityId.length > 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: (dashboard && root.rev >= 0) ? dashboard.formatState(root.entityId) : ""
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }
}
