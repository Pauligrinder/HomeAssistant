import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    contentTopMargin: 0
    contentBottomMargin: 0

    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property string batteryEntity: {
        if (card && card.battery_entity)
            return String(card.battery_entity)
        return card && card.google_battery ? String(card.google_battery) : ""
    }
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    property string imageUrl: ""
    property string requestedPath: ""

    function imagePath() {
        return dashboard
                ? dashboard.mediaPathOf(dashboard.attribute(entityId, "entity_picture")) : ""
    }

    function refreshImage() {
        var path = root.imagePath()
        if (!dashboard || !path.length)
            return
        if (path.indexOf("data:") === 0) {
            root.imageUrl = path
            return
        }
        var cached = dashboard.cachedMediaUrl(path)
        if (cached && cached.length)
            root.imageUrl = cached
        else if (path !== root.requestedPath) {
            root.requestedPath = path
            dashboard.prefetchMedia(path)
        }
    }

    function batteryLevel() {
        if (!dashboard || !batteryEntity.length)
            return 0
        var state = Number(dashboard.entityState(batteryEntity))
        if (!isNaN(state))
            return Math.max(0, Math.min(100, state))
        var attr = Number(dashboard.attribute(batteryEntity, "battery_level"))
        return isNaN(attr) ? 0 : Math.max(0, Math.min(100, attr))
    }

    function batteryCharging() {
        if (!dashboard || !batteryEntity.length)
            return false
        if (String(dashboard.attribute(batteryEntity, "battery_charging")) === "true"
                || String(dashboard.attribute(batteryEntity, "charging")) === "true")
            return true
        return String(dashboard.attribute(batteryEntity, "icon")).indexOf("charging") >= 0
    }

    function batteryIcon() {
        if (card && card.battery_entity) {
            var configured = dashboard.attribute(batteryEntity, "icon")
            if (configured)
                return String(configured)
        }
        var level = root.batteryLevel()
        var step = Math.max(10, Math.min(100, Math.round(level / 10) * 10))
        if (level < 10)
            return root.batteryCharging() ? "mdi:battery-charging-10" : "mdi:battery-alert"
        if (root.batteryCharging())
            return step === 100 ? "mdi:battery-charging-100"
                                : "mdi:battery-charging-" + step
        return step === 100 ? "mdi:battery" : "mdi:battery-" + step
    }

    function batteryColor() {
        var level = root.batteryLevel()
        return Qt.rgba(level < 50 ? 1 : (100 - level) / 50,
                       level >= 50 ? 1 : level / 50, 0, 1)
    }

    function locationIcon() {
        if (!dashboard)
            return "mdi:home-off"
        var state = dashboard.entityState(entityId)
        if (state === "home")
            return "mdi:home"
        var zoneIcon = dashboard.attribute("zone." + state, "icon")
        return zoneIcon ? String(zoneIcon) : "mdi:home-off"
    }

    function locationColor() {
        if (!dashboard)
            return "red"
        var state = dashboard.entityState(entityId)
        if (state === "home")
            return "lime"
        return dashboard.entityState("zone." + state).length ? "yellow" : "red"
    }

    function calendarVisible() {
        if (!dashboard || !card || !card.calendar_icon)
            return false
        if (card.calendar_color_entity)
            return true
        return card.calendar_entity
                && dashboard.entityState(String(card.calendar_entity)) !== "off"
    }

    function calendarColor() {
        var fallback = card && card.calendar_color ? String(card.calendar_color) : "grey"
        if (!dashboard || !card || !card.calendar_color_entity)
            return fallback
        var state = dashboard.entityState(String(card.calendar_color_entity))
        if (state === "green")
            return "lime"
        return state === "red" || state === "yellow" ? state : fallback
    }

    Connections {
        target: dashboard
        onMediaCached: {
            if (path === root.imagePath())
                root.imageUrl = fileUrl
        }
        onStatesRevisionChanged: root.refreshImage()
    }

    Component.onCompleted: root.refreshImage()

    Item {
        x: -Theme.paddingMedium
        width: root.width
        height: Theme.itemSizeHuge

        RoundedImage {
            anchors.fill: parent
            source: root.imageUrl
            cornerRadius: root.radius
        }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: statusRow.height + 2 * Theme.paddingSmall
            width: statusRow.width + 2 * Theme.paddingSmall
            color: "black"
            opacity: 0.7
            radius: root.radius
        }

        Row {
            id: statusRow
            z: 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.paddingSmall
            spacing: Theme.paddingSmall

            MdiIcon {
                visible: root.rev >= 0 && root.calendarVisible()
                width: visible ? Theme.iconSizeSmall : 0
                height: width
                mdiIcons: root.mdiIcons
                name: card && card.calendar_icon ? String(card.calendar_icon) : ""
                iconColor: root.rev >= 0 ? root.calendarColor() : "grey"
            }

            MdiIcon {
                visible: root.batteryEntity.length > 0
                width: visible ? Theme.iconSizeSmall : 0
                height: width
                mdiIcons: root.mdiIcons
                name: root.rev >= 0 ? root.batteryIcon() : "mdi:battery"
                iconColor: root.rev >= 0 ? root.batteryColor() : Theme.primaryColor

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (dashboard && root.batteryEntity.length)
                            dashboard.openMoreInfo(root.batteryEntity)
                    }
                }
            }

            MdiIcon {
                width: Theme.iconSizeSmall
                height: width
                mdiIcons: root.mdiIcons
                name: root.rev >= 0 ? root.locationIcon() : "mdi:home-off"
                iconColor: root.rev >= 0 ? root.locationColor() : "red"
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 1
            onClicked: {
                if (!dashboard)
                    return
                var action = card && card.tap_action
                        ? String(card.tap_action) : "more-info"
                dashboard.performAction({ "action": action }, root.entityId)
            }
        }
    }
}
