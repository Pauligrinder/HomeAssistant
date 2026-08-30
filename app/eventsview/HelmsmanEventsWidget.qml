import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.DBus 2.0

Item {
    id: root

    // The events view loader only sets the width, and takes its height from
    // implicitHeight, so the widget has to report its content height there.
    width: parent ? parent.width : Screen.width
    implicitWidth: width
    implicitHeight: column.height
    height: implicitHeight

    property bool active: visible && eventsViewVisible
    property bool expanded: false
    property int collapsedCount: 2

    property var entities: []
    property string errorText: ""

    // Card whose brightness slider is open, opened by long press.
    property string brightnessEntityId: ""
    property bool adjustingBrightness: false

    readonly property var visibleEntities: expanded
                                           ? entities
                                           : entities.slice(0, collapsedCount)

    function parseEntities(payload) {
        if (!payload || payload.length === 0) {
            root.entities = []
            root.errorText = ""
            return
        }
        try {
            var parsed = JSON.parse(payload)
            if (parsed instanceof Array) {
                root.entities = parsed
                root.errorText = ""
            } else {
                root.entities = []
                root.errorText = "Invalid widget data"
            }
        } catch (e) {
            root.entities = []
            root.errorText = "Widget unavailable"
        }
    }

    function stateLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        if (entity.dimmable === true && entity.on === true)
            return "On · " + Math.round(Number(entity.brightnessPct) || 0) + "%"
        return entity.on === true ? "On" : "Off"
    }

    // Repaint the card straight away; the app confirms with EntitiesChanged.
    function patchEntity(entityId, patch) {
        var next = []
        for (var i = 0; i < root.entities.length; ++i) {
            var item = root.entities[i]
            if (item.entityId !== entityId) {
                next.push(item)
                continue
            }
            var copy = {}
            for (var key in item)
                copy[key] = item[key]
            for (var field in patch)
                copy[field] = patch[field]
            next.push(copy)
        }
        root.entities = next
    }

    function toggleLight(entity) {
        if (!entity || entity.available === false)
            return
        var on = !(entity.on === true)
        root.patchEntity(entity.entityId,
                         { "on": on,
                           "state": on ? "on" : "off",
                           "brightnessPct": on ? (Number(entity.brightnessPct) || 100) : 0 })
        widgetIface.call("ToggleLight", [entity.entityId])
    }

    function setBrightness(entity, pct) {
        if (!entity || entity.available === false)
            return
        pct = Math.max(0, Math.min(100, Math.round(pct)))
        root.patchEntity(entity.entityId,
                         { "on": pct > 0,
                           "state": pct > 0 ? "on" : "off",
                           "brightnessPct": pct })
        widgetIface.call("SetBrightnessPct", [entity.entityId, pct])
    }

    function toggleBrightness(entity) {
        if (!entity || entity.available === false || entity.dimmable !== true)
            return
        root.brightnessEntityId = root.brightnessEntityId === entity.entityId
                ? ""
                : entity.entityId
    }

    function refresh() {
        // Replacing the model rebuilds the delegates, which would fight a drag.
        if (!root.active || root.adjustingBrightness)
            return
        widgetIface.call("Refresh", [])
        widgetIface.call("GetEntitiesJson", [],
                         function(result) { root.parseEntities(result) },
                         function() {
                             root.entities = []
                             root.errorText = "Widget unavailable"
                         })
    }

    function reload() {
        refresh()
    }

    function save() {
    }

    Component.onCompleted: if (active) refresh()
    onActiveChanged: {
        if (active) {
            refresh()
        } else {
            root.brightnessEntityId = ""
        }
    }

    Timer {
        id: refreshTimer
        interval: 8000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    DBusInterface {
        id: widgetIface
        service: "org.helmsman.harbour-helmsman"
        path: "/widget"
        iface: "org.helmsman.Widget"
        signalsEnabled: root.active
        // Nemo.DBus maps the D-Bus signal EntitiesChanged to a lowercase-initial handler.
        function entitiesChanged() {
            root.refresh()
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            text: "Helmsman"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeMedium
            font.family: Theme.fontFamilyHeading
            truncationMode: TruncationMode.Fade
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: root.entities.length === 0
            text: root.errorText.length > 0
                  ? root.errorText
                  : "Open Helmsman to sync selected lights."
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.visibleEntities

            delegate: Item {
                id: card

                property bool dimmable: modelData.dimmable === true
                property bool available: modelData.available !== false
                property bool showBrightness: card.dimmable
                                              && card.available
                                              && root.brightnessEntityId === modelData.entityId

                x: Theme.horizontalPageMargin
                width: column.width - 2 * Theme.horizontalPageMargin
                height: cardColumn.height + 2 * Theme.paddingMedium

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingMedium
                    color: "#03A9F4"
                    opacity: tapArea.pressed
                             ? 0.5
                             : (modelData.on === true ? 0.32 : 0.16)
                }

                // Watermark like the cover: half off the right edge, clipped
                // short of the rounded corners.
                Item {
                    anchors.fill: parent
                    clip: true

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.right
                        height: parent.height - 2 * Theme.paddingSmall
                        width: height
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        opacity: modelData.on === true ? 0.34 : 0.22
                        visible: status === Image.Ready
                        source: modelData.iconPath
                                ? "file://" + modelData.iconPath
                                : ""
                    }
                }

                Column {
                    id: cardColumn

                    x: Theme.paddingLarge
                    y: Theme.paddingMedium
                    width: parent.width - 2 * Theme.paddingLarge
                    spacing: Theme.paddingSmall

                    // Only the labels toggle, so the slider below keeps its drags.
                    MouseArea {
                        id: tapArea

                        width: parent.width
                        height: labels.height
                        enabled: card.available
                        onClicked: root.toggleLight(modelData)
                        onPressAndHold: root.toggleBrightness(modelData)

                        Column {
                            id: labels
                            width: parent.width

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                color: Theme.primaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: modelData.on === true
                                text: modelData.name || modelData.entityId
                            }

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                text: {
                                    if (card.dimmable && card.available && !card.showBrightness)
                                        return root.stateLabel(modelData) + " · hold to dim"
                                    return root.stateLabel(modelData)
                                }
                            }
                        }
                    }

                    Slider {
                        id: dimmer

                        width: parent.width
                        visible: card.showBrightness
                        minimumValue: 0
                        maximumValue: 100
                        stepSize: 1
                        valueText: Math.round(value) + "%"
                        label: "Brightness"

                        Binding {
                            target: dimmer
                            property: "value"
                            value: Number(modelData.brightnessPct) || 0
                            when: !dimmer.down
                        }

                        onDownChanged: {
                            root.adjustingBrightness = down
                            if (!down)
                                root.setBrightness(modelData, dimmer.value)
                        }
                    }
                }
            }
        }

        BackgroundItem {
            id: showMore

            width: parent.width
            height: Theme.itemSizeExtraSmall
            visible: root.entities.length > root.collapsedCount
            onClicked: root.expanded = !root.expanded

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                color: showMore.highlighted ? Theme.highlightColor : Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: root.expanded
                      ? "Show less"
                      : ("Show more (" + (root.entities.length - root.collapsedCount) + ")")
            }
        }
    }
}
