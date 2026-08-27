import QtQuick 2.6
import Sailfish.Silica 1.0
import "../eventsview"

Page {
    id: page
    property var hassClient
    property string filterText: ""

    readonly property var filteredLights: {
        var all = hassClient.widget ? hassClient.widget.availableEntities : []
        var needle = page.filterText.toLowerCase()
        var out = []
        for (var i = 0; i < all.length; ++i) {
            var entity = all[i]
            if (!needle.length) {
                out.push(entity)
                continue
            }
            var haystack = ((entity.name || "") + " " + (entity.entityId || "")).toLowerCase()
            if (haystack.indexOf(needle) >= 0)
                out.push(entity)
        }
        return out
    }

    onStatusChanged: {
        if (status === PageStatus.Active && hassClient.widget)
            hassClient.widget.refreshAvailable()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width

            PageHeader { title: "Cover favorites" }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: "Choose lights to show on the app cover. If there are more than fit, use the cover arrows to change page. Dimmable lights get a brightness slider here. Other entity types (including graphs) can be added later."
            }

            SectionHeader { text: "Preview" }

            EventsViewWidget {
                width: parent.width
                entities: hassClient.widget ? hassClient.widget.widgetEntities : []
                statusText: {
                    if (!hassClient.loggedIn)
                        return "Sign in to Home Assistant first."
                    if (hassClient.widget && hassClient.widget.lastError.length > 0)
                        return hassClient.widget.lastError
                    if (hassClient.widget && hassClient.widget.widgetEntities.length === 0)
                        return "No lights selected yet."
                    return ""
                }
                onToggleRequested: hassClient.widget.toggleLight(entityId)
                onBrightnessRequested: hassClient.widget.setBrightnessPct(entityId, pct)
            }

            SectionHeader { text: "Lights" }

            SearchField {
                id: searchField
                width: parent.width
                placeholderText: "Filter lights"
                onTextChanged: page.filterText = text
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: hassClient.widget && hassClient.widget.lastError.length > 0
                text: hassClient.widget ? hassClient.widget.lastError : ""
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                visible: (!hassClient.widget || hassClient.widget.availableEntities.length === 0)
                         && !(hassClient.widget && hassClient.widget.lastError.length > 0)
                text: hassClient.widget && hassClient.widget.busy
                      ? "Loading lights…"
                      : "No light entities found."
            }

            Repeater {
                model: page.filteredLights
                delegate: TextSwitch {
                    width: column.width
                    text: modelData.name
                    description: modelData.entityId
                                 + (modelData.dimmable ? " · dimmable" : "")
                                 + (modelData.available === false ? " · unavailable" : "")
                    checked: modelData.selected === true
                    automaticCheck: false
                    onClicked: hassClient.widget.setEntitySelected(modelData.entityId, !checked)
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
