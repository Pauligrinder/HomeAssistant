import QtQuick 2.6
import Sailfish.Silica 1.0
import "../eventsview"

Page {
    id: page
    objectName: eventsViewMode ? "EventsViewFavoritesPage" : "CoverFavoritesPage"
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

    readonly property var filteredEntities: {
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

    function entitiesOfKind(kind) {
        var all = page.filteredEntities
        var out = []
        for (var i = 0; i < all.length; ++i) {
            if ((all[i].kind || "light") === kind)
                out.push(all[i])
        }
        return out
    }

    readonly property bool hasPickableEntities: {
        var kinds = ["light", "switch", "climate", "script"]
        if (page.eventsViewMode)
            kinds.push("graph", "sensor")
        for (var i = 0; i < kinds.length; ++i) {
            if (page.entitiesOfKind(kinds[i]).length > 0)
                return true
        }
        return false
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
                      ? "Choose lights, switches, scripts, ACs, sensors, and graphs for the Events View. Tap a light, switch, or AC to toggle it, hold a light for brightness/color or an AC for mode, temperature, fan, and vanes, or tap a script for Run and Cancel. Sensors show their current value with the last 24 hours as the card background. Graphs are sensors that already publish a today/tomorrow series, such as Nordpool electricity prices. Drag a card to reorder it, or drop it on the bin to remove it."
                      : "Choose lights, switches, scripts, and ACs for the app cover. If there are more than fit, use the cover arrows to change page. Tap a light, switch, or AC to toggle it, or a script to run it."
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
                        return "Nothing selected yet."
                    return ""
                }
            }

            SearchField {
                id: searchField
                width: parent.width
                placeholderText: "Filter"
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
                visible: !page.hasPickableEntities
                         && !(hassClient.widget && hassClient.widget.lastError.length > 0)
                text: hassClient.widget && hassClient.widget.busy
                      ? "Loading…"
                      : (page.eventsViewMode
                         ? "No lights, switches, scripts, ACs, sensors, or graphs found."
                         : "No lights, switches, scripts, or ACs found.")
            }

            Repeater {
                model: {
                    var items = [
                        { "title": "Lights", "kind": "light" },
                        { "title": "Switches", "kind": "switch" },
                        { "title": "Air conditioners", "kind": "climate" },
                        { "title": "Scripts", "kind": "script" }
                    ]
                    if (page.eventsViewMode) {
                        items.push({ "title": "Graphs", "kind": "graph" })
                        items.push({ "title": "Sensors", "kind": "sensor" })
                    }
                    return items
                }
                delegate: Column {
                    id: kindGroup
                    width: column.width
                    property string kindTitle: modelData.title
                    property string entityKind: modelData.kind
                    visible: page.entitiesOfKind(kindGroup.entityKind).length > 0

                    SectionHeader { text: kindGroup.kindTitle }

                    Repeater {
                        model: page.entitiesOfKind(kindGroup.entityKind)
                        delegate: TextSwitch {
                            width: column.width
                            text: modelData.name
                            description: {
                                var bits = [modelData.entityId]
                                if (modelData.kind === "graph" || modelData.kind === "sensor") {
                                    var unit = modelData.graphUnit || ""
                                    if (modelData.graphNow !== undefined && modelData.graphNow !== null
                                            && modelData.graphNow !== "")
                                        bits.push(String(modelData.graphNow) + (unit ? " " + unit : ""))
                                    else if (unit)
                                        bits.push(unit)
                                }
                                if (modelData.dimmable)
                                    bits.push("dimmable")
                                if (modelData.available === false)
                                    bits.push("unavailable")
                                return bits.join(" · ")
                            }
                            checked: page.selectedIds.indexOf(modelData.entityId) >= 0
                            automaticCheck: false
                            onClicked: page.setSelected(modelData.entityId, !checked)
                        }
                    }
                }
            }

            Item { width: 1; height: Theme.paddingLarge }
        }
    }
}
