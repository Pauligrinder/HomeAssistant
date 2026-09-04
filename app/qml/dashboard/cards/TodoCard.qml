import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    property var items: []

    Connections {
        target: dashboard
        onTodoReady: {
            if (entityId === root.entityId)
                root.reload()
        }
    }

    function reload() {
        var raw = dashboard ? dashboard.todoItems(entityId) : []
        if (raw && raw.items)
            root.items = raw.items
        else
            root.items = raw || []
    }

    Component.onCompleted: {
        if (dashboard && entityId.length)
            dashboard.fetchTodo(entityId)
    }

    Label {
        width: parent.width
        text: dashboard ? dashboard.friendlyName(entityId, "To-do") : "To-do"
        color: Theme.highlightColor
    }
    Repeater {
        model: root.items
        TextSwitch {
            width: parent.width
            text: modelData.summary || modelData.uid || "Item"
            checked: String(modelData.status) === "completed"
            onClicked: {
                if (dashboard)
                    dashboard.setTodoItem(entityId, modelData.summary || modelData.uid, checked)
            }
        }
    }
}
