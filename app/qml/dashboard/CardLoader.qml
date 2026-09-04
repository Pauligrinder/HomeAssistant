import QtQuick 2.6
import Sailfish.Silica 1.0

Loader {
    id: loader
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int columns: 12
    property int unitWidth: parent ? parent.width : width

    width: {
        var cols = (card && card._columns) ? card._columns : 12
        var span = Math.min(loader.columns, Math.max(1, cols))
        var gap = Theme.paddingSmall
        var unit = (loader.unitWidth - gap * (loader.columns - 1)) / loader.columns
        return Math.max(Theme.itemSizeSmall, span * unit + Math.max(0, span - 1) * gap)
    }

    source: loader.sourceForType(card ? card.type : "")

    onLoaded: {
        if (!item)
            return
        item.card = Qt.binding(function() { return loader.card })
        item.dashboard = Qt.binding(function() { return loader.dashboard })
        item.hassClient = Qt.binding(function() { return loader.hassClient })
        item.mdiIcons = Qt.binding(function() { return loader.mdiIcons })
        item.width = Qt.binding(function() { return loader.width })
    }

    function sourceForType(type) {
        var t = String(type || "")
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
            return Qt.resolvedUrl("cards/FallbackCard.qml")
        }
    }
}
