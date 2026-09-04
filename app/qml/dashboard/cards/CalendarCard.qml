import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    property var events: []

    Connections {
        target: dashboard
        onCalendarReady: {
            if (entityId === root.entityId)
                root.events = dashboard.calendarEvents(root.entityId)
        }
    }

    Component.onCompleted: {
        if (dashboard && entityId.length)
            dashboard.fetchCalendar(entityId)
    }

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId, "Calendar") : "Calendar"
        color: Theme.highlightColor
    }
    Repeater {
        model: root.events
        Label {
            width: parent.width
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            text: (modelData.summary || modelData.title || "Event")
                  + (modelData.start ? ("\n" + String(modelData.start)) : "")
        }
    }
    Label {
        visible: root.events.length === 0
        text: "No upcoming events"
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }
}
