import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property var entities: {
        if (card && card.entities)
            return card.entities
        return []
    }
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Label {
        width: parent.width
        text: "Map"
        color: Theme.highlightColor
    }

    Repeater {
        model: root.entities.length ? root.entities : root.trackerEntities()
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            text: {
                var id = typeof modelData === "string" ? modelData : (modelData.entity || "")
                if (!dashboard || root.rev < 0)
                    return id
                var name = dashboard.friendlyName(id)
                var lat = dashboard.attribute(id, "latitude")
                var lon = dashboard.attribute(id, "longitude")
                var state = dashboard.formatState(id)
                if (lat && lon)
                    return name + " — " + state + "\n" + lat + ", " + lon
                return name + " — " + state
            }
        }
    }

    Button {
        text: "Open map in Home Assistant"
        onClicked: {
            if (dashboard)
                dashboard.openWebPath("/map")
        }
    }

    function trackerEntities() {
        // Fallback: show nothing extra; the button still opens HA map.
        return []
    }
}
