import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property var hassClient

    function submit() {
        hassClient.login(usernameField.text, passwordField.text)
    }

    Connections {
        target: hassClient
        onOtpRequired: {
            pageStack.push(Qt.resolvedUrl("OtpPage.qml"), { hassClient: hassClient })
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

            PageHeader { title: "Sign in" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Sign in to " + hassClient.baseUrl + " with a Home Assistant user."
            }

            TextField {
                id: usernameField
                width: parent.width
                label: "Username"
                placeholderText: "Username"
                text: hassClient.username
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordField.forceActiveFocus()
            }

            PasswordField {
                id: passwordField
                width: parent.width
                label: "Password"
                placeholderText: "Password"
                EnterKey.enabled: usernameField.text.length > 0 && text.length > 0 && !hassClient.busy
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: page.submit()
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

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: hassClient.busy
                visible: running
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hassClient.busy ? "Signing in..." : "Sign in"
                enabled: usernameField.text.length > 0 && passwordField.text.length > 0 && !hassClient.busy
                onClicked: page.submit()
            }
        }
    }
}
