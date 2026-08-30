import QtQuick 2.6
import Sailfish.Silica 1.0
import "../eventsview"

Page {
    id: page
    property var hassClient
    property bool eventsViewMode: false
    property string filterText: ""

    // Bound rather than queried through a function so the switches follow
    // selection changes without waiting for the next state poll.
    readonly property var selectedIds: {
        if (!hassClient.widget)
            return []
        return eventsViewMode
                ? hassClient.widget.eventsViewSelectedEntityIds
                : hassClient.widget.selectedEntityIds
    }

    function setSelected(entityId, selected) {
        if (eventsViewMode)
            hassClient.widget.setEventsViewEntitySelected(entityId, selected)
        else
            hassClient.widget.setEntitySelected(entityId, selected)
    }

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

            PageHeader {
                title: page.eventsViewMode
                       ? "Events View favorites"
                       : "Cover favorites"
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.eventsViewMode
                      ? "Choose lights to show in the Events View. Each light gets its own card there; tap a card to toggle it, or hold a dimmable light to set its brightness."
                      : "Choose lights to show on the app cover. If there are more than fit, use the cover arrows to change page. Tap a light on the cover to toggle it."
            }

            SectionHeader { text: "Preview" }

            EventsViewWidget {
                width: parent.width
                entities: !hassClient.widget
                          ? []
                          : (page.eventsViewMode
                             ? hassClient.widget.eventsViewWidgetEntities
                             : hassClient.widget.widgetEntities)
                statusText: {
                    if (!hassClient.loggedIn)
                        return "Sign in to Home Assistant first."
                    if (!hassClient.widget)
                        return "Widget unavailable."
                    if (hassClient.widget && hassClient.widget.lastError.length > 0)
                        return hassClient.widget.lastError
                    var entities = page.eventsViewMode
                            ? hassClient.widget.eventsViewWidgetEntities
                            : hassClient.widget.widgetEntities
                    if (hassClient.widget && entities.length === 0)
                        return "No lights selected yet."
                    return ""
                }
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
                    checked: page.selectedIds.indexOf(modelData.entityId) >= 0
                    automaticCheck: false
                    onClicked: page.setSelected(modelData.entityId, !checked)
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
