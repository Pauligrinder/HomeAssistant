import QtQuick 2.6
import Sailfish.Silica 1.0

Loader {
    id: loader
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    property int topContentInset: 0
    property int rowHeight: 0
    property int columns: 12
    property int unitWidth: parent ? parent.width : width
    readonly property int rowUnit: Theme.itemSizeSmall
    readonly property int minHeight: {
        // Grid square: true forces each cell to match its computed width.
        if (card && card._square)
            return Math.round(loader.width)
        var rows = (card && card._rows) ? Number(card._rows) : 0
        if (rows <= 0)
            return 0
        return Math.round(rows * loader.rowUnit + Math.max(0, rows - 1) * Theme.paddingMedium)
    }
    readonly property int contentHeight: item && item.implicitHeight ? item.implicitHeight : 0
    readonly property int naturalHeight: Math.max(loader.contentHeight, loader.minHeight)
    readonly property int statesRevision: dashboard ? dashboard.statesRevision : 0
    readonly property bool cardIsVisible: !dashboard || !card
                                                   || (statesRevision >= 0
                                                       && dashboard.cardVisible(card))

    readonly property url cardSource: loader.sourceForType(card ? card.type : "")
    property bool sourceReady: false

    visible: cardIsVisible
    height: {
        // Force a true square cell; do not let taller content stretch the row.
        if (card && card._square)
            return Math.round(loader.width)
        return Math.max(loader.naturalHeight, loader.rowHeight, loader.fillHeight)
    }
    width: {
        var cols = (card && card._columns) ? card._columns : 12
        var span = Math.min(loader.columns, Math.max(1, cols))
        var gap = Theme.paddingMedium
        var unit = (loader.unitWidth - gap * (loader.columns - 1)) / loader.columns
        var computed = span * unit + Math.max(0, span - 1) * gap
        // itemSizeSmall is only a placeholder before unitWidth is known.
        // Do not inflate cells past their span or a 3-column row can overflow.
        if (!isFinite(computed) || computed <= 0)
            return Theme.itemSizeSmall
        return computed
    }

    // Cards read card and dashboard in their own Component.onCompleted, which
    // runs before onLoaded, so the context has to arrive as initial properties.
    // Binding source instead would leave those handlers with undefined values.
    function loadCard() {
        if (!loader.sourceReady)
            return
        var fill = Math.max(loader.fillHeight, loader.rowHeight)
        if (card && card._square)
            fill = Math.round(loader.width)
        loader.setSource(loader.cardSource, {
                             "card": loader.card,
                             "dashboard": loader.dashboard,
                             "hassClient": loader.hassClient,
                             "mdiIcons": loader.mdiIcons,
                             "fillHeight": fill,
                             "topContentInset": loader.topContentInset,
                             "minContentHeight": loader.minHeight
                         })
    }

    onCardSourceChanged: loader.loadCard()

    Component.onCompleted: {
        loader.sourceReady = true
        loader.loadCard()
    }

    onLoaded: {
        if (!item)
            return
        item.card = Qt.binding(function() { return loader.card })
        item.dashboard = Qt.binding(function() { return loader.dashboard })
        item.hassClient = Qt.binding(function() { return loader.hassClient })
        item.mdiIcons = Qt.binding(function() { return loader.mdiIcons })
        item.width = Qt.binding(function() { return loader.width })
        item.fillHeight = Qt.binding(function() {
            if (loader.card && loader.card._square)
                return Math.round(loader.width)
            return Math.max(loader.fillHeight, loader.rowHeight)
        })
        if (item.topContentInset !== undefined)
            item.topContentInset = Qt.binding(function() { return loader.topContentInset })
        if (item.minContentHeight !== undefined)
            item.minContentHeight = Qt.binding(function() { return loader.minHeight })
    }

    // layout-card and similar custom containers: render nested cards instead of
    // a dead "unsupported" stub. Word hints pick orientation when possible.
    function sourceForContainer(type) {
        var t = String(type || "").toLowerCase()
        var nested = loader.card && loader.card.cards
        if (!nested || !nested.length)
            return ""
        if (t.indexOf("horizontal") >= 0)
            return Qt.resolvedUrl("cards/HorizontalStackCard.qml")
        if (t.indexOf("grid") >= 0)
            return Qt.resolvedUrl("cards/GridCard.qml")
        // vertical-layout, masonry-layout, and any other cards[] container
        return Qt.resolvedUrl("cards/VerticalStackCard.qml")
    }

    function sourceForType(type) {
        var t = String(type || "")
        if (t === "custom:person-status-card" || t === "custom:person-info-card")
            return Qt.resolvedUrl("cards/PersonStatusCard.qml")
        if (t === "custom:custom-calendar-card")
            return Qt.resolvedUrl("cards/CustomCalendarCard.qml")
        if (t === "custom:apexcharts-card")
            return Qt.resolvedUrl("cards/ApexChartsCard.qml")
        if (t === "custom:horizon-card")
            return Qt.resolvedUrl("cards/HorizonCard.qml")
        if (t === "custom:auto-entities")
            return Qt.resolvedUrl("cards/AutoEntitiesCard.qml")
        if (t === "custom:mushroom-title-card")
            return Qt.resolvedUrl("cards/MushroomTitleCard.qml")
        if (t === "custom:mushroom-light-card")
            return Qt.resolvedUrl("cards/MushroomLightCard.qml")
        if (t === "custom:collapsable-cards" || t === "custom:expander-card")
            return Qt.resolvedUrl("cards/CollapsableCards.qml")
        if (t === "custom:button-card") {
            var ct = loader.card && loader.card.color_type
                     ? String(loader.card.color_type) : ""
            if (ct === "blank-card" || ct === "label-card")
                return Qt.resolvedUrl("cards/BlankCard.qml")
            // Simple entity button-card → core button renderer.
            if (loader.card && loader.card.entity)
                return Qt.resolvedUrl("cards/ButtonCard.qml")
            return Qt.resolvedUrl("cards/FallbackCard.qml")
        }
        var container = loader.sourceForContainer(t)
        if (container !== "")
            return container
        if (t.indexOf("custom:") === 0)
            return Qt.resolvedUrl("cards/FallbackCard.qml")
        if (t.indexOf("energy-") === 0 || t === "energy")
            return Qt.resolvedUrl("cards/EnergyCard.qml")
        switch (t) {
        case "tile": return Qt.resolvedUrl("cards/TileCard.qml")
        case "entities": return Qt.resolvedUrl("cards/EntitiesCard.qml")
        case "glance": return Qt.resolvedUrl("cards/GlanceCard.qml")
        case "heading": return Qt.resolvedUrl("cards/HeadingCard.qml")
        case "entity": return Qt.resolvedUrl("cards/EntityCard.qml")
        case "button":
        case "shortcut": return Qt.resolvedUrl("cards/ButtonCard.qml")
        case "markdown": return Qt.resolvedUrl("cards/MarkdownCard.qml")
        case "vertical-stack": return Qt.resolvedUrl("cards/VerticalStackCard.qml")
        case "horizontal-stack": return Qt.resolvedUrl("cards/HorizontalStackCard.qml")
        case "grid": return Qt.resolvedUrl("cards/GridCard.qml")
        case "thermostat": return Qt.resolvedUrl("cards/ThermostatCard.qml")
        case "light": return Qt.resolvedUrl("cards/LightCard.qml")
        case "humidifier": return Qt.resolvedUrl("cards/HumidifierCard.qml")
        case "sensor": return Qt.resolvedUrl("cards/SensorCard.qml")
        case "gauge": return Qt.resolvedUrl("cards/GaugeCard.qml")
        case "clock": return Qt.resolvedUrl("cards/ClockCard.qml")
        case "alarm-panel": return Qt.resolvedUrl("cards/AlarmCard.qml")
        case "media-control": return Qt.resolvedUrl("cards/MediaCard.qml")
        case "weather-forecast": return Qt.resolvedUrl("cards/WeatherCard.qml")
        case "calendar": return Qt.resolvedUrl("cards/CalendarCard.qml")
        case "todo-list":
        case "shopping-list": return Qt.resolvedUrl("cards/TodoCard.qml")
        case "area": return Qt.resolvedUrl("cards/AreaCard.qml")
        case "plant-status": return Qt.resolvedUrl("cards/PlantCard.qml")
        case "history-graph":
        case "statistics-graph": return Qt.resolvedUrl("cards/HistoryGraphCard.qml")
        case "statistic": return Qt.resolvedUrl("cards/StatisticCard.qml")
        case "picture": return Qt.resolvedUrl("cards/PictureCard.qml")
        case "picture-entity": return Qt.resolvedUrl("cards/PictureEntityCard.qml")
        case "picture-glance": return Qt.resolvedUrl("cards/PictureGlanceCard.qml")
        case "picture-elements": return Qt.resolvedUrl("cards/PictureElementsCard.qml")
        case "map": return Qt.resolvedUrl("cards/MapCard.qml")
        case "iframe":
        case "webpage": return Qt.resolvedUrl("cards/WebpageCard.qml")
        case "conditional": return Qt.resolvedUrl("cards/ConditionalCard.qml")
        case "entity-filter": return Qt.resolvedUrl("cards/EntityFilterCard.qml")
        case "logbook":
        case "activity": return Qt.resolvedUrl("cards/LogbookCard.qml")
        default:
            container = loader.sourceForContainer(t)
            if (container !== "")
                return container
            return Qt.resolvedUrl("cards/FallbackCard.qml")
        }
    }
}
