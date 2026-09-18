import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    readonly property string entityId: card && card.calendar_entity
                                       ? String(card.calendar_entity) : ""
    property var events: []
    property date weekStart: weekStartFor(new Date())
    readonly property real timeWidth: Theme.itemSizeSmall
    readonly property real dayWidth: (body.width - timeWidth) / 5
    readonly property real hourHeight: Theme.itemSizeSmall
    readonly property real gridHeight: hourHeight * 8

    function weekStartFor(date) {
        var d = new Date(date.getTime())
        var day = d.getDay()
        var mondayOffset = day === 0 ? -6 : 1 - day
        d.setDate(d.getDate() + mondayOffset)
        d.setHours(0, 0, 0, 0)
        if (day === 5 && date.getHours() >= 16)
            d.setDate(d.getDate() + 7)
        return d
    }

    function weekNumber(date) {
        var d = new Date(date.getTime())
        d.setHours(0, 0, 0, 0)
        d.setDate(d.getDate() + 3 - ((d.getDay() + 6) % 7))
        var firstThursday = new Date(d.getFullYear(), 0, 4)
        return 1 + Math.round(((d.getTime() - firstThursday.getTime()) / 86400000
                               - 3 + ((firstThursday.getDay() + 6) % 7)) / 7)
    }

    function eventDate(event, key) {
        var raw = event ? event[key] : null
        if (raw && typeof raw === "object")
            raw = raw.dateTime || raw.date || ""
        return raw ? new Date(String(raw)) : new Date(NaN)
    }

    function eventDay(event) {
        var date = eventDate(event, "start")
        return isNaN(date.getTime()) ? -1 : date.getDay() - 1
    }

    function eventTop(event) {
        var date = eventDate(event, "start")
        if (isNaN(date.getTime()))
            return 0
        return Math.max(0, ((date.getHours() - 8) * 60 + date.getMinutes())
                        * hourHeight / 60)
    }

    function eventHeight(event) {
        var start = eventDate(event, "start")
        var end = eventDate(event, "end")
        if (isNaN(start.getTime()) || isNaN(end.getTime()))
            return hourHeight
        return Math.max(Theme.paddingLarge,
                        (end.getTime() - start.getTime()) / 60000 * hourHeight / 60)
    }

    function eventVisible(event) {
        var start = eventDate(event, "start")
        if (isNaN(start.getTime()))
            return false
        var day = eventDay(event)
        return day >= 0 && day < 5 && start.getHours() < 16
               && (start.getHours() >= 8 || eventHeight(event) > 0)
    }

    function subjectName(summary) {
        // Same rules as custom-calendar-card.js: drop a leading y/x/v/z
        // grouping letter, then map Wilma subject codes with startsWith.
        var original = summary ? String(summary) : "Tunti"
        var t = String(summary || "")
        if (t.length && t.charAt(0) === "y")
            t = t.substring(1)
        if (t.length && t.charAt(0) === "x")
            t = t.substring(1)
        if (t.length && t.charAt(0) === "v")
            t = t.substring(1)
        if (t.length && t.charAt(0) === "z")
            t = t.substring(1)
        t = t.toLowerCase()
        if (t.indexOf("ena") === 0)
            return "Englanti"
        if (t.indexOf("suk") === 0)
            return "Äidinkieli"
        if (t.indexOf("ma") === 0)
            return "Matematiikka"
        if (t.indexOf("ym") === 0)
            return "Ympäristöoppi"
        if (t.indexOf("ue") === 0)
            return "Uskonto"
        if (t.indexOf("li") === 0)
            return "Liikunta"
        if (t.indexOf("ku") === 0)
            return "Kuvaamataito"
        if (t.indexOf("ks") === 0)
            return "Käsityö"
        if (t.indexOf("fy") === 0)
            return "Fysiikka"
        if (t.indexOf("hi") === 0)
            return "Historia"
        if (t.indexOf("mu") === 0)
            return "Musiikki"
        if (t.indexOf("op") === 0)
            return "Opinnonohjaus"
        if (t.indexOf("bi") === 0)
            return "Biologia"
        if (t.indexOf("ruokailu") === 0)
            return "Ruokailu"
        if (t.indexOf("tunnetaidot") === 0)
            return "Tunnetaidot"
        if (t.indexOf("rub") === 0)
            return "Ruotsi"
        if (t.indexOf("ke") === 0)
            return "Kemia"
        if (t.indexOf("mt") === 0)
            return "Maantieto"
        if (t.indexOf("te") === 0)
            return "Terveystieto"
        if (t.indexOf("yh") === 0)
            return "Yhteiskuntaoppi"
        if (t.indexOf("sel") === 0)
            return "Selvityjät"
        if (t.indexOf("tvt") === 0)
            return "Tieto- ja viestintätekniikka"
        return original
    }

    function colorKey(summary) {
        var text = String(summary || "Unknown")
        var cut = text.indexOf("(")
        if (cut >= 0)
            text = text.substring(0, cut)
        cut = text.indexOf(".")
        if (cut >= 0)
            text = text.substring(0, cut)
        return text.replace(/^\s+|\s+$/g, "")
    }

    function subjectColor(summary) {
        var text = root.colorKey(summary)
        var hash = 0
        for (var i = 0; i < text.length; ++i)
            hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0
        var hue = Math.abs(hash) % 360
        var sat = 65 + (Math.abs(hash) % 20)
        var light = 45 + (Math.abs(hash) % 15)
        return Qt.hsla(hue / 360, sat / 100, light / 100, 1)
    }

    function dayDate(index) {
        var d = new Date(weekStart.getTime())
        d.setDate(d.getDate() + index)
        return (d.getMonth() + 1) + "/" + d.getDate()
    }

    function fetchEvents() {
        if (!dashboard || !entityId.length)
            return
        var end = new Date(weekStart.getTime())
        end.setDate(end.getDate() + 7)
        dashboard.fetchCalendarRange(entityId, weekStart.toISOString(), end.toISOString())
    }

    function syncWeek() {
        var next = weekStartFor(new Date())
        if (next.getTime() !== weekStart.getTime())
            weekStart = next
        fetchEvents()
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
                root.syncWeek()
        }
    }

    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.syncWeek()
    }

    Component.onCompleted: root.syncWeek()

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
            text: root.configName(root.entityId, "School Calendar")
                  + " — Viikko " + root.weekNumber(root.weekStart)
            color: Theme.highlightColor
            truncationMode: TruncationMode.Fade
        }
    }

    Item {
        id: body
        width: parent.width
        height: header.height + root.gridHeight
        clip: true

        Row {
            id: header
            width: parent.width
            height: Theme.itemSizeSmall

            Label {
                width: root.timeWidth
                height: parent.height
                text: "Aika"
                font.pixelSize: Theme.fontSizeTiny
                verticalAlignment: Text.AlignVCenter
            }

            Repeater {
                model: ["MA", "TI", "KE", "TO", "PE"]
                Label {
                    width: root.dayWidth
                    height: header.height
                    text: modelData + "\n" + root.dayDate(index)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.secondaryHighlightColor
                }
            }
        }

        Item {
            id: timetable
            anchors.top: header.bottom
            width: parent.width
            height: root.gridHeight

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.25)
                    ctx.lineWidth = 1
                    for (var h = 0; h <= 8; ++h) {
                        ctx.beginPath()
                        ctx.moveTo(0, h * root.hourHeight)
                        ctx.lineTo(width, h * root.hourHeight)
                        ctx.stroke()
                    }
                    for (var d = 0; d <= 5; ++d) {
                        var x = root.timeWidth + d * root.dayWidth
                        ctx.beginPath()
                        ctx.moveTo(x, 0)
                        ctx.lineTo(x, height)
                        ctx.stroke()
                    }
                }
            }

            Repeater {
                model: 8
                Label {
                    x: 0
                    y: index * root.hourHeight
                    width: root.timeWidth - Theme.paddingSmall
                    height: root.hourHeight
                    text: (index + 8) + ":00"
                    font.pixelSize: Theme.fontSizeTiny
                    color: Theme.secondaryColor
                    horizontalAlignment: Text.AlignRight
                }
            }

            Repeater {
                model: root.events
                Rectangle {
                    readonly property int dayIndex: root.eventDay(modelData)
                    visible: root.eventVisible(modelData)
                    x: root.timeWidth + dayIndex * root.dayWidth + 1
                    y: root.eventTop(modelData) + 1
                    width: root.dayWidth - 2
                    height: Math.min(root.eventHeight(modelData),
                                     root.gridHeight - y)
                    radius: Theme.paddingSmall / 2
                    color: root.subjectColor(modelData.summary || modelData.title)

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.paddingSmall / 2
                        clip: true
                        Label {
                            width: parent.width
                            text: root.subjectName(modelData.summary || modelData.title)
                            font.pixelSize: Theme.fontSizeTiny
                            color: "white"
                            wrapMode: Text.Wrap
                        }
                        Label {
                            width: parent.width
                            visible: !!modelData.location
                            text: modelData.location ? String(modelData.location) : ""
                            font.pixelSize: Theme.fontSizeTiny
                            color: "white"
                            opacity: 0.8
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }
        }
    }
}
