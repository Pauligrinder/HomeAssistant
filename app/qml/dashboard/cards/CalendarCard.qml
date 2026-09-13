import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    property var events: []

    function fetchEvents() {
        if (dashboard && entityId.length)
            dashboard.fetchCalendar(entityId)
    }

    Connections {
        target: dashboard
        onCalendarReady: {
            if (entityId === root.entityId)
                root.events = dashboard.calendarEvents(root.entityId)
        }
        onEntityChanged: {
            if (entityId === root.entityId)
                root.fetchEvents()
        }
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive)
                root.fetchEvents()
        }
    }

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.fetchEvents()
    }

    Component.onCompleted: root.fetchEvents()

    Row {
        width: parent.width
        spacing: Theme.paddingSmall

        MdiIcon {
            mdiIcons: root.mdiIcons
            name: (dashboard && root.statesRevision >= 0)
                  ? dashboard.entityIcon(root.entityId, card && card.icon ? card.icon : "")
                  : "mdi:calendar"
            width: Theme.iconSizeSmall
            height: width
            iconColor: Theme.highlightColor
        }
        Label {
            width: parent.width - Theme.iconSizeSmall - Theme.paddingSmall
            text: (dashboard && root.statesRevision >= 0)
                  ? dashboard.friendlyName(entityId, "Calendar") : "Calendar"
            color: Theme.highlightColor
            truncationMode: TruncationMode.Fade
        }
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
