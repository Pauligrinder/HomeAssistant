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
    readonly property int totalCount: openModel.count + completedModel.count
    property bool editing: false
    property bool showCompleted: false

    ListModel { id: openModel }
    ListModel { id: completedModel }

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

    function appendEntry(model, entry, section) {
        var summary = entry.summary ? String(entry.summary)
                      : (entry.name ? String(entry.name) : "")
        model.append({
                         "uid": entry.uid ? String(entry.uid) : "",
                         "summary": summary,
                         "status": entry.status ? String(entry.status) : "",
                         "section": section
                     })
    }

    function reload() {
        var raw = dashboard ? dashboard.todoItems(root.entityId) : []
        if (!raw)
            raw = []
        openModel.clear()
        completedModel.clear()
        for (var i = 0; i < raw.length; ++i) {
            var entry = raw[i] || {}
            if (String(entry.status || "") === "completed")
                root.appendEntry(completedModel, entry, "completed")
            else
                root.appendEntry(openModel, entry, "open")
        }
        if (completedModel.count < 1)
            root.showCompleted = false
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

    function lastOpenKey() {
        if (openModel.count < 1)
            return ""
        return root.itemKey(openModel.get(openModel.count - 1))
    }

    function moveItem(model, from, delta) {
        var to = from + delta
        if (!dashboard || to < 0 || to >= model.count)
            return
        var uid = root.itemKey(model.get(from))
        if (!uid.length)
            return
        var previous = ""
        if (delta < 0) {
            if (to > 0)
                previous = root.itemKey(model.get(to - 1))
            else if (model === completedModel)
                previous = root.lastOpenKey()
        } else {
            previous = root.itemKey(model.get(to))
        }
        dashboard.moveTodoItem(root.entityId, uid, previous)
        root.scheduleReload()
    }

    function commitRename(model, index, key, field) {
        if (!dashboard || !field || !key || !key.length)
            return
        var current = ""
        if (model && index >= 0 && index < model.count) {
            var entry = model.get(index)
            current = entry && entry.summary ? String(entry.summary) : ""
        }
        var text = field.text.trim()
        if (!text.length) {
            field.text = current
            return
        }
        if (text === current)
            return
        dashboard.renameTodoItem(root.entityId, key, text)
        if (model && index >= 0 && index < model.count)
            model.setProperty(index, "summary", text)
        root.scheduleReload()
    }

    Timer {
        id: reloadDelay
        interval: 400
        onTriggered: root.requestItems()
    }

    Component.onCompleted: root.requestItems()

    Component {
        id: todoRow
        Item {
            id: row
            width: parent ? parent.width : Theme.itemSizeHuge
            height: root.editing
                    ? Math.max(Theme.itemSizeMedium, editField.height)
                    : Theme.itemSizeSmall
            readonly property var listModel: String(section) === "completed"
                                             ? completedModel : openModel
            readonly property int rowIndex: index
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

                TextField {
                    id: editField
                    width: Math.max(0, parent.width - upButton.width - downButton.width
                                    - deleteButton.width - 3 * Theme.paddingSmall)
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.summaryText
                    label: ""
                    color: row.completed ? Theme.secondaryColor : Theme.primaryColor
                    font.strikeout: row.completed
                    inputMethodHints: Qt.ImhNoPredictiveText
                    EnterKey.enabled: text.trim().length > 0
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: {
                        root.commitRename(row.listModel, row.rowIndex, row.key, editField)
                        focus = false
                    }
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            root.commitRename(row.listModel, row.rowIndex, row.key, editField)
                    }
                }

                IconButton {
                    id: upButton
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-up"
                    enabled: row.rowIndex > 0 && row.key.length > 0
                    onClicked: root.moveItem(row.listModel, row.rowIndex, -1)
                }

                IconButton {
                    id: downButton
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-down"
                    enabled: row.rowIndex < row.listModel.count - 1 && row.key.length > 0
                    onClicked: root.moveItem(row.listModel, row.rowIndex, 1)
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

    Item {
        width: parent.width
        height: Math.max(titleLabel.implicitHeight, editButton.height)

        Label {
            id: titleLabel
            anchors.left: parent.left
            anchors.right: editButton.left
            anchors.rightMargin: Theme.paddingSmall
            anchors.verticalCenter: parent.verticalCenter
            text: root.titleText
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }

        MouseArea {
            id: editButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.itemSizeSmall
            height: Theme.itemSizeSmall
            onClicked: {
                root.editing = !root.editing
                if (!root.editing)
                    addField.text = ""
            }

            MdiIcon {
                id: editIcon
                anchors.centerIn: parent
                mdiIcons: root.mdiIcons
                name: root.editing ? "mdi:check" : "mdi:pencil"
                iconColor: Theme.highlightColor
                width: Theme.iconSizeMedium
            }
        }
    }

    Row {
        width: parent.width
        visible: root.editing
        spacing: Theme.paddingSmall

        TextField {
            id: addField
            width: Math.max(Theme.itemSizeLarge,
                            parent.width - addButton.width - Theme.paddingSmall)
            label: qsTr("Add item")
            placeholderText: qsTr("Add item")
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

    Label {
        width: parent.width
        visible: root.totalCount === 0
        height: visible ? implicitHeight : 0
        text: qsTr("No items")
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeExtraSmall
    }

    Repeater {
        model: openModel
        delegate: todoRow
    }

    MouseArea {
        width: parent.width
        height: visible ? showCompletedLabel.implicitHeight + Theme.paddingSmall : 0
        visible: completedModel.count > 0
        onClicked: root.showCompleted = !root.showCompleted

        Label {
            id: showCompletedLabel
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            text: root.showCompleted ? qsTr("Hide completed items")
                                     : qsTr("Show completed items")
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }

    Repeater {
        model: root.showCompleted ? completedModel : null
        delegate: todoRow
    }
}
