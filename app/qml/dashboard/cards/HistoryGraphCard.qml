import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    property var points: []
    readonly property var entityIds: {
        if (card && card.entities)
            return card.entities
        if (card && card.entity)
            return [card.entity]
        return []
    }

    Connections {
        target: dashboard
        onHistoryReady: {
            if (root.entityIds.indexOf(entityId) >= 0)
                root.points = points
        }
    }

    Component.onCompleted: {
        var ids = []
        for (var i = 0; i < root.entityIds.length; ++i) {
            var e = root.entityIds[i]
            ids.push(typeof e === "string" ? e : (e.entity || ""))
        }
        if (dashboard && ids.length)
            dashboard.fetchHistory(ids, 24)
    }

    Label {
        width: parent.width
        text: card && card.title ? card.title : "History"
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Canvas {
        id: canvas
        width: parent.width
        height: Theme.itemSizeExtraLarge
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var src = root.points || []
            if (src.length < 2)
                return
            var nums = []
            for (var i = 0; i < src.length; ++i) {
                var v = Number(src[i].state)
                if (!isNaN(v))
                    nums.push(v)
            }
            if (nums.length < 2)
                return
            var min = Math.min.apply(Math, nums)
            var max = Math.max.apply(Math, nums)
            if (min === max) {
                min -= 1
                max += 1
            }
            ctx.strokeStyle = Theme.highlightColor
            ctx.lineWidth = 2
            ctx.beginPath()
            for (var j = 0; j < nums.length; ++j) {
                var x = j * (width - 2) / (nums.length - 1)
                var y = height - ((nums[j] - min) / (max - min)) * (height - 4) - 2
                if (j === 0)
                    ctx.moveTo(x, y)
                else
                    ctx.lineTo(x, y)
            }
            ctx.stroke()
        }
        Connections {
            target: root
            onPointsChanged: canvas.requestPaint()
        }
    }
}
