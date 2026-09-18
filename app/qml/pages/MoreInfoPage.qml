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
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property string domain: dashboard ? dashboard.domainOf(entityId) : ""
    readonly property bool on: (dashboard && rev >= 0) ? dashboard.isOn(entityId) : false
    readonly property real latitude: page.locationLatitude()
    readonly property real longitude: page.locationLongitude()
    readonly property real locationRadius: page.locationAccuracy()
    readonly property bool hasLocation: isFinite(page.latitude) && isFinite(page.longitude)
                                        && Math.abs(page.latitude) <= 90
                                        && Math.abs(page.longitude) <= 180
                                        && !(page.latitude === 0 && page.longitude === 0)
    readonly property var relatedIds: {
        if (!dashboard || page.rev < 0 || !page.entityId.length)
            return []
        return dashboard.relatedEntities(page.entityId) || []
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

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: page.domain === "camera"
            MenuItem {
                text: "Restart stream"
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
                text: (dashboard && page.rev >= 0) ? dashboard.formatState(page.entityId) : ""
            }

            HistoryGraph {
                width: parent.width
                dashboard: page.dashboard
                entityId: page.entityId
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
                text: page.on ? "Turn off" : "Turn on"
                onClicked: {
                    if (page.domain === "camera")
                        dashboard.callService("camera",
                                              page.on ? "turn_off" : "turn_on",
                                              {}, page.entityId)
                    else
                        dashboard.toggle(page.entityId)
                }
            }

            Slider {
                width: parent.width
                visible: page.domain === "light" && page.on
                minimumValue: 0
                maximumValue: 100
                value: {
                    var b = (dashboard && page.rev >= 0)
                            ? Number(dashboard.attribute(page.entityId, "brightness")) : 0
                    return b ? Math.round(b * 100 / 255) : 0
                }
                label: "Brightness"
                onReleased: dashboard.callService("light", "turn_on",
                                                  { "brightness_pct": Math.round(value) }, page.entityId)
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
                    text: "Open"
                    onClicked: dashboard.callService("cover", "open_cover", {}, page.entityId)
                }
                Button {
                    text: "Stop"
                    onClicked: dashboard.callService("cover", "stop_cover", {}, page.entityId)
                }
                Button {
                    text: "Close"
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
                label: "Position"
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
                label: "Value"
                onReleased: dashboard.callService(page.domain, "set_value",
                                                  { "value": value }, page.entityId)
            }

            SectionHeader {
                text: "Controls"
                visible: page.relatedControls.length > 0
            }

            Repeater {
                model: page.relatedControls
                delegate: relatedRow
            }

            SectionHeader {
                text: "Sensors"
                visible: page.relatedSensors.length > 0
            }

            Repeater {
                model: page.relatedSensors
                delegate: relatedRow
            }

            SectionHeader {
                text: "Related"
                visible: page.relatedOther.length > 0
            }

            Repeater {
                model: page.relatedOther
                delegate: relatedRow
            }

            SectionHeader {
                text: "Attributes"
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
        id: relatedRow
        BackgroundItem {
            id: row
            width: column.width
            height: Theme.itemSizeSmall
            property string relatedId: String(modelData || "")
            readonly property bool toggleable: dashboard && page.rev >= 0 && row.relatedId.length
                                               ? dashboard.isToggleable(row.relatedId) : false

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
                    visible: row.relatedId.length > 0 && !row.toggleable
                    width: Math.min(implicitWidth, row.width * 0.45)
                    horizontalAlignment: Text.AlignRight
                    text: (dashboard && page.rev >= 0 && row.relatedId.length)
                          ? dashboard.formatState(row.relatedId) : ""
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }

                Switch {
                    id: relatedToggle
                    y: (parent.height - height) / 2
                    visible: row.toggleable
                    automaticCheck: false
                    checked: (row.toggleable && page.rev >= 0)
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
}
