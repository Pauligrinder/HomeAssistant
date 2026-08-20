import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property var hassClient
    property bool hasSavedSession: hassClient.refreshToken.length > 0

    function connectClicked() {
        hassClient.connectToInstance(hostField.text, sslSwitch.checked, ignoreSslSwitch.checked)
    }

    function primaryClicked() {
        if (page.hasSavedSession)
            hassClient.restoreSession()
        else
            page.connectClicked()
    }

    Connections {
        target: hassClient
        onConnectionSucceeded: {
            if (!hassClient.loggedIn)
                pageStack.push(Qt.resolvedUrl("LoginPage.qml"), { hassClient: hassClient })
        }
        onRestoreFinished: {
            if (loggedIn)
                pageStack.replaceAbove(null, Qt.resolvedUrl("HomePage.qml"), { hassClient: hassClient })
        }
        onLoginSucceeded: {
            pageStack.replaceAbove(null, Qt.resolvedUrl("HomePage.qml"), { hassClient: hassClient })
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
                      ? "A saved session was found for this instance. Retry restore, or connect again to sign in fresh."
                      : "Enter the IP address or hostname of your Home Assistant instance."
            }

            TextField {
                id: hostField
                width: parent.width
                label: "IP or hostname"
                placeholderText: "homeassistant.local:8123"
                text: {
                    if (!hassClient.host.length)
                        return ""
                    var value = hassClient.host
                    if (hassClient.port > 0)
                        value += ":" + hassClient.port
                    return value
                }
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
                EnterKey.enabled: text.length > 0 && !hassClient.busy && !hassClient.restoringSession
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.primaryClicked()
            }

            TextSwitch {
                id: sslSwitch
                text: "Use HTTPS"
                checked: hassClient.useSsl
                description: "Turn on if the instance is served over TLS. Port still defaults to 8123 unless you specify one."
            }

            TextSwitch {
                id: ignoreSslSwitch
                text: "Ignore certificate errors"
                checked: hassClient.ignoreSslErrors
                visible: sslSwitch.checked
                description: "Needed for self-signed certificates."
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
                enabled: hostField.text.length > 0 && !hassClient.busy && !hassClient.restoringSession
                onClicked: page.primaryClicked()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Sign in again"
                visible: page.hasSavedSession
                enabled: hostField.text.length > 0 && !hassClient.busy && !hassClient.restoringSession
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
