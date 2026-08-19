import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property var hassClient
    backNavigation: !hassClient.busy

    function submit() {
        hassClient.submitOtp(codeField.text)
    }

    Connections {
        target: hassClient
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

            PageHeader { title: "Verification" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: hassClient.otpHint.length > 0
                      ? hassClient.otpHint
                      : "Enter the 6-digit code from your authenticator app."
            }

            TextField {
                id: codeField
                width: parent.width
                label: "One-time code"
                placeholderText: "123456"
                inputMethodHints: Qt.ImhDigitsOnly
                echoMode: TextInput.Normal
                EnterKey.enabled: text.length >= 6 && !hassClient.busy
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
                text: hassClient.busy ? "Verifying..." : "Verify"
                enabled: codeField.text.length >= 6 && !hassClient.busy
                onClicked: page.submit()
            }
        }
    }
}
