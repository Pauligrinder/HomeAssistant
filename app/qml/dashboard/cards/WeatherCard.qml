import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: root.statesRevision
    readonly property var forecast: {
        var f = (dashboard && rev >= 0) ? dashboard.attribute(entityId, "forecast") : []
        return f || []
    }

    function conditionIcon(condition) {
        switch (String(condition || "").toLowerCase()) {
        case "clear-night": return "mdi:weather-night"
        case "cloudy": return "mdi:weather-cloudy"
        case "exceptional": return "mdi:alert-circle-outline"
        case "fog": return "mdi:weather-fog"
        case "hail": return "mdi:weather-hail"
        case "lightning": return "mdi:weather-lightning"
        case "lightning-rainy": return "mdi:weather-lightning-rainy"
        case "partlycloudy": return "mdi:weather-partly-cloudy"
        case "pouring": return "mdi:weather-pouring"
        case "rainy": return "mdi:weather-rainy"
        case "snowy": return "mdi:weather-snowy"
        case "snowy-rainy": return "mdi:weather-snowy-rainy"
        case "sunny": return "mdi:weather-sunny"
        case "windy": return "mdi:weather-windy"
        case "windy-variant": return "mdi:weather-windy-variant"
        default: return "mdi:weather-cloudy"
        }
    }

    Column {
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            text: (dashboard && root.rev >= 0)
                  ? root.configName(root.entityId, "Weather") : "Weather"
            color: Theme.highlightColor
        }

        Row {
            width: parent.width
            spacing: Theme.paddingMedium

            MdiIcon {
                width: Theme.iconSizeLarge
                height: width
                mdiIcons: root.mdiIcons
                name: (dashboard && root.rev >= 0)
                      ? root.conditionIcon(dashboard.entityState(root.entityId)) : ""
                iconColor: Theme.highlightColor
            }

            Column {
                width: parent.width - Theme.iconSizeLarge - Theme.paddingMedium

                Label {
                    width: parent.width
                    text: (dashboard && root.rev >= 0)
                          ? dashboard.formatState(root.entityId) : ""
                    font.pixelSize: Theme.fontSizeLarge
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    width: parent.width
                    text: {
                        if (!dashboard || root.rev < 0)
                            return ""
                        var t = dashboard.attribute(root.entityId, "temperature")
                        var u = dashboard.attribute(root.entityId, "temperature_unit")
                        return t !== undefined && t !== null
                                ? String(t) + (u ? " " + String(u) : "°") : ""
                    }
                    color: Theme.secondaryColor
                }
            }
        }

        Repeater {
            model: root.forecast

            Row {
                width: parent.width
                spacing: Theme.paddingSmall

                MdiIcon {
                    width: Theme.iconSizeSmall
                    height: width
                    mdiIcons: root.mdiIcons
                    name: root.conditionIcon(modelData.condition)
                }

                Column {
                    width: parent.width - Theme.iconSizeSmall - Theme.paddingSmall

                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: {
                            var d = modelData.datetime || modelData.day || ""
                            var cond = modelData.condition || ""
                            return String(d) + (cond ? "  " + String(cond) : "")
                        }
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        text: {
                            var high = modelData.temperature
                            var low = modelData.templow
                            if (high === undefined && low === undefined)
                                return ""
                            var unit = dashboard
                                    ? dashboard.attribute(root.entityId, "temperature_unit") : ""
                            return (high !== undefined ? String(high) : "")
                                    + (low !== undefined ? " / " + String(low) : "")
                                    + (unit ? " " + String(unit) : "")
                        }
                    }
                }
            }
        }
    }
}
