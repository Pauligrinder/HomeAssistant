import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property var hassClient
    property string filterText: ""

    readonly property var allLanguages: hassClient ? hassClient.availableUiLanguages : []
    readonly property var filteredLanguages: {
        var list = page.allLanguages
        var q = page.filterText.trim().toLowerCase()
        if (!q.length)
            return list
        var out = []
        for (var i = 0; i < list.length; ++i) {
            var item = list[i]
            var name = String(item.name || "").toLowerCase()
            var id = String(item.id || "").toLowerCase()
            if (name.indexOf(q) >= 0 || id.indexOf(q) >= 0)
                out.push(item)
        }
        return out
    }

    function pick(id) {
        if (!hassClient)
            return
        if (id === hassClient.uiLanguage) {
            pageStack.pop()
            return
        }
        hassClient.uiLanguage = id
        var dlg = pageStack.replace(page, Qt.resolvedUrl("../components/ActionConfirmDialog.qml"), {
                                        prompt: {
                                            "title": qsTr("Restart Helmsman?"),
                                            "text": qsTr("Apply the selected language."),
                                            "confirmText": qsTr("Restart now"),
                                            "dismissText": qsTr("Later")
                                        }
                                    })
        dlg.accepted.connect(function() { hassClient.restartApp() })
    }

    function currentLanguageName() {
        if (!hassClient)
            return qsTr("System")
        var want = hassClient.uiLanguage
        var list = page.allLanguages
        for (var i = 0; i < list.length; ++i) {
            if (list[i].id === want)
                return list[i].name
        }
        return want.length ? want : qsTr("System")
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: page.filteredLanguages
        currentIndex: -1

        header: Column {
            width: listView.width

            PageHeader { title: qsTr("Language") }

            SearchField {
                width: parent.width
                placeholderText: qsTr("Search languages")
                onTextChanged: page.filterText = text
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: qsTr("System follows your Home Assistant profile language when signed in, otherwise the phone language. Restart Helmsman after changing language.")
            }

            Item {
                width: 1
                height: Theme.paddingMedium
            }
        }

        delegate: BackgroundItem {
            id: row
            width: listView.width
            height: Theme.itemSizeMedium
            highlighted: down || (hassClient && modelData.id === hassClient.uiLanguage)

            onClicked: page.pick(modelData.id)

            Label {
                anchors.left: parent.left
                anchors.right: checkIcon.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.rightMargin: Theme.paddingMedium
                text: modelData.name
                color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }

            Icon {
                id: checkIcon
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                visible: hassClient && modelData.id === hassClient.uiLanguage
                source: "image://theme/icon-m-acknowledge"
                color: Theme.highlightColor
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No matching languages")
        }

        VerticalScrollDecorator {}
    }
}
