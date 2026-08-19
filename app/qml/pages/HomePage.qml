import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property var hassClient
    backNavigation: false

    Connections {
        target: hassClient
        onLoggedInChanged: {
            if (!hassClient.loggedIn)
                pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: "Sign out"
                onClicked: hassClient.logout()
            }
        }

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: hassClient.instanceName.length > 0 ? hassClient.instanceName : "Home Assistant"
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                text: "You're signed in"
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Instance: " + hassClient.baseUrl
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                visible: hassClient.haVersion.length > 0
                text: "Home Assistant " + hassClient.haVersion
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                visible: hassClient.username.length > 0
                text: "User: " + hassClient.username
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: "Dashboards and entity control will land here next. Pull down to sign out."
            }

            SectionHeader { text: "About" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: "Native Home Assistant client  ·  app " + hassClient.appVersion
            }
        }
    }
}
