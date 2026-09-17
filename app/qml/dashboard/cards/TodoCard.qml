import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property string entityId: card && card.entity ? String(card.entity) : ""
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property string titleText: {
        if (card && card.title && String(card.title).length)
            return String(card.title)
        return root.configName(root.entityId, "To-do")
    }
    property bool editing: false

    ListModel {
        id: itemModel
    }

    Connections {
        target: dashboard
        onTodoReady: {
            if (entityId === root.entityId)
                root.reload()
        }
        onReadyChanged: {
            if (dashboard && dashboard.ready)
                root.requestItems()
        }
        onEntityChanged: {
            if (entityId === root.entityId)
                root.requestItems()
        }
    }

    function requestItems() {
        if (dashboard && root.entityId.length)
            dashboard.fetchTodo(root.entityId)
    }

    function reload() {
        var raw = dashboard ? dashboard.todoItems(root.entityId) : []
        if (!raw)
            raw = []
        itemModel.clear()
        for (var i = 0; i < raw.length; ++i) {
            var entry = raw[i] || {}
            var summary = entry.summary ? String(entry.summary)
                          : (entry.name ? String(entry.name) : "")
            itemModel.append({
                                 "uid": entry.uid ? String(entry.uid) : "",
                                 "summary": summary,
                                 "status": entry.status ? String(entry.status) : ""
                             })
        }
        if (itemModel.count === 0)
            root.editing = false
    }

    function scheduleReload() {
        reloadDelay.restart()
    }

    function itemKey(entry) {
        if (!entry)
            return ""
        if (entry.uid)
            return String(entry.uid)
        if (entry.summary)
            return String(entry.summary)
        if (entry.name)
            return String(entry.name)
        return ""
    }

    function addItem() {
        var text = addField.text.trim()
        if (!text.length || !dashboard)
            return
        dashboard.addTodoItem(root.entityId, text)
        addField.text = ""
        root.scheduleReload()
    }

    function moveItem(from, delta) {
        var to = from + delta
        if (!dashboard || to < 0 || to >= itemModel.count)
            return
        var uid = root.itemKey(itemModel.get(from))
        if (!uid.length)
            return
        var previous = ""
        if (delta < 0) {
            if (to > 0)
                previous = root.itemKey(itemModel.get(to - 1))
        } else {
            previous = root.itemKey(itemModel.get(to))
        }
        dashboard.moveTodoItem(root.entityId, uid, previous)
        root.scheduleReload()
    }

    Timer {
        id: reloadDelay
        interval: 400
        onTriggered: root.requestItems()
    }

    Component.onCompleted: root.requestItems()

    Row {
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            width: Math.max(0, parent.width - editButton.width - Theme.paddingSmall)
            text: root.titleText
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }

        MouseArea {
            id: editButton
            width: editLabel.implicitWidth + Theme.paddingSmall
            height: Theme.itemSizeExtraSmall
            enabled: itemModel.count > 0 || root.editing
            opacity: enabled ? 1 : 0.4
            onClicked: root.editing = !root.editing

            Label {
                id: editLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.editing ? "Done" : "Edit"
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }
    }

    Label {
        width: parent.width
        visible: itemModel.count === 0
        height: visible ? implicitHeight : 0
        text: "No items"
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }

    Repeater {
        model: itemModel

        Item {
            id: row
            width: parent.width
            height: Theme.itemSizeSmall
            property int rowIndex: index
            readonly property string key: uid && String(uid).length ? String(uid)
                                          : (summary ? String(summary) : "")
            readonly property string summaryText: summary ? String(summary) : (row.key || "Item")
            readonly property bool completed: String(status) === "completed"

            TextSwitch {
                anchors.fill: parent
                visible: !root.editing
                text: row.summaryText
                checked: row.completed
                automaticCheck: false
                onClicked: {
                    if (!dashboard || !row.key.length)
                        return
                    dashboard.setTodoItem(root.entityId, row.key, !row.completed)
                    root.scheduleReload()
                }
            }

            Row {
                visible: root.editing
                anchors.fill: parent
                spacing: Theme.paddingSmall

                Label {
                    y: (parent.height - height) / 2
                    width: Math.max(0, parent.width - upButton.width - downButton.width
                                    - deleteButton.width - 3 * Theme.paddingSmall)
                    text: row.summaryText
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: row.completed ? Theme.secondaryColor : Theme.primaryColor
                    font.strikeout: row.completed
                }

                IconButton {
                    id: upButton
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-up"
                    enabled: row.rowIndex > 0 && row.key.length > 0
                    onClicked: root.moveItem(row.rowIndex, -1)
                }

                IconButton {
                    id: downButton
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-down"
                    enabled: row.rowIndex < itemModel.count - 1 && row.key.length > 0
                    onClicked: root.moveItem(row.rowIndex, 1)
                }

                IconButton {
                    id: deleteButton
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-delete"
                    enabled: row.key.length > 0
                    onClicked: {
                        if (!dashboard)
                            return
                        dashboard.removeTodoItem(root.entityId, row.key)
                        root.scheduleReload()
                    }
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Theme.paddingSmall

        TextField {
            id: addField
            width: Math.max(Theme.itemSizeLarge,
                            parent.width - addButton.width - Theme.paddingSmall)
            label: "Add item"
            placeholderText: "Add item"
            inputMethodHints: Qt.ImhNoPredictiveText
            EnterKey.enabled: text.trim().length > 0
            EnterKey.iconSource: "image://theme/icon-m-add"
            EnterKey.onClicked: root.addItem()
        }

        IconButton {
            id: addButton
            width: Theme.iconSizeMedium
            height: Theme.iconSizeMedium
            anchors.verticalCenter: addField.verticalCenter
            icon.source: "image://theme/icon-m-add"
            enabled: addField.text.trim().length > 0
            onClicked: root.addItem()
        }
    }
}
