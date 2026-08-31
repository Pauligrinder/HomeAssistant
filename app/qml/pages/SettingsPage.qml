import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property var hassClient
    property string pendingTestUrl: ""
    property string internalTestResult: ""
    property string externalTestResult: ""

    function save() {
        hassClient.saveConnectionSettings(
                    internalField.text,
                    externalField.text,
                    ssidField.text,
                    ignoreSslSwitch.checked)
        pageStack.pop()
    }

    WifiChecker {
        id: wifi
        onNetworkChanged: {
            hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
            if (ssidField.text.length === 0 && wifi.ssid.length > 0)
                ssidField.placeholderText = wifi.ssid
        }
    }

    Connections {
        target: hassClient
        onConnectionTestFinished: {
            if (endpoint === internalField.text) {
                internalTestResult = success
                        ? ("Internal: " + message)
                        : ("Internal failed: " + message)
            } else if (endpoint === externalField.text) {
                externalTestResult = success
                        ? ("External: " + message)
                        : ("External failed: " + message)
            }
            page.pendingTestUrl = ""
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: "Helmsman settings" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Use full URLs including the scheme. Internal is often http:// on LAN; external is often https://."
            }

            TextField {
                id: internalField
                width: parent.width
                label: "Internal URL"
                placeholderText: "http://homeassistant.local"
                text: hassClient.internalUrl
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.pendingTestUrl === internalField.text ? "Testing internal..." : "Test internal"
                enabled: internalField.text.length > 0
                         && !hassClient.testingConnection
                         && page.pendingTestUrl.length === 0
                onClicked: {
                    internalTestResult = ""
                    page.pendingTestUrl = internalField.text
                    hassClient.testEndpoint(internalField.text, ignoreSslSwitch.checked)
                }
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: internalTestResult.length > 0
                text: internalTestResult
            }

            TextField {
                id: externalField
                width: parent.width
                label: "External URL"
                placeholderText: "https://example.ui.nabu.casa"
                text: hassClient.externalUrl
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.pendingTestUrl === externalField.text ? "Testing external..." : "Test external"
                enabled: externalField.text.length > 0
                         && !hassClient.testingConnection
                         && page.pendingTestUrl.length === 0
                onClicked: {
                    externalTestResult = ""
                    page.pendingTestUrl = externalField.text
                    hassClient.testEndpoint(externalField.text, ignoreSslSwitch.checked)
                }
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: externalTestResult.length > 0
                text: externalTestResult
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "If you only have one address, put it in External URL and leave Internal URL empty. Helmsman will not switch between addresses in that case."
            }

            TextField {
                id: ssidField
                width: parent.width
                visible: internalField.text.length > 0
                label: "Home Wi‑Fi SSID"
                placeholderText: wifi.ssid.length > 0 ? wifi.ssid : "MyHomeWifi"
                text: hassClient.homeWifiSsid
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: internalField.text.length > 0
                text: "Use current Wi‑Fi"
                enabled: wifi.ssid.length > 0
                onClicked: ssidField.text = wifi.ssid
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: internalField.text.length > 0
                text: wifi.ssid.length > 0
                      ? ("Current Wi‑Fi: " + wifi.ssid
                         + (hassClient.usingInternalUrl ? " · using internal" : " · using external"))
                      : "Not connected to Wi‑Fi"
            }

            TextSwitch {
                id: ignoreSslSwitch
                text: "Ignore certificate errors"
                checked: hassClient.ignoreSslErrors
                description: "Needed for self-signed HTTPS certificates."
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: {
                    if (!hassClient.mobileAppRegistered)
                        return "Notifications: registering device with Home Assistant…"
                    if (hassClient.pushConnected)
                        return "Notifications: connected as " + hassClient.deviceName
                    return "Notifications: registered, reconnecting…"
                }
            }

            SectionHeader { text: "Cover favorites" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Pick lights to show on the app cover. Tap a light on the cover to toggle it."
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Choose cover favorites"
                enabled: hassClient.loggedIn
                onClicked: pageStack.push(Qt.resolvedUrl("EventsViewSettingsPage.qml"),
                                          { hassClient: hassClient,
                                            eventsViewMode: false })
            }

            SectionHeader { text: "Events View favorites" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Pick lights to show in the Events View. Each light gets its own card there; tap a card to toggle it, or hold a dimmable light to set its brightness."
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Choose Events View favorites"
                enabled: hassClient.loggedIn
                onClicked: pageStack.push(Qt.resolvedUrl("EventsViewSettingsPage.qml"),
                                          { hassClient: hassClient,
                                            eventsViewMode: true })
            }

            SectionHeader { text: "Sensors" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Choose which device sensors Helmsman reports to Home Assistant."
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: hassClient.sensors && hassClient.sensors.lastError.length > 0
                text: hassClient.sensors ? ("Last error: " + hassClient.sensors.lastError) : ""
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: {
                    if (!hassClient.sensors)
                        return "Sensors: unavailable"
                    if (!hassClient.mobileAppRegistered)
                        return "Sensors: waiting for mobile_app registration…"
                    if (hassClient.sensors.active)
                        return "Sensors: reporting"
                    return "Sensors: idle"
                }
            }

            Repeater {
                model: hassClient.sensors ? hassClient.sensors.sensorStatuses : []
                delegate: TextSwitch {
                    width: column.width
                    visible: modelData.uniqueId !== "location"
                    height: visible ? implicitHeight : 0
                    text: modelData.name
                    checked: modelData.enabled
                    description: {
                        var bits = []
                        if (modelData.disabled)
                            bits.push("Disabled in Home Assistant")
                        if (modelData.state && modelData.state.length)
                            bits.push(modelData.state)
                        if (modelData.lastUpdated && modelData.lastUpdated.length)
                            bits.push("updated " + modelData.lastUpdated)
                        if (modelData.lastError && modelData.lastError.length)
                            bits.push(modelData.lastError)
                        return bits.join(" · ")
                    }
                    onCheckedChanged: {
                        if (hassClient.sensors
                                && modelData.enabled !== checked) {
                            hassClient.sensors.setSensorEnabled(
                                        modelData.uniqueId, checked)
                        }
                    }
                }
            }

            SectionHeader { text: "Location" }

            TextSwitch {
                id: locationEnabledSwitch
                text: "Report location"
                checked: hassClient.sensors
                         ? hassClient.sensors.locationEnabled : true
                description: hassClient.sensors
                             && !hassClient.sensors.locationReporting
                             && hassClient.sensors.locationEnabled
                             ? "Location is disabled in Home Assistant."
                             : "Allow Helmsman to update the Home Assistant device tracker."
                onCheckedChanged: {
                    if (hassClient.sensors
                            && hassClient.sensors.locationEnabled !== checked)
                        hassClient.sensors.locationEnabled = checked
                }
            }

            ComboBox {
                id: locationPresetBox
                width: parent.width
                enabled: locationEnabledSwitch.checked
                label: "Location update mode"
                currentIndex: hassClient.sensors
                              ? hassClient.sensors.locationPreset : 1
                menu: ContextMenu {
                    MenuItem { text: "Battery saver" }
                    MenuItem { text: "Balanced" }
                    MenuItem { text: "Accurate" }
                }
                onCurrentIndexChanged: {
                    if (hassClient.sensors
                            && hassClient.sensors.locationPreset !== currentIndex)
                        hassClient.sensors.locationPreset = currentIndex
                }
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: locationEnabledSwitch.checked
                text: {
                    if (locationPresetBox.currentIndex === 0)
                        return "Fewer Home Assistant updates for lower battery use."
                    if (locationPresetBox.currentIndex === 2)
                        return "More frequent Home Assistant updates when a fix is available."
                    return "A balance of update speed and battery use. GPS is not kept running."
                }
            }

            Slider {
                id: staleSlider
                width: parent.width
                enabled: locationEnabledSwitch.checked
                label: "Request own location if older than"
                minimumValue: 5
                maximumValue: 60
                stepSize: 5
                value: hassClient.sensors
                       ? hassClient.sensors.locationStaleMinutes : 15
                valueText: Math.round(value) + " min"
                onValueChanged: {
                    var mins = Math.round(value)
                    if (hassClient.sensors
                            && hassClient.sensors.locationStaleMinutes !== mins)
                        hassClient.sensors.locationStaleMinutes = mins
                }
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: locationEnabledSwitch.checked
                text: "Uses location updates from other apps when they request GPS. Helmsman only turns GPS on itself if the last fix is older than this."
            }

            TextSwitch {
                id: homeOnInternalSwitch
                visible: internalField.text.length > 0
                enabled: locationEnabledSwitch.checked
                text: "Mark home on internal connection"
                checked: hassClient.sensors ? hassClient.sensors.homeOnInternal : true
                description: "Report home without using GPS while connected through the internal URL. When disabled, no location is sent on that connection."
                onCheckedChanged: {
                    if (hassClient.sensors
                            && hassClient.sensors.homeOnInternal !== checked)
                        hassClient.sensors.homeOnInternal = checked
                }
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: hassClient.sensors
                         && hassClient.sensors.lastLocationText.length > 0
                text: hassClient.sensors
                      ? ("Last location: " + hassClient.sensors.lastLocationText) : ""
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Refresh sensor config"
                enabled: hassClient.sensors && hassClient.sensors.active
                onClicked: hassClient.sensors.refreshConfig()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Save"
                enabled: internalField.text.length > 0 || externalField.text.length > 0
                onClicked: page.save()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sign out"
                onClicked: {
                    hassClient.logout()
                    pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: "App " + hassClient.appVersion
            }
        }
    }
}
