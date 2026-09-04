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

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: (dashboard && page.rev >= 0) ? dashboard.friendlyName(page.entityId) : page.entityId
            }

            Item {
                width: parent.width
                height: Theme.itemSizeMedium
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

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dashboard && page.rev >= 0 && dashboard.isToggleable(page.entityId)
                text: page.on ? "Turn off" : "Turn on"
                onClicked: dashboard.toggle(page.entityId)
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
            out.push({ "key": key, "value": String(val) })
        }
        return out
    }
}
