import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property var hassClient

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
        onSsidChanged: {
            if (ssidField.text.length === 0 && wifi.ssid.length > 0)
                ssidField.placeholderText = wifi.ssid
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
                placeholderText: "http://homeassistant.local:8123"
                text: hassClient.internalUrl
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
            }

            TextField {
                id: externalField
                width: parent.width
                label: "External URL"
                placeholderText: "https://example.ui.nabu.casa"
                text: hassClient.externalUrl
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
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
