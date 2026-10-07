import QtQuick 2.6
import Sailfish.Silica 1.0
import harbour.helmsman 1.0
import "../dashboard"

Page {
    id: page
    property var hassClient
    property var mdiIcons
    property string entityId: ""
    property var dashboard: hassClient ? hassClient.lovelace : null
    property int entityTick: 0
    readonly property int rev: (dashboard ? dashboard.statesRevision : 0) + entityTick
    readonly property string domain: dashboard ? dashboard.domainOf(entityId) : ""

    Connections {
        target: dashboard
        onEntityChanged: {
            if (entityId === page.entityId)
                page.entityTick++
        }
    }
    readonly property bool on: (dashboard && rev >= 0) ? dashboard.isOn(entityId) : false
    readonly property real latitude: page.locationLatitude()
    readonly property real longitude: page.locationLongitude()
    readonly property real locationRadius: page.locationAccuracy()
    readonly property bool hasLocation: isFinite(page.latitude) && isFinite(page.longitude)
                                        && Math.abs(page.latitude) <= 90
                                        && Math.abs(page.longitude) <= 180
                                        && !(page.latitude === 0 && page.longitude === 0)
    readonly property var lightGroupMembers: page.lightMemberIds(page.entityId)
    readonly property var relatedIds: {
        if (!dashboard || page.rev < 0 || !page.entityId.length)
            return []
        var related = dashboard.relatedEntities(page.entityId) || []
        var members = page.lightGroupMembers
        if (!members.length)
            return related
        var skip = {}
        for (var i = 0; i < members.length; ++i)
            skip[String(members[i])] = true
        var out = []
        for (var j = 0; j < related.length; ++j) {
            var id = String(related[j] || "")
            if (id.length && !skip[id])
                out.push(id)
        }
        return out
    }
    readonly property var relatedControls: {
        var ids = page.relatedIds
        return page.relatedBucket("controls", ids)
    }
    readonly property var relatedSensors: {
        var ids = page.relatedIds
        return page.relatedBucket("sensors", ids)
    }
    readonly property var relatedOther: {
        var ids = page.relatedIds
        return page.relatedBucket("other", ids)
    }
    readonly property bool numericHistory: page.isNumericHistoryEntity()
    readonly property bool showHistoryTimeline: page.entityId.length > 0
                                                && page.domain !== "camera"
                                                && !page.numericHistory
    readonly property var lightColorSwatches: [
        { "r": 255, "g": 0, "b": 0 },
        { "r": 255, "g": 128, "b": 0 },
        { "r": 255, "g": 220, "b": 0 },
        { "r": 0, "g": 200, "b": 0 },
        { "r": 0, "g": 200, "b": 220 },
        { "r": 0, "g": 80, "b": 255 },
        { "r": 140, "g": 0, "b": 255 },
        { "r": 255, "g": 0, "b": 160 }
    ]
    property int clockTick: 0

    Timer {
        interval: 30000
        running: page.status === PageStatus.Active
        repeat: true
        onTriggered: page.clockTick++
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.domain === "camera"
            MenuItem {
                text: i18n.translation("restart_stream")
                onClicked: {
                    if (dashboard && dashboard.cameraStream)
                        dashboard.cameraStream.restart()
                }
            }
        }

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: (dashboard && page.rev >= 0) ? dashboard.friendlyName(page.entityId) : page.entityId
            }

            Loader {
                width: parent.width
                active: page.domain === "camera"
                sourceComponent: streamComponent
            }

            Item {
                width: parent.width
                height: visible ? Theme.itemSizeMedium : 0
                visible: page.domain !== "camera"
                MdiIcon {
                    id: icon
                    anchors.horizontalCenter: parent.horizontalCenter
                    mdiIcons: page.mdiIcons
                    name: (dashboard && page.rev >= 0) ? dashboard.entityIcon(page.entityId) : ""
                    iconColor: page.on ? Theme.highlightColor : Theme.primaryColor
                    width: Theme.iconSizeLarge
                    height: width
                    opacity: (dashboard && page.rev >= 0 && dashboard.isPending(page.entityId)) ? 0.55 : 1.0
                }
                PendingIndicator {
                    anchors.centerIn: icon
                    dashboard: page.dashboard
                    entityId: page.entityId
                    size: BusyIndicatorSize.Small
                }
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.Wrap
                visible: page.domain !== "script"
                text: (dashboard && page.rev >= 0) ? dashboard.formatState(page.entityId) : ""
            }

            HistoryGraph {
                width: parent.width
                dashboard: page.dashboard
                entityId: page.entityId
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.showHistoryTimeline
                text: i18n.translation("history")
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("HistoryTimelinePage.qml"), {
                                       hassClient: page.hassClient,
                                       mdiIcons: page.mdiIcons,
                                       entityId: page.entityId
                                   })
                }
            }

            DetailItem {
                label: i18n.translation("last_changed")
                value: page.formatEntityTime("last_changed")
                visible: value.length > 0
            }

            DetailItem {
                label: i18n.translation("last_updated")
                value: page.formatEntityTime("last_updated")
                visible: value.length > 0
            }

            Loader {
                id: mapLoader
                width: parent.width
                height: (active && status === Loader.Ready) ? Math.round(width * 0.7) : 0
                active: page.hasLocation
                source: Qt.resolvedUrl("../dashboard/EntityMap.qml")
                onLoaded: {
                    item.dashboard = Qt.binding(function() { return page.dashboard })
                    item.latitude = Qt.binding(function() { return page.latitude })
                    item.longitude = Qt.binding(function() { return page.longitude })
                    item.accuracy = Qt.binding(function() { return page.locationRadius })
                    item.autoFit = false
                    item.interactive = false
                    item.markers = Qt.binding(function() { return page.mapMarkers() })
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dashboard && page.rev >= 0 && (dashboard.isToggleable(page.entityId)
                         || page.cameraPowerSupported())
                text: {
                    if (page.domain === "script")
                        return i18n.translation("run")
                    return page.on ? i18n.translation("turn_off") : i18n.translation("turn_on")
                }
                onClicked: {
                    if (page.domain === "camera")
                        dashboard.callService("camera",
                                              page.on ? "turn_off" : "turn_on",
                                              {}, page.entityId)
                    else
                        dashboard.toggle(page.entityId)
                }
            }

            Loader {
                width: parent.width
                active: page.domain === "light"
                sourceComponent: lightControlsComp
                onLoaded: {
                    item.targetId = Qt.binding(function() { return page.entityId })
                    item.showMemberHeader = false
                }
            }

            SectionHeader {
                text: i18n.translation("lights")
                visible: page.lightGroupMembers.length > 0
            }

            Repeater {
                model: page.lightGroupMembers
                Loader {
                    width: column.width
                    property string memberId: String(modelData || "")
                    sourceComponent: lightControlsComp
                    onLoaded: {
                        item.targetId = Qt.binding(function() { return memberId })
                        item.showMemberHeader = true
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.domain === "climate"
                spacing: Theme.paddingMedium
                Button {
                    text: "−"
                    onClicked: {
                        var t = Number(dashboard.attribute(page.entityId, "temperature"))
                        dashboard.callService("climate", "set_temperature",
                                              { "temperature": t - 0.5 }, page.entityId)
                    }
                }
                Button {
                    text: "+"
                    onClicked: {
                        var t = Number(dashboard.attribute(page.entityId, "temperature"))
                        dashboard.callService("climate", "set_temperature",
                                              { "temperature": t + 0.5 }, page.entityId)
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.domain === "cover"
                spacing: Theme.paddingMedium
                Button {
                    text: i18n.translation("open")
                    onClicked: dashboard.callService("cover", "open_cover", {}, page.entityId)
                }
                Button {
                    text: i18n.translation("stop")
                    onClicked: dashboard.callService("cover", "stop_cover", {}, page.entityId)
                }
                Button {
                    text: i18n.translation("close")
                    onClicked: dashboard.callService("cover", "close_cover", {}, page.entityId)
                }
            }

            Slider {
                width: parent.width
                visible: page.domain === "cover" && dashboard && page.rev >= 0
                         && dashboard.attribute(page.entityId, "current_position") !== undefined
                minimumValue: 0
                maximumValue: 100
                value: (dashboard && page.rev >= 0)
                       ? Number(dashboard.attribute(page.entityId, "current_position")) : 0
                label: i18n.translation("position")
                onReleased: dashboard.callService("cover", "set_cover_position",
                                                  { "position": Math.round(value) }, page.entityId)
            }

            Slider {
                width: parent.width
                visible: (page.domain === "number" || page.domain === "input_number")
                         && dashboard && page.rev >= 0
                minimumValue: page.numberBound("min", 0)
                maximumValue: page.numberBound("max", 100)
                stepSize: page.numberBound("step", 1)
                value: (dashboard && page.rev >= 0)
                       ? Number(dashboard.entityState(page.entityId)) : 0
                label: i18n.translation("value")
                onReleased: dashboard.callService(page.domain, "set_value",
                                                  { "value": value }, page.entityId)
            }

            SectionHeader {
                text: i18n.translation("controls")
                visible: page.relatedControls.length > 0
            }

            Repeater {
                model: page.relatedControls
                delegate: relatedRow
            }

            SectionHeader {
                text: i18n.translation("sensors")
                visible: page.relatedSensors.length > 0
            }

            Repeater {
                model: page.relatedSensors
                delegate: relatedRow
            }

            SectionHeader {
                text: i18n.translation("related")
                visible: page.relatedOther.length > 0
            }

            Repeater {
                model: page.relatedOther
                delegate: relatedRow
            }

            SectionHeader {
                text: i18n.translation("attributes")
                visible: true
            }

            Repeater {
                model: page.attributeList()
                DetailItem {
                    label: modelData.key
                    value: modelData.value
                }
            }
        }
    }

    Component {
        id: streamComponent
        CameraStreamPlayer {
            width: parent.width
            stream: dashboard ? dashboard.cameraStream : null
            entityId: page.entityId
            active: page.status === PageStatus.Active
        }
    }

    Component {
        id: lightControlsComp
        Column {
            id: controls
            width: parent ? parent.width : Screen.width
            spacing: Theme.paddingSmall
            property string targetId: ""
            property bool showMemberHeader: false
            readonly property int rev: page.rev
            readonly property bool on: dashboard && controls.rev >= 0 && controls.targetId.length
                                      ? dashboard.isOn(controls.targetId) : false
            readonly property bool supportsBrightness: page.lightIsDimmable(controls.targetId)
            readonly property bool supportsColorTemp: page.lightHasColorTemp(controls.targetId)
            readonly property bool supportsColor: page.lightHasColor(controls.targetId)
            readonly property int minKelvin: page.lightColorTempMinK(controls.targetId)
            readonly property int maxKelvin: page.lightColorTempMaxK(controls.targetId)
            readonly property var colorChoices: page.lightColorChoicesFor(controls.targetId)

            BackgroundItem {
                id: memberHeader
                width: parent.width
                height: visible ? Theme.itemSizeSmall : 0
                visible: controls.showMemberHeader && controls.targetId.length > 0
                onClicked: {
                    if (!controls.targetId.length || controls.targetId === page.entityId)
                        return
                    pageStack.push(Qt.resolvedUrl("MoreInfoPage.qml"), {
                                       hassClient: page.hassClient,
                                       mdiIcons: page.mdiIcons,
                                       entityId: controls.targetId
                                   })
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.rightMargin: Theme.horizontalPageMargin
                    spacing: Theme.paddingSmall

                    Item {
                        y: (parent.height - height) / 2
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall

                        MdiIcon {
                            anchors.fill: parent
                            mdiIcons: page.mdiIcons
                            name: (dashboard && controls.rev >= 0 && controls.targetId.length)
                                  ? dashboard.entityIcon(controls.targetId) : ""
                            iconColor: controls.on ? Theme.highlightColor : Theme.primaryColor
                            width: Theme.iconSizeSmall
                            opacity: (dashboard && controls.rev >= 0 && controls.targetId.length
                                      && dashboard.isPending(controls.targetId)) ? 0.55 : 1.0
                        }

                        PendingIndicator {
                            anchors.centerIn: parent
                            dashboard: page.dashboard
                            entityId: controls.targetId
                        }
                    }

                    Label {
                        y: (parent.height - height) / 2
                        width: Math.max(0, parent.width - Theme.iconSizeSmall - Theme.paddingSmall
                                        - memberToggle.width - Theme.paddingSmall)
                        text: (dashboard && controls.rev >= 0 && controls.targetId.length)
                              ? dashboard.friendlyName(controls.targetId) : controls.targetId
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primaryColor
                    }

                    Switch {
                        id: memberToggle
                        y: (parent.height - height) / 2
                        automaticCheck: false
                        checked: controls.on
                        onClicked: {
                            if (dashboard && controls.targetId.length)
                                dashboard.toggle(controls.targetId)
                        }
                    }
                }
            }

            Slider {
                width: parent.width
                visible: controls.supportsBrightness && controls.on
                minimumValue: 0
                maximumValue: 100
                value: {
                    var b = (dashboard && controls.rev >= 0 && controls.targetId.length)
                            ? Number(dashboard.attribute(controls.targetId, "brightness")) : 0
                    return b ? Math.round(b * 100 / 255) : 0
                }
                label: i18n.translation("brightness")
                onReleased: {
                    if (dashboard && controls.targetId.length)
                        dashboard.callService("light", "turn_on",
                                              { "brightness_pct": Math.round(value) },
                                              controls.targetId)
                }
            }

            Slider {
                id: temperature
                width: parent.width
                visible: controls.supportsColorTemp && controls.on
                minimumValue: controls.minKelvin
                maximumValue: controls.maxKelvin
                stepSize: 50
                valueText: Math.round(value) + " K"
                label: i18n.translation("temperature")

                Binding {
                    target: temperature
                    property: "value"
                    value: {
                        var k = page.lightCurrentKelvin(controls.targetId)
                        if (k <= 0)
                            return (temperature.minimumValue + temperature.maximumValue) / 2
                        return k
                    }
                    when: !temperature.down
                }

                onReleased: {
                    if (dashboard && controls.targetId.length)
                        dashboard.callService("light", "turn_on",
                                              { "color_temp_kelvin": Math.round(value) },
                                              controls.targetId)
                }
            }

            Column {
                width: parent.width
                spacing: Theme.paddingSmall
                visible: controls.supportsColor && controls.on

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    text: i18n.translation("color")
                }

                Row {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    spacing: Theme.paddingSmall

                    Repeater {
                        model: controls.colorChoices
                        delegate: Rectangle {
                            readonly property int swatchCount: controls.colorChoices.length
                            width: {
                                var n = swatchCount
                                var gap = Theme.paddingSmall
                                if (n <= 0)
                                    return Theme.iconSizeSmall
                                return Math.max(Theme.iconSizeSmall,
                                                Math.floor((parent.width - (n - 1) * gap) / n))
                            }
                            height: width
                            radius: Theme.paddingSmall
                            color: Qt.rgba(modelData.r / 255,
                                           modelData.g / 255,
                                           modelData.b / 255, 1)
                            property bool selected: page.lightColorSwatchSelected(controls.targetId,
                                                                                  modelData)
                            property bool isWhite: modelData.r === 255
                                                   && modelData.g === 255
                                                   && modelData.b === 255
                            border.width: selected ? 3 : (isWhite ? 1 : 0)
                            border.color: selected
                                          ? (isWhite ? "#222222" : "#FFFFFF")
                                          : "#80FFFFFF"

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (dashboard && controls.targetId.length)
                                        dashboard.callService("light", "turn_on",
                                                              { "rgb_color": [modelData.r,
                                                                              modelData.g,
                                                                              modelData.b] },
                                                              controls.targetId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: relatedRow
        BackgroundItem {
            id: row
            width: column.width
            height: Theme.itemSizeSmall
            property string relatedId: String(modelData || "")
            readonly property bool isScript: row.relatedId.indexOf("script.") === 0
            readonly property bool toggleable: dashboard && page.rev >= 0 && row.relatedId.length
                                               ? dashboard.isToggleable(row.relatedId) : false
            readonly property bool showRun: row.isScript
            readonly property bool showToggle: row.toggleable && !row.isScript
            readonly property bool showState: row.relatedId.length > 0 && !row.toggleable && !row.isScript

            onClicked: {
                if (!row.relatedId.length)
                    return
                pageStack.push(Qt.resolvedUrl("MoreInfoPage.qml"), {
                                   hassClient: page.hassClient,
                                   mdiIcons: page.mdiIcons,
                                   entityId: row.relatedId
                               })
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.horizontalPageMargin
                spacing: Theme.paddingSmall

                Item {
                    id: relatedIconBox
                    y: (parent.height - height) / 2
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall

                    MdiIcon {
                        id: relatedIcon
                        anchors.fill: parent
                        mdiIcons: page.mdiIcons
                        name: (dashboard && page.rev >= 0 && row.relatedId.length)
                              ? dashboard.entityIcon(row.relatedId) : ""
                        iconColor: (dashboard && page.rev >= 0 && row.relatedId.length
                                    && dashboard.isOn(row.relatedId))
                                   ? Theme.highlightColor : Theme.primaryColor
                        width: Theme.iconSizeSmall
                        opacity: (dashboard && page.rev >= 0 && row.relatedId.length
                                  && dashboard.isPending(row.relatedId)) ? 0.55 : 1.0
                    }

                    PendingIndicator {
                        anchors.centerIn: parent
                        dashboard: page.dashboard
                        entityId: row.relatedId
                    }
                }

                Label {
                    y: (parent.height - height) / 2
                    width: Math.max(0, parent.width - relatedIconBox.width - Theme.paddingSmall
                                    - (relatedState.visible
                                       ? relatedState.width + Theme.paddingSmall : 0)
                                    - (relatedRun.visible
                                       ? relatedRun.width + Theme.paddingSmall : 0)
                                    - (relatedToggle.visible
                                       ? relatedToggle.width + Theme.paddingSmall : 0))
                    text: (dashboard && page.rev >= 0 && row.relatedId.length)
                          ? dashboard.friendlyName(row.relatedId) : row.relatedId
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primaryColor
                }

                Label {
                    id: relatedState
                    y: (parent.height - height) / 2
                    visible: row.showState
                    width: Math.min(implicitWidth, row.width * 0.45)
                    horizontalAlignment: Text.AlignRight
                    text: (dashboard && page.rev >= 0 && row.relatedId.length)
                          ? dashboard.formatState(row.relatedId) : ""
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }

                Button {
                    id: relatedRun
                    y: (parent.height - height) / 2
                    visible: row.showRun
                    preferredWidth: Theme.buttonWidthExtraSmall
                    height: Theme.itemSizeExtraSmall
                    text: i18n.translation("run")
                    onClicked: dashboard.toggle(row.relatedId)
                }

                Switch {
                    id: relatedToggle
                    y: (parent.height - height) / 2
                    visible: row.showToggle
                    automaticCheck: false
                    checked: (row.showToggle && page.rev >= 0)
                             ? dashboard.isOn(row.relatedId) : false
                    onClicked: dashboard.toggle(row.relatedId)
                }
            }
        }
    }

    function relatedBucket(kind, all) {
        var out = []
        if (!all || !dashboard || page.rev < 0)
            return out
        for (var i = 0; i < all.length; ++i) {
            var id = String(all[i])
            var domain = dashboard.domainOf(id)
            var control = dashboard.isToggleable(id)
                          || domain === "number" || domain === "input_number"
                          || domain === "select" || domain === "input_select"
            var sensor = domain === "sensor" || domain === "binary_sensor"
            if (kind === "controls" && control)
                out.push(id)
            else if (kind === "sensors" && sensor)
                out.push(id)
            else if (kind === "other" && !control && !sensor)
                out.push(id)
        }
        return out
    }

    function numberBound(key, fallback) {
        if (!dashboard || page.rev < 0)
            return fallback
        var n = Number(dashboard.attribute(page.entityId, key))
        return isFinite(n) && (key !== "step" || n > 0) ? n : fallback
    }

    function cameraPowerSupported() {
        if (page.domain !== "camera" || !dashboard || page.rev < 0)
            return false
        var features = Number(dashboard.attribute(page.entityId, "supported_features"))
        return (features & 1) === 1
    }

    function lightSupportedColorModes(id) {
        if (!dashboard || page.rev < 0 || !id)
            return []
        var modes = dashboard.attribute(id, "supported_color_modes")
        if (!modes || !modes.length)
            return []
        var out = []
        for (var i = 0; i < modes.length; ++i) {
            var mode = String(modes[i] || "")
            if (mode.length)
                out.push(mode)
        }
        return out
    }

    function lightModesContain(id, wanted) {
        var modes = page.lightSupportedColorModes(id)
        for (var i = 0; i < wanted.length; ++i) {
            for (var j = 0; j < modes.length; ++j) {
                if (modes[j] === wanted[i])
                    return true
            }
        }
        return false
    }

    function lightIsDimmable(id) {
        if (!dashboard || page.rev < 0 || !id)
            return false
        var modes = page.lightSupportedColorModes(id)
        for (var i = 0; i < modes.length; ++i) {
            if (modes[i] !== "onoff")
                return true
        }
        var brightness = dashboard.attribute(id, "brightness")
        if (brightness !== undefined && brightness !== null && isFinite(Number(brightness)))
            return true
        var features = Number(dashboard.attribute(id, "supported_features"))
        return (features & 1) !== 0
    }

    function lightHasColorTemp(id) {
        if (!dashboard || page.rev < 0 || !id)
            return false
        if (page.lightModesContain(id, ["color_temp"]))
            return true
        var features = Number(dashboard.attribute(id, "supported_features"))
        return (features & 2) !== 0
    }

    function lightHasColor(id) {
        if (!dashboard || page.rev < 0 || !id)
            return false
        if (page.lightModesContain(id, ["hs", "xy", "rgb", "rgbw", "rgbww"]))
            return true
        var features = Number(dashboard.attribute(id, "supported_features"))
        return (features & 16) !== 0
    }

    function lightColorChoicesFor(id) {
        var list = []
        var src = page.lightColorSwatches
        for (var i = 0; i < src.length; ++i)
            list.push(src[i])
        if (!page.lightHasColorTemp(id))
            list.push({ "r": 255, "g": 255, "b": 255 })
        return list
    }

    function lightMiredsToKelvin(mireds) {
        var m = Number(mireds)
        if (!isFinite(m) || m <= 0)
            return 0
        return Math.max(1000, Math.min(10000, Math.round(1000000 / m)))
    }

    function lightColorTempRangeK(id) {
        var minK = 0
        var maxK = 0
        if (dashboard && page.rev >= 0 && id) {
            minK = Number(dashboard.attribute(id, "min_color_temp_kelvin"))
            maxK = Number(dashboard.attribute(id, "max_color_temp_kelvin"))
            if (!isFinite(minK) || minK <= 0 || !isFinite(maxK) || maxK <= 0) {
                var minMireds = Number(dashboard.attribute(id, "min_mireds"))
                var maxMireds = Number(dashboard.attribute(id, "max_mireds"))
                if ((!isFinite(minK) || minK <= 0) && isFinite(maxMireds) && maxMireds > 0)
                    minK = page.lightMiredsToKelvin(maxMireds)
                if ((!isFinite(maxK) || maxK <= 0) && isFinite(minMireds) && minMireds > 0)
                    maxK = page.lightMiredsToKelvin(minMireds)
            }
        }
        if (!isFinite(minK) || minK <= 0)
            minK = 2000
        if (!isFinite(maxK) || maxK <= 0)
            maxK = 6500
        if (minK > maxK) {
            var tmp = minK
            minK = maxK
            maxK = tmp
        }
        return { min: Math.round(minK), max: Math.round(maxK) }
    }

    function lightColorTempMinK(id) {
        return page.lightColorTempRangeK(id).min
    }

    function lightColorTempMaxK(id) {
        return page.lightColorTempRangeK(id).max
    }

    function lightCurrentKelvin(id) {
        if (!dashboard || page.rev < 0 || !id)
            return 0
        var k = Number(dashboard.attribute(id, "color_temp_kelvin"))
        if (isFinite(k) && k > 0)
            return Math.round(k)
        var mireds = Number(dashboard.attribute(id, "color_temp"))
        if (isFinite(mireds) && mireds > 0)
            return page.lightMiredsToKelvin(mireds)
        return 0
    }

    function lightCurrentRgb(id) {
        if (!dashboard || page.rev < 0 || !id)
            return null
        var rgb = dashboard.attribute(id, "rgb_color")
        if (rgb && rgb.length >= 3) {
            return {
                r: Math.max(0, Math.min(255, Math.round(Number(rgb[0]) || 0))),
                g: Math.max(0, Math.min(255, Math.round(Number(rgb[1]) || 0))),
                b: Math.max(0, Math.min(255, Math.round(Number(rgb[2]) || 0)))
            }
        }
        var hs = dashboard.attribute(id, "hs_color")
        if (!hs || hs.length < 2)
            return null
        var hue = ((Number(hs[0]) % 360) + 360) % 360
        var sat = Math.max(0, Math.min(100, Number(hs[1]))) / 100
        var c = sat
        var x = c * (1 - Math.abs((hue / 60) % 2 - 1))
        var r = 0, g = 0, b = 0
        if (hue < 60) { r = c; g = x }
        else if (hue < 120) { r = x; g = c }
        else if (hue < 180) { g = c; b = x }
        else if (hue < 240) { g = x; b = c }
        else if (hue < 300) { r = x; b = c }
        else { r = c; b = x }
        return {
            r: Math.round(r * 255),
            g: Math.round(g * 255),
            b: Math.round(b * 255)
        }
    }

    function lightColorSwatchSelected(id, swatch) {
        if (!swatch || !dashboard || page.rev < 0 || !id)
            return false
        var mode = String(dashboard.attribute(id, "color_mode") || "")
        if (mode === "color_temp")
            return false
        var rgb = page.lightCurrentRgb(id)
        if (!rgb)
            return false
        return Math.abs(rgb.r - swatch.r) < 40
                && Math.abs(rgb.g - swatch.g) < 40
                && Math.abs(rgb.b - swatch.b) < 40
    }

    function normalizeEntityIdList(raw) {
        var out = []
        if (raw === undefined || raw === null)
            return out
        if (typeof raw === "string") {
            if (raw.length)
                out.push(raw)
            return out
        }
        if (!raw.length)
            return out
        for (var i = 0; i < raw.length; ++i) {
            var item = raw[i]
            if (item === undefined || item === null)
                continue
            if (typeof item === "string") {
                if (item.length)
                    out.push(item)
                continue
            }
            if (typeof item === "object") {
                var entity = String(item.entity || item.entity_id || "")
                if (entity.length)
                    out.push(entity)
            }
        }
        return out
    }

    function lightMemberIds(groupId) {
        if (!dashboard || page.rev < 0 || !groupId)
            return []
        if (dashboard.domainOf(groupId) !== "light")
            return []
        var ids = page.normalizeEntityIdList(dashboard.attribute(groupId, "entity_id"))
        var out = []
        var seen = {}
        for (var i = 0; i < ids.length; ++i) {
            var id = String(ids[i] || "")
            if (!id || id === groupId || seen[id])
                continue
            if (dashboard.domainOf(id) !== "light")
                continue
            var st = dashboard.entity(id)
            if (!st || !st.state)
                continue
            seen[id] = true
            out.push(id)
        }
        return out
    }

    function coordNumber(value) {
        if (value === undefined || value === null || value === "")
            return NaN
        var n = Number(value)
        return isFinite(n) ? n : NaN
    }

    function attributeNumber(name) {
        if (!dashboard || page.rev < 0)
            return NaN
        return page.coordNumber(dashboard.attribute(page.entityId, name))
    }

    function gpsPair() {
        if (!dashboard || page.rev < 0)
            return null
        var gps = dashboard.attribute(page.entityId, "gps")
        if (!gps || gps.length < 2)
            return null
        var lat = page.coordNumber(gps[0] !== undefined ? gps[0] : gps.latitude)
        var lon = page.coordNumber(gps[1] !== undefined ? gps[1] : gps.longitude)
        if (!isFinite(lat) || !isFinite(lon))
            return null
        return [lat, lon]
    }

    function locationLatitude() {
        var lat = page.attributeNumber("latitude")
        if (isFinite(lat))
            return lat
        var gps = page.gpsPair()
        return gps ? gps[0] : NaN
    }

    function locationLongitude() {
        var lon = page.attributeNumber("longitude")
        if (isFinite(lon))
            return lon
        var gps = page.gpsPair()
        return gps ? gps[1] : NaN
    }

    function locationAccuracy() {
        var radius = page.attributeNumber("radius")
        if (isFinite(radius) && radius > 0)
            return radius
        var accuracy = page.attributeNumber("gps_accuracy")
        if (isFinite(accuracy) && accuracy > 0)
            return accuracy
        return 0
    }

    function mapMarkers() {
        if (!page.hasLocation)
            return []
        var pic = ""
        var name = page.entityId
        if (dashboard && page.rev >= 0) {
            pic = dashboard.mediaPathOf(dashboard.attribute(page.entityId, "entity_picture")) || ""
            name = dashboard.friendlyName(page.entityId)
        }
        return [{
                    "id": page.entityId,
                    "lat": page.latitude,
                    "lon": page.longitude,
                    "name": name,
                    "picture": pic,
                    "accuracy": page.locationRadius
                }]
    }

    function attributeList() {
        if (!dashboard || page.rev < 0)
            return []
        var st = dashboard.entity(page.entityId)
        var attrs = st && st.attributes ? st.attributes : {}
        var out = []
        for (var key in attrs) {
            if (!attrs.hasOwnProperty(key))
                continue
            var val = attrs[key]
            if (typeof val === "object")
                continue
            if (key === "access_token" || key === "entity_picture")
                continue
            out.push({ "key": key, "value": String(val) })
        }
        return out
    }

    function isNumericHistoryEntity() {
        if (!dashboard || page.rev < 0 || !page.entityId.length)
            return false
        var unit = dashboard.attribute(page.entityId, "unit_of_measurement")
        if (unit !== undefined && unit !== null && String(unit).length)
            return true
        var state = dashboard.entityState(page.entityId)
        if (!state || state === "unavailable" || state === "unknown")
            return false
        var n = Number(state)
        return !isNaN(n)
    }

    function parseEntityStamp(stamp) {
        if (!stamp)
            return null
        var t = Date.parse(String(stamp))
        return isNaN(t) ? null : new Date(t)
    }

    function formatEntityTime(field) {
        var tick = page.clockTick
        if (!dashboard || page.rev < 0 || !page.entityId.length)
            return ""
        var st = dashboard.entity(page.entityId)
        if (!st)
            return ""
        var d = page.parseEntityStamp(st[field])
        if (!d)
            return ""
        var ago = Format.formatDate(d, Formatter.DurationElapsed)
        var stamp = Format.formatDate(d, Formatter.Timepoint)
        if (!ago || !ago.length)
            return stamp
        return ago + " (" + stamp + ")"
    }
}
