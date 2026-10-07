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
        return id && id.length ? id : i18n.translation("system")
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
                        ? i18n.translation("internal").arg(message)
                        : i18n.translation("internal_failed").arg(message)
            } else if (endpoint === page.externalField.text) {
                externalTestResult = success
                        ? i18n.translation("external").arg(message)
                        : i18n.translation("external_failed").arg(message)
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

            PageHeader { title: i18n.translation("helmsman_settings") }

            ExpandingSectionGroup {
                id: sections
                width: parent.width
                currentIndex: 0

                ExpandingSection {
                    id: connectionSection
                    title: i18n.translation("connection")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: i18n.translation("url_format_help")
                        }

                        TextField {
                            id: internalField
                            width: parent.width
                            label: i18n.translation("internal_url")
                            placeholderText: "http://homeassistant.local"
                            text: hassClient.internalUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
                            Component.onCompleted: page.internalField = internalField
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.pendingTestUrl === internalField.text
                                  ? i18n.translation("testing_internal") : i18n.translation("test_internal")
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
                            label: i18n.translation("external_url")
                            placeholderText: "https://example.ui.nabu.casa"
                            text: hassClient.externalUrl
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
                            Component.onCompleted: page.externalField = externalField
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.pendingTestUrl === externalField.text
                                  ? i18n.translation("testing_external") : i18n.translation("test_external")
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
                            text: i18n.translation("single_address_help")
                        }

                        TextField {
                            id: ssidField
                            width: parent.width
                            visible: internalField.text.length > 0
                            label: i18n.translation("home_wi_fi_ssid")
                            placeholderText: wifi.ssid.length > 0 ? wifi.ssid : "MyHomeWifi"
                            text: hassClient.homeWifiSsid
                            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                            Component.onCompleted: page.ssidField = ssidField
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: internalField.text.length > 0
                            text: i18n.translation("use_current_wi_fi")
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
                                  ? i18n.translation("current_wi_fi").arg(wifi.ssid).arg(
                                        hassClient.usingInternalUrl
                                        ? i18n.translation("using_internal")
                                        : i18n.translation("using_external"))
                                  : i18n.translation("not_connected_to_wi_fi")
                        }

                        TextSwitch {
                            id: ignoreSslSwitch
                            text: i18n.translation("ignore_certificate_errors")
                            checked: hassClient.ignoreSslErrors
                            description: i18n.translation("ignore_certificate_help")
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
                                    return i18n.translation("notifications_registering")
                                if (hassClient.pushConnected)
                                    return i18n.translation("notifications_connected_as").arg(hassClient.deviceName)
                                return i18n.translation("notifications_reconnecting")
                            }
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }

                ExpandingSection {
                    title: i18n.translation("interface")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        ValueButton {
                            width: parent.width
                            label: i18n.translation("language")
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
                            text: i18n.translation("language_follows_system")
                        }

                        TextSwitch {
                            text: i18n.translation("native_dashboard")
                            automaticCheck: false
                            checked: hassClient.nativeDashboardEnabled
                            description: i18n.translation("native_dashboard_help")
                            onClicked: hassClient.nativeDashboardEnabled = !checked
                        }

                        ComboBox {
                            id: engineBox
                            width: parent.width
                            label: i18n.translation("browser_engine")
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
                                                                 "title": i18n.translation("restart_helmsman"),
                                                                 "text": i18n.translation("switch_the_home_assistant_web_ui_to").arg(page.engineNameFor(id)),
                                                                 "confirmText": i18n.translation("restart_now"),
                                                                 "dismissText": i18n.translation("later")
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
                                  ? i18n.translation("restart_for_engine")
                                  : i18n.translation("webview_engine_help")
                        }
                        Item {
                            width: 1
                            height: Theme.paddingLarge
                        }
                    }
                }

                ExpandingSection {
                    title: i18n.translation("events_view_and_cover")

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
                                  ? i18n.translation("events_widget_on_help")
                                  : i18n.translation("events_widget_off_help")
                        }

                        TextSwitch {
                            text: i18n.translation("show_notifications_on_the_app_cover")
                            automaticCheck: false
                            checked: hassClient.coverNotificationsEnabled
                            description: i18n.translation("cover_notifications_help")
                            onClicked: hassClient.coverNotificationsEnabled = !checked
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: i18n.translation("select_cover_entities")
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: i18n.translation("manage_app_cover_entities")
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
                            text: i18n.translation("select_events_view_entities_settings")
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: i18n.translation("manage_events_view_entities")
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
                    title: i18n.translation("sensors")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            text: i18n.translation("choose_sensors_help")
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: hassClient.sensors && hassClient.sensors.lastError.length > 0
                            text: hassClient.sensors ? i18n.translation("last_error").arg(hassClient.sensors.lastError) : ""
                        }

                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * x
                            wrapMode: Text.Wrap
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            text: {
                                if (!hassClient.sensors)
                                    return i18n.translation("sensors_unavailable")
                                if (!hassClient.mobileAppRegistered)
                                    return i18n.translation("sensors_waiting")
                                if (hassClient.sensors.active)
                                    return i18n.translation("sensors_reporting")
                                return i18n.translation("sensors_idle")
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
                                        bits.push(i18n.translation("disabled_in_home_assistant"))
                                    if (modelData.state && modelData.state.length)
                                        bits.push(modelData.state)
                                    if (modelData.lastUpdated && modelData.lastUpdated.length)
                                        bits.push(i18n.translation("updated").arg(modelData.lastUpdated))
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
                            text: i18n.translation("refresh_sensor_config")
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
                    title: i18n.translation("location")

                    content.sourceComponent: Column {
                        width: sections.width
                        spacing: Theme.paddingMedium

                        TextSwitch {
                            id: locationEnabledSwitch
                            text: i18n.translation("report_location")
                            checked: hassClient.sensors
                                     ? hassClient.sensors.locationEnabled : true
                            automaticCheck: false
                            description: hassClient.sensors
                                         && !hassClient.sensors.locationReporting
                                         && hassClient.sensors.locationEnabled
                                         ? i18n.translation("location_disabled")
                                         : i18n.translation("report_location_help")
                            onClicked: {
                                if (hassClient.sensors)
                                    hassClient.sensors.locationEnabled = !checked
                            }
                        }

                        ComboBox {
                            id: locationPresetBox
                            width: parent.width
                            enabled: locationEnabledSwitch.checked
                            label: i18n.translation("location_update_mode")
                            property bool presetReady: false
                            currentIndex: 1
                            menu: ContextMenu {
                                MenuItem { text: i18n.translation("battery_saver") }
                                MenuItem { text: i18n.translation("balanced") }
                                MenuItem { text: i18n.translation("accurate") }
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
                                    return i18n.translation("location_mode_saver")
                                if (locationPresetBox.currentIndex === 2)
                                    return i18n.translation("location_mode_accurate")
                                return i18n.translation("location_mode_balanced")
                            }
                        }

                        Slider {
                            id: staleSlider
                            width: parent.width
                            enabled: locationEnabledSwitch.checked
                            label: i18n.translation("get_a_location_fix_if_older_than")
                            minimumValue: 5
                            maximumValue: 60
                            stepSize: 5
                            property bool staleReady: false
                            value: 15
                            valueText: i18n.translation("min").arg(Math.round(value))
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
                            text: i18n.translation("location_fix_help")
                        }

                        TextSwitch {
                            visible: page.internalField && page.internalField.text.length > 0
                            enabled: locationEnabledSwitch.checked
                            text: i18n.translation("mark_home_on_internal_connection")
                            checked: hassClient.sensors ? hassClient.sensors.homeOnInternal : true
                            automaticCheck: false
                            description: i18n.translation("home_on_internal_help")
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
                                  ? i18n.translation("last_location").arg(hassClient.sensors.lastLocationText) : ""
                        }

                        Button {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: i18n.translation("update_location_now")
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
                text: i18n.translation("save")
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
                text: i18n.translation("home_assistant_settings")
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
                text: i18n.translation("sign_out")
                onClicked: {
                    hassClient.logout()
                    pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: i18n.translation("app").arg(hassClient.appVersion)
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
