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
    property string errorText: "Helmsman must be running to show the widget"
    property bool appRunning: false

    // Card whose brightness / color / temperature controls are open.
    property string adjustEntityId: ""
    property bool adjustingSlider: false
    // Script card whose Run/Cancel row is open.
    property string scriptEntityId: ""

    readonly property var colorSwatches: [
        { "r": 255, "g": 0, "b": 0 },
        { "r": 255, "g": 128, "b": 0 },
        { "r": 255, "g": 220, "b": 0 },
        { "r": 0, "g": 200, "b": 0 },
        { "r": 0, "g": 200, "b": 220 },
        { "r": 0, "g": 80, "b": 255 },
        { "r": 140, "g": 0, "b": 255 },
        { "r": 255, "g": 0, "b": 160 }
    ]

    readonly property var visibleEntities: expanded
                                           ? entities
                                           : entities.slice(0, collapsedCount)

    function parseEntities(payload) {
        root.appRunning = true
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
        if (entity.kind === "script")
            return ""
        if (entity.kind === "climate")
            return root.climateLabel(entity)
        if (entity.dimmable === true && entity.on === true)
            return "On · " + Math.round(Number(entity.brightnessPct) || 0) + "%"
        return entity.on === true ? "On" : "Off"
    }

    function climateLabel(entity) {
        if (!entity || entity.on !== true)
            return "Off"
        var mode = entity.hvacMode || entity.state || ""
        if (mode === "fan_only")
            return "Fan"
        if (mode === "heat_cool")
            return "Heat/Cool"
        if (mode === "off")
            return "Off"
        if (!mode)
            return "On"
        return mode.charAt(0).toUpperCase() + mode.slice(1)
    }

    function hvacSupported(entity, mode) {
        if (!entity)
            return false
        var modes = entity.hvacModes
        if (!modes || modes.length === 0)
            return true
        for (var i = 0; i < modes.length; ++i) {
            if (modes[i] === mode)
                return true
        }
        return false
    }

    function acLevelMode(levels, level) {
        if (!levels || level < 1 || level > levels.length)
            return ""
        var mode = levels[level - 1]
        return mode ? String(mode) : ""
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
        if (entity.kind === "script")
            return
        if (entity.kind === "climate") {
            var climateOn = !(entity.on === true)
            var climatePatch = { "on": climateOn }
            if (!climateOn) {
                climatePatch.state = "off"
                climatePatch.hvacMode = "off"
            }
            root.patchEntity(entity.entityId, climatePatch)
            widgetIface.call("ToggleLight", [entity.entityId])
            return
        }
        var on = !(entity.on === true)
        root.patchEntity(entity.entityId,
                         { "on": on,
                           "state": on ? "on" : "off",
                           "brightnessPct": on ? (Number(entity.brightnessPct) || 100) : 0 })
        widgetIface.call("ToggleLight", [entity.entityId])
    }

    function runScript(entity) {
        if (!entity || entity.available === false)
            return
        widgetIface.call("RunScript", [entity.entityId])
        root.scriptEntityId = ""
    }

    function cancelScript(entity) {
        if (!entity || entity.available === false)
            return
        widgetIface.call("CancelScript", [entity.entityId])
        root.scriptEntityId = ""
    }

    function activateCard(entity) {
        if (!entity || entity.available === false)
            return
        if (entity.kind === "script") {
            root.adjustEntityId = ""
            root.scriptEntityId = root.scriptEntityId === entity.entityId
                    ? ""
                    : entity.entityId
            return
        }
        root.scriptEntityId = ""
        root.toggleLight(entity)
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

    function setColorTemp(entity, kelvin) {
        if (!entity || entity.available === false)
            return
        kelvin = Math.round(kelvin)
        root.patchEntity(entity.entityId,
                         { "on": true,
                           "state": "on",
                           "colorTempKelvin": kelvin,
                           "colorMode": "color_temp" })
        widgetIface.call("SetColorTempKelvin", [entity.entityId, kelvin])
    }

    function setRgbColor(entity, r, g, b) {
        if (!entity || entity.available === false)
            return
        root.patchEntity(entity.entityId,
                         { "on": true,
                           "state": "on",
                           "rgbR": r,
                           "rgbG": g,
                           "rgbB": b,
                           "colorMode": "rgb" })
        widgetIface.call("SetRgbColor", [entity.entityId, r, g, b])
    }

    function setHvacMode(entity, mode) {
        if (!entity || entity.available === false)
            return
        root.patchEntity(entity.entityId,
                         { "on": mode !== "off",
                           "state": mode,
                           "hvacMode": mode })
        widgetIface.call("SetHvacMode", [entity.entityId, mode])
    }

    function setFanLevel(entity, level) {
        if (!entity || entity.available === false)
            return
        if (!root.acLevelMode(entity.fanLevels, level))
            return
        root.patchEntity(entity.entityId, { "fanLevel": level, "on": true })
        widgetIface.call("SetFanLevel", [entity.entityId, level])
    }

    function setVaneVertical(entity, level) {
        if (!entity || entity.available === false)
            return
        if (!root.acLevelMode(entity.vaneVerticalLevels, level))
            return
        root.patchEntity(entity.entityId, { "vaneVertical": level })
        widgetIface.call("SetVaneVertical", [entity.entityId, level])
    }

    function setVaneHorizontal(entity, level) {
        if (!entity || entity.available === false)
            return
        if (!root.acLevelMode(entity.vaneHorizontalLevels, level))
            return
        root.patchEntity(entity.entityId, { "vaneHorizontal": level })
        widgetIface.call("SetVaneHorizontal", [entity.entityId, level])
    }

    function colorSwatchSelected(entity, swatch) {
        if (!entity || entity.colorMode === "color_temp")
            return false
        var er = Number(entity.rgbR)
        var eg = Number(entity.rgbG)
        var eb = Number(entity.rgbB)
        if (er < 0 || eg < 0 || eb < 0)
            return false
        return Math.abs(er - swatch.r) < 40
                && Math.abs(eg - swatch.g) < 40
                && Math.abs(eb - swatch.b) < 40
    }

    function hasAdjusters(entity) {
        if (!entity || entity.kind === "script")
            return false
        return entity.dimmable === true
                || entity.supportsColor === true
                || entity.supportsColorTemp === true
                || entity.kind === "climate"
    }

    function toggleAdjusters(entity) {
        if (!entity || entity.available === false || !root.hasAdjusters(entity))
            return
        root.scriptEntityId = ""
        root.adjustEntityId = root.adjustEntityId === entity.entityId
                ? ""
                : entity.entityId
    }

    function refresh() {
        // Replacing the model rebuilds the delegates, which would fight a drag.
        if (!root.active || root.adjustingSlider || root.scriptEntityId.length > 0)
            return
        widgetIface.call("Refresh", [])
        widgetIface.call("GetEntitiesJson", [],
                         function(result) { root.parseEntities(result) },
                         function() {
                             root.appRunning = false
                             root.entities = []
                             root.errorText = "Helmsman must be running to show the widget"
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
            root.adjustEntityId = ""
            root.scriptEntityId = ""
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
            text: {
                if (!root.appRunning)
                    return "Helmsman must be running to show the widget"
                if (root.errorText.length > 0)
                    return root.errorText
                return "No favorites selected yet."
            }
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            wrapMode: Text.Wrap
        }

        BackgroundItem {
            id: chooseFavorites

            width: parent.width
            height: Theme.itemSizeExtraSmall
            visible: root.appRunning && root.entities.length === 0
                     && root.errorText.length === 0
            onClicked: widgetIface.call("OpenFavorites", [])

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                color: chooseFavorites.highlighted ? Theme.highlightColor : Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Choose favorites"
            }
        }

        Repeater {
            model: root.visibleEntities

            delegate: Item {
                id: card

                property bool dimmable: modelData.dimmable === true
                property bool available: modelData.available !== false
                property bool isScript: modelData.kind === "script"
                property bool isClimate: modelData.kind === "climate"
                property var entity: modelData
                property bool supportsColor: modelData.supportsColor === true
                property bool supportsColorTemp: modelData.supportsColorTemp === true
                property bool hasAdjusters: card.dimmable
                                            || card.supportsColor
                                            || card.supportsColorTemp
                                            || card.isClimate
                property bool showAdjusters: card.hasAdjusters
                                             && card.available
                                             && root.adjustEntityId === modelData.entityId
                property bool showScriptActions: card.isScript
                                                 && card.available
                                                 && root.scriptEntityId === modelData.entityId
                property var colorChoices: {
                    var list = []
                    var src = root.colorSwatches
                    for (var i = 0; i < src.length; ++i)
                        list.push(src[i])
                    if (!card.supportsColorTemp)
                        list.push({ "r": 255, "g": 255, "b": 255 })
                    return list
                }
                property int swatchSize: {
                    var n = card.colorChoices.length
                    var gap = Theme.paddingSmall
                    if (n <= 0)
                        return Theme.iconSizeSmall
                    return Math.max(Theme.iconSizeSmall,
                                    Math.floor((cardColumn.width - (n - 1) * gap) / n))
                }
                property int acCellSize: {
                    var n = 5
                    var gap = Theme.paddingSmall
                    return Math.max(Theme.iconSizeMedium,
                                    Math.floor((cardColumn.width - (n - 1) * gap) / n))
                }
                property var hvacChoices: {
                    var all = [
                        { "id": "cool", "label": "Cool" },
                        { "id": "heat", "label": "Heat" },
                        { "id": "dry", "label": "Dry" },
                        { "id": "fan_only", "label": "Fan" }
                    ]
                    var out = []
                    for (var i = 0; i < all.length; ++i) {
                        if (root.hvacSupported(card.entity, all[i].id))
                            out.push(all[i])
                    }
                    return out
                }

                x: Theme.horizontalPageMargin
                width: column.width - 2 * Theme.horizontalPageMargin
                height: cardColumn.height + 2 * Theme.paddingMedium

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingMedium
                    color: "#03A9F4"
                    opacity: tapArea.pressed
                             ? 0.5
                             : ((card.isScript ? card.showScriptActions
                                               : modelData.on === true) ? 0.32 : 0.16)
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
                        opacity: (card.isScript ? card.showScriptActions
                                                : modelData.on === true) ? 0.34 : 0.22
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
                        onClicked: root.activateCard(modelData)
                        onPressAndHold: root.toggleAdjusters(modelData)

                        Column {
                            id: labels
                            width: parent.width

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                color: Theme.primaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: !card.isScript && modelData.on === true
                                text: modelData.name || modelData.entityId
                            }

                            Label {
                                width: parent.width
                                truncationMode: TruncationMode.Fade
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                visible: labelText.length > 0
                                property string labelText: {
                                    if (card.isScript) {
                                        if (!card.available)
                                            return root.stateLabel(modelData)
                                        return card.showScriptActions
                                                ? ""
                                                : "Tap for Run or Cancel"
                                    }
                                    if (card.hasAdjusters && card.available && !card.showAdjusters)
                                        return root.stateLabel(modelData) + " · hold to adjust"
                                    return root.stateLabel(modelData)
                                }
                                text: labelText
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.paddingMedium
                        visible: card.showScriptActions

                        Button {
                            width: (parent.width - parent.spacing) / 2
                            text: "Run"
                            onClicked: root.runScript(modelData)
                        }

                        Button {
                            width: (parent.width - parent.spacing) / 2
                            text: "Cancel"
                            onClicked: root.cancelScript(modelData)
                        }
                    }

                    Slider {
                        id: dimmer

                        width: parent.width
                        visible: card.showAdjusters && card.dimmable
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
                            root.adjustingSlider = down
                            if (!down)
                                root.setBrightness(modelData, dimmer.value)
                        }
                    }

                    Slider {
                        id: temperature

                        width: parent.width
                        visible: card.showAdjusters && card.supportsColorTemp
                        minimumValue: Number(modelData.minKelvin) || 2000
                        maximumValue: Number(modelData.maxKelvin) || 6500
                        stepSize: 50
                        valueText: Math.round(value) + " K"
                        label: "Temperature"

                        Binding {
                            target: temperature
                            property: "value"
                            value: {
                                var k = Number(modelData.colorTempKelvin) || 0
                                if (k <= 0)
                                    return (temperature.minimumValue + temperature.maximumValue) / 2
                                return k
                            }
                            when: !temperature.down
                        }

                        onDownChanged: {
                            root.adjustingSlider = down
                            if (!down)
                                root.setColorTemp(modelData, temperature.value)
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall
                        visible: card.showAdjusters && card.supportsColor

                        Label {
                            width: parent.width
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Color"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall

                            Repeater {
                                model: card.colorChoices
                                delegate: Rectangle {
                                    width: card.swatchSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    color: Qt.rgba(modelData.r / 255,
                                                   modelData.g / 255,
                                                   modelData.b / 255, 1)
                                    property bool selected: root.colorSwatchSelected(card.entity, modelData)
                                    property bool isWhite: modelData.r === 255
                                                           && modelData.g === 255
                                                           && modelData.b === 255
                                    border.width: selected ? 3 : (isWhite ? 1 : 0)
                                    border.color: selected
                                                  ? (isWhite ? "#222222" : "#FFFFFF")
                                                  : "#80FFFFFF"

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setRgbColor(card.entity,
                                                                    modelData.r,
                                                                    modelData.g,
                                                                    modelData.b)
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall
                        visible: card.showAdjusters && card.isClimate

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: card.hvacChoices.length > 0

                            Repeater {
                                model: card.hvacChoices
                                delegate: Rectangle {
                                    width: card.hvacChoices.length > 0
                                           ? (parent.width - (card.hvacChoices.length - 1) * parent.spacing)
                                             / card.hvacChoices.length
                                           : parent.width
                                    height: Theme.itemSizeExtraSmall
                                    radius: Theme.paddingSmall
                                    color: (card.entity.hvacMode === modelData.id)
                                           ? "#73FFFFFF" : "#28FFFFFF"

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.setHvacMode(card.entity, modelData.id)
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        color: Theme.primaryColor
                                        font.pixelSize: Theme.fontSizeExtraSmall
                                        font.bold: card.entity.hvacMode === modelData.id
                                        text: modelData.label
                                    }
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            visible: card.entity.supportsFan === true
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Fan"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: card.entity.supportsFan === true

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: card.acCellSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    property int level: index + 1
                                    property bool enabledLevel: root.acLevelMode(card.entity.fanLevels, level).length > 0
                                    property bool selected: Number(card.entity.fanLevel) === level
                                    color: selected ? "#73FFFFFF" : "#28FFFFFF"
                                    opacity: enabledLevel ? 1 : 0.35

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: width * 0.16
                                        property int barCount: level
                                        Repeater {
                                            model: 5
                                            Rectangle {
                                                width: Math.max(2, Math.round(parent.width * 0.12))
                                                height: parent.height * (0.3 + index * 0.14)
                                                x: index * (parent.width / 5)
                                                y: parent.height - height
                                                radius: 1
                                                color: "#FFFFFF"
                                                opacity: index < parent.barCount ? 1 : 0.22
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: enabledLevel
                                        onClicked: root.setFanLevel(card.entity, level)
                                    }
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            visible: card.entity.supportsVaneVertical === true
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Vertical vanes"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: card.entity.supportsVaneVertical === true

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: card.acCellSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    property int level: index + 1
                                    property bool enabledLevel: root.acLevelMode(card.entity.vaneVerticalLevels, level).length > 0
                                    property bool selected: Number(card.entity.vaneVertical) === level
                                    property real vaneAngle: -50 + (level - 1) * 25
                                    color: selected ? "#73FFFFFF" : "#28FFFFFF"
                                    opacity: enabledLevel ? 1 : 0.35

                                    Item {
                                        anchors.fill: parent
                                        property real angle: vaneAngle
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: parent.width * 0.7
                                                height: Math.max(2, Math.round(parent.height * 0.07))
                                                radius: height / 2
                                                color: "#FFFFFF"
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: parent.height * 0.22 + index * parent.height * 0.2
                                                rotation: parent.angle
                                                transformOrigin: Item.Center
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: enabledLevel
                                        onClicked: root.setVaneVertical(card.entity, level)
                                    }
                                }
                            }
                        }

                        Label {
                            width: parent.width
                            visible: card.entity.supportsVaneHorizontal === true
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: "Horizontal vanes"
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            visible: card.entity.supportsVaneHorizontal === true

                            Repeater {
                                model: 5
                                delegate: Rectangle {
                                    width: card.acCellSize
                                    height: width
                                    radius: Theme.paddingSmall
                                    property int level: index + 1
                                    property bool enabledLevel: root.acLevelMode(card.entity.vaneHorizontalLevels, level).length > 0
                                    property bool selected: Number(card.entity.vaneHorizontal) === level
                                    property real vaneAngle: -50 + (level - 1) * 25
                                    color: selected ? "#73FFFFFF" : "#28FFFFFF"
                                    opacity: enabledLevel ? 1 : 0.35

                                    Item {
                                        anchors.fill: parent
                                        property real angle: vaneAngle
                                        Repeater {
                                            model: 3
                                            Rectangle {
                                                width: Math.max(2, Math.round(parent.width * 0.08))
                                                height: parent.height * 0.62
                                                radius: width / 2
                                                color: "#FFFFFF"
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: parent.width * 0.22 + index * parent.width * 0.22
                                                rotation: parent.angle
                                                transformOrigin: Item.Center
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: enabledLevel
                                        onClicked: root.setVaneHorizontal(card.entity, level)
                                    }
                                }
                            }
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
