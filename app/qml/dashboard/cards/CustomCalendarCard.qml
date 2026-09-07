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
        var original = String(summary || "Event")
        var token = original.toLowerCase().replace(/^[yxvz]\s*/, "")
                            .split(/[.(\s]/)[0]
        var names = {
            "ena": "Englanti", "suk": "Äidinkieli", "ma": "Matematiikka",
            "ym": "Ympäristöoppi", "ue": "Uskonto", "li": "Liikunta",
            "ku": "Kuvataide", "ks": "Käsityö", "fy": "Fysiikka",
            "hi": "Historia", "mu": "Musiikki", "op": "Oppilaanohjaus",
            "bi": "Biologia", "ruokailu": "Ruokailu", "tunnetaidot": "Tunnetaidot",
            "rub": "Ruotsi", "ke": "Kemia", "mt": "Maantieto",
            "te": "Terveystieto", "yh": "Yhteiskuntaoppi", "sel": "SEL",
            "tvt": "TVT"
        }
        return names[token] || original
    }

    function subjectColor(summary) {
        var text = String(summary || "Event").split(/[.(]/)[0]
        var hash = 0
        for (var i = 0; i < text.length; ++i)
            hash = ((hash << 5) - hash + text.charCodeAt(i)) | 0
        return Qt.hsla(Math.abs(hash % 360) / 360, 0.62, 0.38, 0.9)
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

    Connections {
        target: dashboard
        onCalendarReady: {
            if (entityId === root.entityId)
                root.events = dashboard.calendarEvents(root.entityId)
        }
    }

    Component.onCompleted: root.fetchEvents()

    Row {
        width: parent.width
        spacing: Theme.paddingSmall

        MdiIcon {
            mdiIcons: root.mdiIcons
            name: "mdi:book-open-variant"
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
