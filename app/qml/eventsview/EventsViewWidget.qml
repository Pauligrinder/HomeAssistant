import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root
    property var entities: []
    property string statusText: ""
    property bool reorderEnabled: false
    property Item trashItem
    property Item coordinateItem

    property string dragEntityId: ""
    property int dragFromIndex: -1
    property int dragInsertIndex: -1
    property int dragCardHeight: 0
    property real dragY: 0
    property bool dragOverTrash: false
    property string dragName: ""
    property string dragBody: ""
    readonly property bool dragging: dragEntityId.length > 0
    readonly property Item overlayParent: coordinateItem ? coordinateItem : root

    signal reorderRequested(string entityId, int newIndex)
    signal removeRequested(string entityId)

    width: parent ? parent.width : Screen.width
    implicitWidth: width
    implicitHeight: visible ? column.height : 0
    height: implicitHeight
    visible: (entities && entities.length > 0) || statusText.length > 0

    function stateLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        if (entity.kind === "script")
            return ""
        if (entity.kind === "climate")
            return root.climateLabel(entity)
        if (entity.kind === "graph" || entity.kind === "sensor")
            return root.graphLabel(entity)
        if (entity.dimmable === true && entity.on === true)
            return "On · " + Math.round(Number(entity.brightnessPct) || 0) + "%"
        return entity.on === true ? "On" : "Off"
    }

    function formatGraphValue(value) {
        var n = Number(value)
        if (!isFinite(n))
            return ""
        if (Math.abs(n) >= 100)
            return String(Math.round(n))
        var shown = n.toFixed(2).replace(/\.?0+$/, "")
        return shown.length ? shown : "0"
    }

    function graphLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        var shown = root.formatGraphValue(entity.graphNow)
        if (!shown.length && entity.state && entity.state !== "unknown"
                && entity.state !== "unavailable")
            shown = entity.state
        var unit = entity.graphUnit || ""
        if (!shown.length)
            return unit
        return unit ? (shown + " " + unit) : shown
    }

    function formatTemp(entity) {
        if (!entity)
            return ""
        var t = Number(entity.targetTemp)
        if (!isFinite(t))
            t = Number(entity.currentTemp)
        if (!isFinite(t))
            return ""
        var step = Number(entity.tempStep) || 0.5
        var shown = step < 1
                    ? (Math.round(t / step) * step).toFixed(1).replace(/\.0$/, "")
                    : String(Math.round(t))
        return shown + (entity.tempUnit || "°")
    }

    function climateLabel(entity) {
        if (!entity || entity.on !== true)
            return "Off"
        var mode = entity.hvacMode || entity.state || ""
        var label = ""
        if (mode === "fan_only")
            label = "Fan"
        else if (mode === "heat_cool")
            label = "Heat/Cool"
        else if (mode === "off")
            return "Off"
        else if (!mode)
            label = "On"
        else
            label = mode.charAt(0).toUpperCase() + mode.slice(1)
        var temp = entity.supportsTargetTemp === true ? root.formatTemp(entity) : ""
        return temp ? (label + " · " + temp) : label
    }

    function entityIndexOf(entityId) {
        var src = root.entities || []
        for (var i = 0; i < src.length; ++i) {
            if (src[i] && src[i].entityId === entityId)
                return i
        }
        return -1
    }

    function beginDrag(entity, cardItem) {
        if (!root.reorderEnabled || !entity || !entity.entityId || root.dragging)
            return
        root.dragEntityId = entity.entityId
        root.dragFromIndex = root.entityIndexOf(entity.entityId)
        root.dragInsertIndex = root.dragFromIndex
        root.dragCardHeight = cardItem ? Math.max(cardItem.height, Theme.itemSizeSmall)
                                       : Theme.itemSizeMedium
        root.dragName = entity.name || entity.entityId
        root.dragBody = root.stateLabel(entity)
        root.dragOverTrash = false
    }

    function updateDrag(sceneX, sceneY) {
        if (!root.dragging)
            return
        var overlay = root.overlayParent
        var local = overlay.mapFromItem(null, sceneX, sceneY)
        root.dragY = Math.max(0, local.y - root.dragCardHeight / 2)
        if (root.trashItem && root.trashItem.visible && root.trashItem.height > 0) {
            var trash = root.trashItem.mapFromItem(null, sceneX, sceneY)
            root.dragOverTrash = trash.y >= 0 && trash.y <= root.trashItem.height
                    && trash.x >= 0 && trash.x <= root.trashItem.width
        } else {
            root.dragOverTrash = false
        }
        if (root.dragOverTrash)
            return
        var pointerY = column.mapFromItem(null, sceneX, sceneY).y
        var insert = (root.entities || []).length
        var favIdx = 0
        for (var i = 0; i < orderRepeater.count; ++i) {
            var item = orderRepeater.itemAt(i)
            if (!item)
                continue
            if (item.entityId === root.dragEntityId) {
                favIdx += 1
                continue
            }
            var visualMid = item.y + item.dragShift + item.height / 2
            if (pointerY < visualMid) {
                insert = favIdx
                break
            }
            favIdx += 1
        }
        root.dragInsertIndex = insert
    }

    function endDrag() {
        if (!root.dragging)
            return
        var entityId = root.dragEntityId
        var from = root.dragFromIndex
        var to = root.dragInsertIndex
        var overTrash = root.dragOverTrash
        root.dragEntityId = ""
        root.dragOverTrash = false
        root.dragFromIndex = -1
        root.dragInsertIndex = -1
        if (overTrash) {
            root.removeRequested(entityId)
            return
        }
        if (from < 0)
            return
        if (to > from)
            to -= 1
        if (to === from || to < 0)
            return
        root.reorderRequested(entityId, to)
    }

    function cancelDrag() {
        root.dragEntityId = ""
        root.dragOverTrash = false
        root.dragFromIndex = -1
        root.dragInsertIndex = -1
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            text: "Helmsman"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeMedium
            font.family: Theme.fontFamilyHeading
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            visible: root.statusText.length > 0 && (!root.entities || root.entities.length === 0)
            wrapMode: Text.Wrap
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            text: root.statusText
        }

        Repeater {
            id: orderRepeater
            model: root.entities || []
            delegate: Item {
                id: row
                property string entityId: modelData.entityId || ""
                property int orderIndex: index
                property real dragShift: {
                    if (!root.dragging)
                        return 0
                    if (root.dragOverTrash)
                        return 0
                    var from = root.dragFromIndex
                    var to = root.dragInsertIndex
                    var idx = row.orderIndex
                    if (idx < 0 || idx === from)
                        return 0
                    var h = root.dragCardHeight + Theme.paddingSmall
                    if (from < to && idx > from && idx < to)
                        return -h
                    if (from > to && idx >= to && idx < from)
                        return h
                    return 0
                }

                x: Theme.horizontalPageMargin
                width: column.width - 2 * x
                height: root.reorderEnabled
                        ? Math.max(labels.height + 2 * Theme.paddingSmall, Theme.itemSizeSmall)
                        : labels.height
                opacity: (root.dragging && root.dragEntityId === row.entityId) ? 0.35 : 1
                transform: Translate {
                    y: row.dragShift
                    Behavior on y { NumberAnimation { duration: 120 } }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingSmall
                    color: "#03A9F4"
                    visible: root.reorderEnabled
                    opacity: handle.pressed ? 0.32 : 0.12
                }

                MouseArea {
                    id: handle
                    anchors.fill: parent
                    enabled: root.reorderEnabled
                    preventStealing: drag.active || (root.dragging
                                     && root.dragEntityId === row.entityId)
                    drag.target: dragDummy
                    drag.axis: Drag.YAxis
                    drag.threshold: Theme.paddingMedium

                    Item {
                        id: dragDummy
                        width: 1
                        height: 1
                        visible: false
                    }

                    onPositionChanged: {
                        if (!pressed)
                            return
                        if (drag.active && !root.dragging)
                            root.beginDrag(modelData, row)
                        if (root.dragging && root.dragEntityId === row.entityId) {
                            var g = handle.mapToItem(null, mouse.x, mouse.y)
                            root.updateDrag(g.x, g.y)
                        }
                    }
                    onReleased: {
                        if (root.dragging && root.dragEntityId === row.entityId)
                            root.endDrag()
                        dragDummy.x = 0
                        dragDummy.y = 0
                    }
                    onCanceled: {
                        if (root.dragging && root.dragEntityId === row.entityId)
                            root.cancelDrag()
                        dragDummy.x = 0
                        dragDummy.y = 0
                    }
                }

                Row {
                    id: labels
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: root.reorderEnabled ? Theme.paddingMedium : 0
                    anchors.rightMargin: root.reorderEnabled ? Theme.paddingMedium : 0
                    spacing: Theme.paddingSmall

                    Column {
                        width: parent.width - (grip.visible ? grip.width + parent.spacing : 0)
                        spacing: 0

                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            color: Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: modelData.kind !== "script"
                                       && (modelData.kind === "graph"
                                           || modelData.kind === "sensor"
                                           || modelData.on === true)
                            text: modelData.name || modelData.entityId
                        }

                        Label {
                            width: parent.width
                            truncationMode: TruncationMode.Fade
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            visible: text.length > 0
                            text: root.stateLabel(modelData)
                        }
                    }

                    Column {
                        id: grip
                        width: Theme.paddingLarge
                        visible: root.reorderEnabled
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        opacity: 0.7

                        Repeater {
                            model: 3
                            Rectangle {
                                width: grip.width
                                height: 2
                                radius: 1
                                color: Theme.secondaryColor
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        id: dragProxy
        parent: root.overlayParent
        visible: root.dragging
        z: 100
        x: Theme.horizontalPageMargin
        y: root.dragY
        width: (root.overlayParent ? root.overlayParent.width : root.width)
               - 2 * Theme.horizontalPageMargin
        height: Math.max(root.dragCardHeight, Theme.itemSizeSmall)
        opacity: root.dragOverTrash ? 0.45 : 0.92

        Rectangle {
            anchors.fill: parent
            radius: Theme.paddingMedium
            color: "#03A9F4"
            opacity: 0.4
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Theme.paddingLarge
            spacing: Theme.paddingSmall

            Label {
                width: parent.width
                truncationMode: TruncationMode.Fade
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                text: root.dragName
            }

            Label {
                width: parent.width
                visible: root.dragBody.length > 0
                truncationMode: TruncationMode.Fade
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: root.dragBody
            }
        }
    }
}
