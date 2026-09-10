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
