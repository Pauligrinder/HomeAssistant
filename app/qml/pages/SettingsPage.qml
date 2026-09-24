import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property var hassClient
    property string pendingTestUrl: ""
    property string internalTestResult: ""
    property string externalTestResult: ""

    // Content loaders create items lazily; keep handles for binds/save.
    property var engineBox
    property var internalField
    property var externalField
    property var ssidField
    property var ignoreSslSwitch

    function engineNameFor(id) {
        var list = hassClient ? hassClient.availableWebViewEngines : []
        for (var i = 0; i < list.length; ++i) {
            if (list[i].id === id)
                return list[i].name
        }
        return id
    }

    function languageNameFor(id) {
        var list = hassClient ? hassClient.availableUiLanguages : []
        for (var i = 0; i < list.length; ++i) {
            if (list[i].id === id)
                return list[i].name
        }
        return id && id.length ? id : qsTr("System")
    }

    function bindEngineCombo() {
        if (!engineBox || !hassClient)
            return
        engineBox.engineReady = false
        var idx = 0
        var list = hassClient.availableWebViewEngines
        for (var i = 0; i < list.length; ++i) {
            if (list[i].id === hassClient.webViewEngine)
                idx = i
        }
        engineBox.currentIndex = idx
        engineBox.engineReady = true
    }

    function activateSections() {
        // Keep fields alive while collapsed so Save / binds still work.
        for (var i = 0; i < sections.children.length; ++i) {
            var child = sections.children[i]
            if (child && child.content)
                child.content.active = true
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Active && hassClient)
            hassClient.refreshWebViewEngines()
    }

    function save() {
        if (!internalField || !externalField || !ssidField || !ignoreSslSwitch)
            return
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
            if (page.ssidField && page.ssidField.text.length === 0 && wifi.ssid.length > 0)
                page.ssidField.placeholderText = wifi.ssid
        }
    }

    Connections {
        target: hassClient
        onConnectionTestFinished: {
            if (!page.internalField || !page.externalField)
                return
            if (endpoint === page.internalField.text) {
                internalTestResult = success
                        ? qsTr("Internal: %1").arg(message)
                        : qsTr("Internal failed: %1").arg(message)
            } else if (endpoint === page.externalField.text) {
                externalTestResult = success
                        ? qsTr("External: %1").arg(message)
                        : qsTr("External failed: %1").arg(message)
            }
            page.pendingTestUrl = ""
        }
        onAvailableWebViewEnginesChanged: page.bindEngineCombo()
        onWebViewEngineChanged: page.bindEngineCombo()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width

            PageHeader { title: qsTr("Helmsman settings") }

            ExpandingSectionGroup {
                id: sections
                width: parent.width
                currentIndex: 0

                ExpandingSection {
                    id: connectionSection
                    title: qsTr("Connection")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: qsTr("Use full URLs including the scheme. Internal is often http:// on LAN; external is often https://.")
                        }

                        TextField {
                            id: internalField
                            width: parent.width
                            label: qsTr("Internal URL")
                            placeholderText: "http://homeassistant.local"
                            text: hassClient.internalUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
                            Component.onCompleted: page.internalField = internalField
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.pendingTestUrl === internalField.text
                                  ? qsTr("Testing internal...") : qsTr("Test internal")
                            enabled: internalField.text.length > 0
                                     && !hassClient.testingConnection
                                     && page.pendingTestUrl.length === 0
                            onClicked: {
                                page.internalTestResult = ""
                                page.pendingTestUrl = internalField.text
                                hassClient.testEndpoint(internalField.text, ignoreSslSwitch.checked)
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: page.internalTestResult.length > 0
                            text: page.internalTestResult
                        }

                        TextField {
                            id: externalField
                            width: parent.width
                            label: qsTr("External URL")
                            placeholderText: "https://example.ui.nabu.casa"
                            text: hassClient.externalUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
                            Component.onCompleted: page.externalField = externalField
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.pendingTestUrl === externalField.text
                                  ? qsTr("Testing external...") : qsTr("Test external")
                            enabled: externalField.text.length > 0
                                     && !hassClient.testingConnection
                                     && page.pendingTestUrl.length === 0
                            onClicked: {
                                page.externalTestResult = ""
                                page.pendingTestUrl = externalField.text
                                hassClient.testEndpoint(externalField.text, ignoreSslSwitch.checked)
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: page.externalTestResult.length > 0
                            text: page.externalTestResult
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: qsTr("If you only have one address, put it in External URL and leave Internal URL empty. Helmsman will not switch between addresses in that case.")
                        }

                        TextField {
                            id: ssidField
                            width: parent.width
                            visible: internalField.text.length > 0
                            label: qsTr("Home Wi‑Fi SSID")
                            placeholderText: wifi.ssid.length > 0 ? wifi.ssid : "MyHomeWifi"
                            text: hassClient.homeWifiSsid
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            Component.onCompleted: page.ssidField = ssidField
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: internalField.text.length > 0
                            text: qsTr("Use current Wi‑Fi")
                            enabled: wifi.ssid.length > 0
                            onClicked: ssidField.text = wifi.ssid
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: internalField.text.length > 0
                            text: wifi.ssid.length > 0
                                  ? qsTr("Current Wi‑Fi: %1%2").arg(wifi.ssid).arg(
                                        hassClient.usingInternalUrl
                                        ? qsTr(" · using internal")
                                        : qsTr(" · using external"))
                                  : qsTr("Not connected to Wi‑Fi")
                        }

                        TextSwitch {
                            id: ignoreSslSwitch
                            text: qsTr("Ignore certificate errors")
                            checked: hassClient.ignoreSslErrors
                            description: qsTr("Needed for self-signed HTTPS certificates.")
                            Component.onCompleted: page.ignoreSslSwitch = ignoreSslSwitch
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: {
                                if (!hassClient.mobileAppRegistered)
                                    return qsTr("Notifications: registering device with Home Assistant…")
                                if (hassClient.pushConnected)
                                    return qsTr("Notifications: connected as %1").arg(hassClient.deviceName)
                                return qsTr("Notifications: registered, reconnecting…")
                            }
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }

                ExpandingSection {
                    title: qsTr("Interface")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        ValueButton {
                            width: parent.width
                            label: qsTr("Language")
                            value: page.languageNameFor(hassClient ? hassClient.uiLanguage : "")
                            onClicked: pageStack.push(Qt.resolvedUrl("LanguagePickerPage.qml"),
                                                      { hassClient: hassClient })
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: qsTr("System follows your Home Assistant profile language when signed in, otherwise the phone language. Restart Helmsman after changing language.")
                        }

                        TextSwitch {
                            text: qsTr("Native dashboard")
                            automaticCheck: false
                            checked: hassClient.nativeDashboardEnabled
                            description: qsTr("Render your Lovelace dashboard as Silica instead of the Home Assistant web UI. Off by default. Custom cards and energy still open in the web view.")
                            onClicked: hassClient.nativeDashboardEnabled = !checked
                        }

                        ComboBox {
                            id: engineBox
                            width: parent.width
                            label: qsTr("Browser engine")
                            property bool engineReady: false
                            menu: ContextMenu {
                                Repeater {
                                    model: hassClient.availableWebViewEngines
                                    MenuItem { text: modelData.name }
                                }
                            }
                            Component.onCompleted: {
                                page.engineBox = engineBox
                                page.bindEngineCombo()
                            }
                            onCurrentIndexChanged: {
                                if (!engineReady || !hassClient)
                                    return
                                var list = hassClient.availableWebViewEngines
                                if (currentIndex < 0 || currentIndex >= list.length)
                                    return
                                var id = list[currentIndex].id
                                if (id === hassClient.webViewEngine)
                                    return
                                hassClient.webViewEngine = id
                                if (id === hassClient.webViewEngineActive)
                                    return
                                var dlg = pageStack.push(Qt.resolvedUrl("../components/ActionConfirmDialog.qml"), {
                                                             prompt: {
                                                                 "title": qsTr("Restart Helmsman?"),
                                                                 "text": qsTr("Switch the Home Assistant web UI to %1.").arg(page.engineNameFor(id)),
                                                                 "confirmText": qsTr("Restart now"),
                                                                 "dismissText": qsTr("Later")
                                                             }
                                                         })
                                dlg.accepted.connect(function() { hassClient.restartApp() })
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: hassClient.webViewEngine !== hassClient.webViewEngineActive
                                  ? qsTr("Restart Helmsman to apply the selected engine.")
                                  : qsTr("Used for the Home Assistant web UI. ESR153 appears when sailfish-browser-next153 is installed; Atlantic when Atlantic Browser is installed.")
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }

                ExpandingSection {
                    title: qsTr("Events View and Cover")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: hassClient.widget && hassClient.widget.eventsViewWidgetEnabled
                                  ? qsTr("The Helmsman Events View widget is on, so Home Assistant alerts show there instead of in the system notification list.")
                                  : qsTr("If you enable the Helmsman widget in Settings → Events view, alerts show there instead of in the system notification list.")
                        }

                        TextSwitch {
                            text: qsTr("Show notifications on the app cover")
                            automaticCheck: false
                            checked: hassClient.coverNotificationsEnabled
                            description: qsTr("Tint the cover with the latest Home Assistant alert. Turn this off to keep cover favorites visible.")
                            onClicked: hassClient.coverNotificationsEnabled = !checked
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: qsTr("Pick lights, switches, scripts, ACs, and sensors for the app cover. Tap a light, switch, or AC to toggle it, or a script to run it. Sensors just show their current value and have no cover button.")
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("Choose cover favorites")
                            enabled: hassClient.loggedIn
                            onClicked: pageStack.push(Qt.resolvedUrl("EventsViewSettingsPage.qml"),
                                                      { hassClient: hassClient,
                                                        eventsViewMode: false })
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: qsTr("Pick lights, switches, scripts, ACs, sensors, and graphs for the Events View. Search on the favorites page filters every list. Tap a light, switch, or AC to toggle it, hold a light for brightness/color or an AC for mode, temperature, fan, and vanes, or tap a script for Run and Cancel. Sensors show their current value with the last 24 hours as the card background. Graphs are sensors that already publish a today/tomorrow series, such as Nordpool electricity prices. In Events View favorites, drag a preview card to reorder it, or drop it on the bin to remove it.")
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("Choose Events View favorites")
                            enabled: hassClient.loggedIn
                            onClicked: pageStack.push(Qt.resolvedUrl("EventsViewSettingsPage.qml"),
                                                      { hassClient: hassClient,
                                                        eventsViewMode: true })
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }

                ExpandingSection {
                    title: qsTr("Sensors")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: qsTr("Choose which device sensors Helmsman reports to Home Assistant.")
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: hassClient.sensors && hassClient.sensors.lastError.length > 0
                            text: hassClient.sensors ? qsTr("Last error: %1").arg(hassClient.sensors.lastError) : ""
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: {
                                if (!hassClient.sensors)
                                    return qsTr("Sensors: unavailable")
                                if (!hassClient.mobileAppRegistered)
                                    return qsTr("Sensors: waiting for mobile_app registration…")
                                if (hassClient.sensors.active)
                                    return qsTr("Sensors: reporting")
                                return qsTr("Sensors: idle")
                            }
                        }

                        Repeater {
                            model: hassClient.sensors ? hassClient.sensors.sensorStatuses : []
                            delegate: TextSwitch {
                                width: sections.width
                                visible: modelData.uniqueId !== "location"
                                height: visible ? implicitHeight : 0
                                text: modelData.name
                                checked: modelData.enabled
                                automaticCheck: false
                                description: {
                                    var bits = []
                                    if (modelData.disabled)
                                        bits.push(qsTr("Disabled in Home Assistant"))
                                    if (modelData.state && modelData.state.length)
                                        bits.push(modelData.state)
                                    if (modelData.lastUpdated && modelData.lastUpdated.length)
                                        bits.push(qsTr("updated %1").arg(modelData.lastUpdated))
                                    if (modelData.lastError && modelData.lastError.length)
                                        bits.push(modelData.lastError)
                                    return bits.join(" · ")
                                }
                                onClicked: {
                                    if (hassClient.sensors)
                                        hassClient.sensors.setSensorEnabled(
                                                    modelData.uniqueId, !checked)
                                }
                            }
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("Refresh sensor config")
                            enabled: hassClient.sensors && hassClient.sensors.active
                            onClicked: hassClient.sensors.refreshConfig()
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }

                ExpandingSection {
                    title: qsTr("Location")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        TextSwitch {
                            id: locationEnabledSwitch
                            text: qsTr("Report location")
                            checked: hassClient.sensors
                                     ? hassClient.sensors.locationEnabled : true
                            automaticCheck: false
                            description: hassClient.sensors
                                         && !hassClient.sensors.locationReporting
                                         && hassClient.sensors.locationEnabled
                                         ? qsTr("Location is disabled in Home Assistant.")
                                         : qsTr("Allow Helmsman to update the Home Assistant device tracker.")
                            onClicked: {
                                if (hassClient.sensors)
                                    hassClient.sensors.locationEnabled = !checked
                            }
                        }

                        ComboBox {
                            id: locationPresetBox
                            width: parent.width
                            enabled: locationEnabledSwitch.checked
                            label: qsTr("Location update mode")
                            property bool presetReady: false
                            currentIndex: 1
                            menu: ContextMenu {
                                MenuItem { text: qsTr("Battery saver") }
                                MenuItem { text: qsTr("Balanced") }
                                MenuItem { text: qsTr("Accurate") }
                            }
                            Component.onCompleted: {
                                currentIndex = hassClient.sensors
                                        ? hassClient.sensors.locationPreset : 1
                                presetReady = true
                            }
                            onCurrentIndexChanged: {
                                if (!presetReady || !hassClient.sensors)
                                    return
                                if (hassClient.sensors.locationPreset !== currentIndex)
                                    hassClient.sensors.locationPreset = currentIndex
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: locationEnabledSwitch.checked
                            text: {
                                if (locationPresetBox.currentIndex === 0)
                                    return qsTr("Fewer Home Assistant updates for lower battery use.")
                                if (locationPresetBox.currentIndex === 2)
                                    return qsTr("More frequent Home Assistant updates when a fix is available.")
                                return qsTr("A balance of update speed and battery use. GPS is not kept running.")
                            }
                        }

                        Slider {
                            id: staleSlider
                            width: parent.width
                            enabled: locationEnabledSwitch.checked
                            label: qsTr("Request own location if older than")
                            minimumValue: 5
                            maximumValue: 60
                            stepSize: 5
                            property bool staleReady: false
                            value: 15
                            valueText: qsTr("%1 min").arg(Math.round(value))
                            Component.onCompleted: {
                                if (hassClient.sensors)
                                    value = hassClient.sensors.locationStaleMinutes
                                staleReady = true
                            }
                            onValueChanged: {
                                if (!staleReady || !hassClient.sensors)
                                    return
                                var mins = Math.round(value)
                                if (hassClient.sensors.locationStaleMinutes !== mins)
                                    hassClient.sensors.locationStaleMinutes = mins
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: locationEnabledSwitch.checked
                            text: qsTr("Uses location updates from other apps when they request GPS. Helmsman only turns GPS on itself if the last fix is older than this.")
                        }

                        TextSwitch {
                            visible: page.internalField && page.internalField.text.length > 0
                            enabled: locationEnabledSwitch.checked
                            text: qsTr("Mark home on internal connection")
                            checked: hassClient.sensors ? hassClient.sensors.homeOnInternal : true
                            automaticCheck: false
                            description: qsTr("Report home without using GPS while connected through the internal URL. Helmsman includes the Home zone coordinates so the device shows on the map, and repeats that update so Home Assistant does not time out to away. When disabled, no location is sent on that connection.")
                            onClicked: {
                                if (hassClient.sensors)
                                    hassClient.sensors.homeOnInternal = !checked
                            }
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: hassClient.sensors
                                     && hassClient.sensors.lastLocationText.length > 0
                            text: hassClient.sensors
                                  ? qsTr("Last location: %1").arg(hassClient.sensors.lastLocationText) : ""
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: qsTr("Update location now")
                            enabled: hassClient.sensors && hassClient.sensors.active
                                     && hassClient.sensors.locationReporting
                            onClicked: hassClient.sensors.refreshLocation()
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Save")
                enabled: (page.internalField && page.internalField.text.length > 0)
                         || (page.externalField && page.externalField.text.length > 0)
                onClicked: page.save()
            }

            Item {
                width: 1
                height: Theme.paddingLarge
                visible: hassClient && hassClient.loggedIn
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: hassClient && hassClient.loggedIn
                text: qsTr("Home Assistant settings")
                onClicked: pageStack.push(Qt.resolvedUrl("HassWebViewPage.qml"), {
                                              hassClient: hassClient,
                                              startPath: "/config"
                                          })
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Sign out")
                onClicked: {
                    hassClient.logout()
                    pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: qsTr("App %1").arg(hassClient.appVersion)
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }
        }
    }

    Component.onCompleted: {
        page.activateSections()
        hassClient.refreshWebViewEngines()
        page.bindEngineCombo()
    }
}
