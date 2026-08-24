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

            TextField {
                id: ssidField
                width: parent.width
                label: "Home Wi‑Fi SSID"
                placeholderText: wifi.ssid.length > 0 ? wifi.ssid : "MyHomeWifi"
                text: hassClient.homeWifiSsid
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
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
