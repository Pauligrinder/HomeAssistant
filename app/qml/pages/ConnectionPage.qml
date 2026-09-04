import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

Page {
    id: page
    property var hassClient
    property bool hasSavedSession: hassClient.refreshToken.length > 0
    property bool hasConfiguredUrls: hassClient.internalUrl.length > 0
                                   || hassClient.externalUrl.length > 0

    function prepareEndpoint() {
        hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
        hassClient.applyEndpointNow()
    }

    function connectClicked() {
        page.prepareEndpoint()
        hassClient.connectToConfiguredInstance()
    }

    function restoreClicked() {
        page.prepareEndpoint()
        hassClient.restoreSession()
    }

    WifiChecker {
        id: wifi
        onNetworkChanged: hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
    }

    Connections {
        target: hassClient
        onConnectionSucceeded: {
            if (!hassClient.loggedIn)
                pageStack.push(Qt.resolvedUrl("LoginPage.qml"), { hassClient: hassClient })
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

            PageHeader { title: "Home Assistant" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.hasSavedSession
                      ? "A saved session was found. Retry restore, or sign in again on the configured address."
                      : "Configure your Home Assistant addresses, then connect to sign in."
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: {
                    if (!page.hasConfiguredUrls)
                        return "No addresses configured yet."
                    var lines = []
                    if (hassClient.internalUrl.length > 0)
                        lines.push("Internal: " + hassClient.internalUrl)
                    if (hassClient.externalUrl.length > 0)
                        lines.push("External: " + hassClient.externalUrl)
                    if (hassClient.baseUrl.length > 0) {
                        var using = "Using: " + hassClient.baseUrl
                        if (hassClient.internalUrl.length > 0)
                            using += hassClient.usingInternalUrl ? " (internal)" : " (external)"
                        lines.push(using)
                    }
                    return lines.join("\n")
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Edit addresses"
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"),
                                          { hassClient: hassClient })
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: hassClient.errorMessage.length > 0
                text: hassClient.errorMessage
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: hassClient.statusText
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: hassClient.restoringSession
                text: "Restoring saved session..."
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: hassClient.busy || hassClient.restoringSession
                visible: running
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (hassClient.restoringSession)
                        return "Restoring..."
                    if (page.hasSavedSession)
                        return "Retry restore"
                    return hassClient.busy ? "Connecting..." : "Connect"
                }
                enabled: page.hasConfiguredUrls
                         && !hassClient.busy
                         && !hassClient.restoringSession
                onClicked: page.hasSavedSession ? page.restoreClicked() : page.connectClicked()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sign in again"
                visible: page.hasSavedSession
                enabled: page.hasConfiguredUrls
                         && !hassClient.busy
                         && !hassClient.restoringSession
                onClicked: page.connectClicked()
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
