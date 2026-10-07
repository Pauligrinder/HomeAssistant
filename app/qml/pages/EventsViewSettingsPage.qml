import QtQuick 2.6
import Sailfish.Silica 1.0
import "../eventsview"

Page {
    id: page
    objectName: eventsViewMode ? "EventsViewFavoritesPage" : "CoverFavoritesPage"
    property var hassClient
    property bool eventsViewMode: false
    property string filterText: ""
    readonly property int sensorSearchLimit: 40

    function kindOf(entity) {
        return (entity && entity.kind) ? entity.kind : "light"
    }

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
            var haystack = ((entity.name || "") + " " + (entity.entityId || "")
                            + " " + page.kindOf(entity)).toLowerCase()
            if (haystack.indexOf(needle) >= 0)
                out.push(entity)
        }
        return out
    }

    function entitiesOfKind(kind) {
        var all = page.filteredEntities
        var out = []
        for (var i = 0; i < all.length; ++i) {
            if (page.kindOf(all[i]) === kind)
                out.push(all[i])
        }
        return out
    }

    readonly property bool hasPickableEntities: {
        var kinds = ["light", "switch", "climate", "script", "sensor"]
        if (page.eventsViewMode)
            kinds.push("graph")
        for (var i = 0; i < kinds.length; ++i) {
            if (page.entitiesOfKind(kinds[i]).length > 0)
                return true
        }
        return false
    }

    readonly property int unfilteredSensorCount: {
        if (!hassClient.widget)
            return 0
        var all = hassClient.widget.availableEntities || []
        var n = 0
        for (var i = 0; i < all.length; ++i) {
            if (page.kindOf(all[i]) === "sensor")
                n++
        }
        return n
    }

    readonly property bool sensorListGated: {
        var matches = page.entitiesOfKind("sensor").length
        if (page.filterText.length === 0)
            return page.unfilteredSensorCount > page.sensorSearchLimit
        return matches > page.sensorSearchLimit
    }

    onStatusChanged: {
        if (status === PageStatus.Active && hassClient.widget)
            hassClient.widget.refreshAvailable()
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        anchors.bottomMargin: trashBin.visible ? trashBin.height : 0
        contentHeight: column.height + Theme.paddingLarge
        interactive: !preview.dragging

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: page.eventsViewMode
                       ? i18n.translation("events_view_favorites")
                       : i18n.translation("cover_favorites")
            }

            SearchField {
                id: searchField
                width: parent.width
                placeholderText: i18n.translation("search_name_or_entity_id")
                onTextChanged: page.filterText = text
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                visible: page.filterText.length > 0
                text: page.filteredEntities.length === 1
                      ? "1 match"
                      : (page.filteredEntities.length + " matches")
            }

            Label {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.eventsViewMode
                      ? i18n.translation("select_events_view_entities")
                      : i18n.translation("select_cover_entities")
            }

            SectionHeader { text: i18n.translation("preview") }

            EventsViewWidget {
                id: preview
                width: parent.width
                reorderEnabled: page.eventsViewMode
                trashItem: trashBin
                coordinateItem: page
                entities: !hassClient.widget
                          ? []
                          : (page.eventsViewMode
                             ? hassClient.widget.eventsViewWidgetEntities
                             : hassClient.widget.widgetEntities)
                statusText: {
                    if (!hassClient.loggedIn)
                        return i18n.translation("sign_in_to_home_assistant_first")
                    if (!hassClient.widget)
                        return i18n.translation("widget_unavailable_sentence")
                    if (hassClient.widget && hassClient.widget.lastError.length > 0)
                        return hassClient.widget.lastError
                    var entities = page.eventsViewMode
                            ? hassClient.widget.eventsViewWidgetEntities
                            : hassClient.widget.widgetEntities
                    if (hassClient.widget && entities.length === 0)
                        return i18n.translation("nothing_selected_yet")
                    return ""
                }
                onReorderRequested: {
                    if (hassClient.widget)
                        hassClient.widget.reorderEventsViewEntity(entityId, newIndex)
                }
                onRemoveRequested: {
                    if (hassClient.widget)
                        hassClient.widget.setEventsViewEntitySelected(entityId, false)
                }
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
                      ? i18n.translation("loading")
                      : (page.filterText.length > 0
                         ? i18n.translation("no_matching_entities")
                         : (page.eventsViewMode
                            ? i18n.translation("no_entities_with_graphs")
                            : i18n.translation("no_entities")))
            }

            Repeater {
                model: {
                    var items = [
                        { "title": i18n.translation("lights"), "kind": "light" },
                        { "title": i18n.translation("switches"), "kind": "switch" },
                        { "title": i18n.translation("air_conditioners"), "kind": "climate" },
                        { "title": i18n.translation("scripts"), "kind": "script" }
                    ]
                    if (page.eventsViewMode)
                        items.push({ "title": i18n.translation("graphs"), "kind": "graph" })
                    items.push({ "title": i18n.translation("sensors"), "kind": "sensor" })
                    return items
                }
                delegate: Column {
                    id: kindGroup
                    width: column.width
                    property string kindTitle: modelData.title
                    property string entityKind: modelData.kind
                    visible: (kindGroup.entityKind === "sensor" && page.sensorListGated)
                             || page.entitiesOfKind(kindGroup.entityKind).length > 0

                    SectionHeader { text: kindGroup.kindTitle }

                    Label {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.horizontalPageMargin
                        wrapMode: Text.Wrap
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        visible: kindGroup.entityKind === "sensor" && page.sensorListGated
                        text: page.filterText.length > 0
                              ? i18n.translation("too_many_sensors")
                                    .arg(page.entitiesOfKind("sensor").length)
                              : i18n.translation("search_to_find_sensors")
                                    .arg(page.unfilteredSensorCount)
                    }

                    Repeater {
                        model: (kindGroup.entityKind === "sensor" && page.sensorListGated)
                               ? []
                               : page.entitiesOfKind(kindGroup.entityKind)
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

    Item {
        id: trashBin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: page.eventsViewMode
                 && ((page.selectedIds && page.selectedIds.length > 0) || preview.dragging)
        height: visible ? (preview.dragging ? Theme.itemSizeLarge : Theme.itemSizeMedium) : 0
        z: 50

        Rectangle {
            anchors.fill: parent
            color: Theme.highlightDimmerColor
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * Theme.horizontalPageMargin,
                            preview.dragging ? Theme.itemSizeLarge * 2.2
                                             : Theme.itemSizeLarge * 1.6)
            height: preview.dragging ? Theme.itemSizeMedium : Theme.itemSizeSmall
            radius: height / 2
            color: preview.dragOverTrash ? "#C62828" : "#40FFFFFF"

            Row {
                anchors.centerIn: parent
                spacing: Theme.paddingSmall

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-delete"
                    sourceSize.width: Theme.iconSizeSmall
                    sourceSize.height: Theme.iconSizeSmall
                    opacity: 0.9
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: preview.dragging
                    color: Theme.primaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    text: preview.dragOverTrash ? i18n.translation("release_to_remove") : i18n.translation("drop_here_to_remove")
                }
            }
        }
    }
}
