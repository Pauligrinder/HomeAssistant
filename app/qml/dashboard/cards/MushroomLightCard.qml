import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// HACS mushroom-light-card: light row with optional brightness / colour temp.
CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: root.statesRevision
    readonly property bool on: (dashboard && entityId.length && rev >= 0)
                               ? dashboard.isOn(entityId) : false
    readonly property bool showBrightness: !card || card.show_brightness_control !== false
    readonly property bool showColorTemp: !!(card && card.show_color_temp_control)
    readonly property bool showColor: !!(card && card.show_color_control)
    readonly property bool collapse: !!(card && card.collapsible_controls)
    readonly property bool controlsVisible: !root.collapse || root.on
    readonly property var featureList: {
        var list = []
        if (root.showBrightness)
            list.push({ "type": "light-brightness" })
        if (root.showColorTemp)
            list.push({ "type": "light-color-temp" })
        if (root.showColor)
            list.push({ "type": "light-color" })
        return list
    }

    function iconName() {
        if (card && card.icon && String(card.icon).length && String(card.icon) !== "none")
            return String(card.icon)
        if (dashboard && root.rev >= 0 && root.entityId.length)
            return dashboard.entityIcon(root.entityId, "mdi:lightbulb")
        return "mdi:lightbulb"
    }

    function iconColor() {
        if (!(card && card.use_light_color) || !root.on || !dashboard || root.rev < 0)
            return root.on ? Theme.highlightColor : Theme.primaryColor
        var rgb = dashboard.attribute(root.entityId, "rgb_color")
        if (rgb && rgb.length >= 3)
            return Qt.rgba(Number(rgb[0]) / 255, Number(rgb[1]) / 255,
                           Number(rgb[2]) / 255, 1)
        return Theme.highlightColor
    }

    Row {
        width: parent.width
        spacing: Theme.paddingMedium
        MdiIcon {
            mdiIcons: root.mdiIcons
            name: root.iconName()
            iconColor: root.iconColor()
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium
            text: (card && card.name) ? String(card.name)
                  : ((dashboard && root.rev >= 0)
                     ? root.configName(root.entityId, "") : root.entityId)
            truncationMode: TruncationMode.Fade
            color: Theme.primaryColor
        }
    }

    Loader {
        width: parent.width
        active: root.controlsVisible && root.entityId.length > 0
                && root.featureList.length > 0
        source: active ? Qt.resolvedUrl("../features/FeatureBar.qml") : ""
        onLoaded: {
            if (!item)
                return
            item.width = Qt.binding(function() { return width })
            item.entityId = Qt.binding(function() { return root.entityId })
            item.dashboard = Qt.binding(function() { return root.dashboard })
            item.mdiIcons = Qt.binding(function() { return root.mdiIcons })
            item.features = Qt.binding(function() { return root.featureList })
        }
    }
}
