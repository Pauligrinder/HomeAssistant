import QtQuick 2.6
import Sailfish.Silica 1.0

CoverBackground {
    id: cover
    property var hassClient
    property var mdiIcons
    property int notificationCount: 0
    property string notificationTitle: ""
    property string notificationBody: ""
    property string notificationColor: "#03A9F4"
    property string notificationIcon: ""
    property bool showingNotification: notificationCount > 0
            && (notificationTitle.length > 0 || notificationBody.length > 0)
    property int coverPage: 0
    property int entitiesGen: 0
    property bool coverActionOdd: false

    readonly property var favorites: {
        var _ = cover.entitiesGen
        return (hassClient && hassClient.widget)
                ? (hassClient.widget.widgetEntities || [])
                : []
    }
    readonly property bool showingFavorites: !showingNotification
            && hassClient && hassClient.loggedIn
            && favorites.length > 0
    // Lipstick only delivers taps to CoverAction (max two). More than two
    // favorites are shown one at a time so the left action can stay "toggle".
    readonly property int itemsPerPage: favorites.length > 2 ? 1 : 2
    readonly property int pageCount: Math.max(1, Math.ceil(favorites.length / itemsPerPage))
    readonly property var pageEntities: {
        var all = favorites
        var start = coverPage * itemsPerPage
        var out = []
        for (var i = 0; i < itemsPerPage; ++i) {
            var idx = start + i
            if (idx >= all.length)
                break
            out.push(all[idx])
        }
        return out
    }
    readonly property var leftEntity: pageEntities.length > 0 ? pageEntities[0] : null
    readonly property var rightEntity: pageEntities.length > 1 ? pageEntities[1] : null
    readonly property string leftEntityId: leftEntity && leftEntity.entityId ? leftEntity.entityId : ""
    readonly property string leftToggleIcon: coverToggleIcon(leftEntity)
    readonly property string rightToggleIcon: coverToggleIcon(rightEntity)
    // Sensors have no service to call, so their action slot stays empty. It is
    // still laid out so a paired toggle or next-page button keeps its half.
    readonly property bool leftActionEnabled: !!leftEntity && !isSensor(leftEntity)
    readonly property bool rightActionEnabled: !!rightEntity && !isSensor(rightEntity)
    readonly property bool watermarkOn: favoriteEmphasized(leftEntity)
    readonly property string watermarkIconName: (leftEntity && leftEntity.icon) ? String(leftEntity.icon) : ""
    property string favoriteWatermarkPath: ""

    function isSensor(entity) {
        return !!entity && entity.kind === "sensor"
    }

    // Sensors and lit favorites get the stronger watermark, matching the widget.
    function favoriteEmphasized(entity) {
        if (!entity)
            return false
        if (isSensor(entity))
            return true
        return entity.kind !== "script" && entity.on === true
    }

    function formatSensorValue(value) {
        var n = Number(value)
        if (!isFinite(n))
            return ""
        if (Math.abs(n) >= 100)
            return String(Math.round(n))
        var shown = n.toFixed(2).replace(/\.?0+$/, "")
        return shown.length ? shown : "0"
    }

    function sensorLabel(entity) {
        var shown = cover.formatSensorValue(entity.graphNow)
        if (!shown.length && entity.state && entity.state !== "unknown"
                && entity.state !== "unavailable")
            shown = entity.state
        var unit = entity.graphUnit || ""
        if (!shown.length)
            return unit
        return unit ? (shown + " " + unit) : shown
    }

    function favoriteStateLabel(entity) {
        if (!entity)
            return ""
        if (entity.available === false)
            return entity.state || "unavailable"
        if (entity.kind === "script")
            return ""
        if (cover.isSensor(entity))
            return cover.sensorLabel(entity)
        if (entity.dimmable === true && entity.on)
            return "On · " + Math.round(Number(entity.brightnessPct) || 0) + "%"
        return entity.on ? "On" : "Off"
    }

    function favoriteName(entity) {
        if (!entity)
            return ""
        return entity.name || entity.entityId || ""
    }

    function coverToggleIcon(entity) {
        if (cover.isSensor(entity))
            return ""
        if (!entity || entity.available === false)
            return "image://theme/icon-cover-refresh"
        if (entity.kind === "script")
            return "image://theme/icon-cover-play"
        if (entity.on)
            return "image://theme/icon-cover-pause"
        return "image://theme/icon-cover-play"
    }

    function favoriteWatermarkMdi(entity) {
        if (!entity)
            return ""
        var icon = entity.icon ? String(entity.icon) : ""
        if (entity.kind === "script")
            return icon.length ? icon : "mdi:script-text"
        if (cover.isSensor(entity))
            return icon.length ? icon : "mdi:chart-line"
        if (entity.kind === "climate") {
            if (!icon.length)
                return entity.on === true ? "mdi:air-conditioner" : "mdi:fan-off"
            if (entity.on !== true && icon === "mdi:air-conditioner")
                return "mdi:fan-off"
            return icon
        }
        if (entity.kind === "switch") {
            if (entity.on === true)
                return icon.length ? icon : "mdi:toggle-switch"
            return icon.length ? icon : "mdi:toggle-switch-off"
        }
        if (entity.on === true)
            return icon.length ? icon : "mdi:lightbulb"
        if (!icon.length)
            return "mdi:lightbulb-outline"
        if (icon.indexOf("-outline") >= 0 || icon.indexOf("-off") >= 0)
            return icon
        var outline = icon + "-outline"
        if (mdiIcons && mdiIcons.hasIcon && mdiIcons.hasIcon(outline))
            return outline
        return icon
    }

    function updateFavoriteWatermark() {
        if (!cover.showingFavorites || !mdiIcons || !mdiIcons.ready || !cover.leftEntity) {
            cover.favoriteWatermarkPath = ""
            return
        }
        var name = cover.favoriteWatermarkMdi(cover.leftEntity)
        var path = name.length ? mdiIcons.renderIconFile(name, "#FFFFFF", 256) : ""
        cover.favoriteWatermarkPath = path || ""
    }

    function toggleFavorite(entity) {
        if (!entity || cover.isSensor(entity))
            return
        var entityId = entity.entityId
        if (!entityId || !hassClient || !hassClient.widget)
            return
        hassClient.widget.toggleLight(entityId)
        cover.coverActionOdd = !cover.coverActionOdd
    }

    function syncCoverPage() {
        var last = Math.max(0, pageCount - 1)
        if (coverPage > last)
            coverPage = last
    }

    function nextCoverPage() {
        coverPage = (coverPage + 1) % pageCount
    }

    onPageCountChanged: syncCoverPage()
    onStatusChanged: {
        if (status === Cover.Active && hassClient && hassClient.widget && hassClient.loggedIn)
            hassClient.widget.refresh()
    }

    Connections {
        target: (hassClient && hassClient.widget) ? hassClient.widget : null
        onWidgetEntitiesChanged: cover.entitiesGen += 1
    }

    Connections {
        target: mdiIcons
        onReadyChanged: cover.updateFavoriteWatermark()
    }

    onShowingFavoritesChanged: cover.updateFavoriteWatermark()
    onLeftEntityIdChanged: cover.updateFavoriteWatermark()
    onWatermarkOnChanged: cover.updateFavoriteWatermark()
    onWatermarkIconNameChanged: cover.updateFavoriteWatermark()

    // Required for the ambience wallpaper to remain visible behind the tint.
    transparent: true

    // Use item opacity (not #AARRGGBB in a gradient) — cover gradients often
    // composite as opaque and completely hide the ambience.
    Rectangle {
        anchors.fill: parent
        color: cover.showingNotification ? cover.notificationColor : "#03A9F4"
        opacity: cover.showingNotification ? 0.72 : 0.32
    }

    // Default house watermark when idle: full cover height, half off the right edge.
    Item {
        id: houseWatermark
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.right
        width: height
        opacity: 0.22
        visible: !cover.showingNotification && !cover.showingFavorites
        z: 0

        Canvas {
            id: homeCanvas
            anchors.fill: parent
            antialiasing: true

            // Rounded-rect hole; used with destination-out for windows.
            function punchRoundRect(ctx, x, y, w, h, r) {
                if (r * 2 > w)
                    r = w * 0.5
                if (r * 2 > h)
                    r = h * 0.5
                ctx.beginPath()
                ctx.moveTo(x + r, y)
                ctx.lineTo(x + w - r, y)
                ctx.quadraticCurveTo(x + w, y, x + w, y + r)
                ctx.lineTo(x + w, y + h - r)
                ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
                ctx.lineTo(x + r, y + h)
                ctx.quadraticCurveTo(x, y + h, x, y + h - r)
                ctx.lineTo(x, y + r)
                ctx.quadraticCurveTo(x, y, x + r, y)
                ctx.closePath()
                ctx.fill()
            }

            onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                ctx.clearRect(0, 0, w, h)

                // Design space is 100x100, mapped to fill the canvas.
                var s = Math.min(w, h) / 100
                var ox = (w - 100 * s) * 0.5
                var oy = (h - 100 * s) * 0.5
                function X(u) { return ox + u * s }
                function Y(v) { return oy + v * s }

                // Roof line (left eave 6,41 → peak 50,3) so the chimney sits on it.
                function roofY(x) {
                    return 41 + (3 - 41) * (x - 6) / (50 - 6)
                }

                var chimL = 25
                var chimR = 33.5
                var chimTop = 6.5

                ctx.fillStyle = "#FFFFFF"
                ctx.strokeStyle = "#FFFFFF"
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.lineWidth = Math.max(1.5, s * 1.15)

                ctx.beginPath()
                // Bottom-left, slightly rounded.
                ctx.moveTo(X(21), Y(97))
                ctx.quadraticCurveTo(X(16.5), Y(97), X(16.5), Y(92.5))
                ctx.lineTo(X(16.5), Y(41))
                ctx.lineTo(X(6), Y(41))
                ctx.lineTo(X(chimL), Y(roofY(chimL)))
                ctx.lineTo(X(chimL), Y(chimTop))
                ctx.lineTo(X(chimR), Y(chimTop))
                ctx.lineTo(X(chimR), Y(roofY(chimR)))
                ctx.lineTo(X(50), Y(3))
                ctx.lineTo(X(94), Y(41))
                ctx.lineTo(X(83.5), Y(41))
                ctx.lineTo(X(83.5), Y(92.5))
                ctx.quadraticCurveTo(X(83.5), Y(97), X(79), Y(97))
                // Arched door cut from the base.
                ctx.lineTo(X(58), Y(97))
                ctx.lineTo(X(58), Y(70))
                ctx.quadraticCurveTo(X(50), Y(62), X(42), Y(70))
                ctx.lineTo(X(42), Y(97))
                ctx.closePath()
                ctx.fill()
                ctx.stroke()

                // Portrait windows and a small gable light.
                ctx.globalCompositeOperation = "destination-out"
                punchRoundRect(ctx, X(23), Y(50), 11.5 * s, 16 * s, 2.4 * s)
                punchRoundRect(ctx, X(65.5), Y(50), 11.5 * s, 16 * s, 2.4 * s)
                ctx.beginPath()
                ctx.arc(X(50), Y(26.5), 4.6 * s, 0, Math.PI * 2)
                ctx.fill()
                ctx.globalCompositeOperation = "source-over"
            }

            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    // Notification icon watermark (drawn white for contrast on tinted cover).
    Image {
        id: iconWatermark
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.right
        width: height
        opacity: cover.showingFavorites && cover.watermarkOn ? 0.34 : 0.22
        visible: (cover.showingNotification && cover.notificationIcon.length > 0)
                 || (cover.showingFavorites && cover.favoriteWatermarkPath.length > 0)
        source: {
            var path = cover.showingNotification ? cover.notificationIcon : cover.favoriteWatermarkPath
            if (!path || path.length === 0)
                return ""
            if (path.indexOf("http://") === 0 || path.indexOf("https://") === 0
                    || path.indexOf("file://") === 0)
                return path
            return "file://" + path
        }
        fillMode: Image.PreserveAspectFit
        z: 0
    }

    // Idle status
    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.paddingLarge * 2
        spacing: Theme.paddingSmall
        z: 1
        visible: !cover.showingNotification && !cover.showingFavorites

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            truncationMode: TruncationMode.Fade
            color: "white"
            text: hassClient && hassClient.instanceName.length > 0
                  ? hassClient.instanceName
                  : "Helmsman"
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: "#CCFFFFFF"
            font.pixelSize: Theme.fontSizeExtraSmall
            text: {
                if (!hassClient)
                    return ""
                if (hassClient.loggedIn) {
                    if (hassClient.internalUrl.length > 0)
                        return hassClient.usingInternalUrl ? "Internal" : "External"
                    return "Connected"
                }
                if (hassClient.connected)
                    return "Connected"
                return "Not connected"
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            truncationMode: TruncationMode.Fade
            color: "#B3FFFFFF"
            font.pixelSize: Theme.fontSizeTiny
            visible: hassClient && hassClient.host.length > 0
            text: hassClient ? hassClient.host : ""
        }
    }

    // Latest notification content
    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.paddingMedium * 2
        spacing: Theme.paddingSmall
        z: 1
        visible: cover.showingNotification

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: "white"
            text: cover.notificationTitle
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            visible: cover.notificationTitle.length > 0
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            color: "#F2FFFFFF"
            text: cover.notificationBody
            font.pixelSize: Theme.fontSizeExtraSmall
            visible: cover.notificationBody.length > 0
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: "#E6FFFFFF"
            font.pixelSize: Theme.fontSizeTiny
            font.bold: true
            visible: cover.notificationCount > 1
            text: cover.notificationCount === 2
                  ? "+ 1 notification"
                  : ("+ " + (cover.notificationCount - 1) + " notifications")
        }
    }

    Column {
        id: favoritesColumn
        visible: cover.showingFavorites
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Theme.paddingMedium
        anchors.leftMargin: Theme.paddingSmall
        anchors.rightMargin: Theme.paddingSmall
        anchors.bottomMargin: Theme.itemSizeSmall
        spacing: Theme.paddingSmall
        z: 1

        // One favorite: name in the middle, action is the left CoverAction.
        Column {
            visible: cover.pageEntities.length === 1
            width: parent.width
            spacing: Theme.paddingSmall

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: "white"
                font.pixelSize: Theme.fontSizeMedium
                font.bold: cover.favoriteEmphasized(cover.leftEntity)
                text: cover.favoriteName(cover.leftEntity)
            }

            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                color: "#CCFFFFFF"
                font.pixelSize: Theme.fontSizeSmall
                visible: cover.favoriteStateLabel(cover.leftEntity).length > 0
                text: cover.favoriteStateLabel(cover.leftEntity)
            }
        }

        // Two favorites: columns sit above the left/right CoverAction buttons.
        Row {
            visible: cover.pageEntities.length >= 2
            width: parent.width
            spacing: Theme.paddingSmall

            Repeater {
                model: cover.pageEntities
                delegate: Column {
                    width: (favoritesColumn.width - Theme.paddingSmall) / 2
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        color: "white"
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: cover.favoriteEmphasized(modelData)
                        text: cover.favoriteName(modelData)
                    }

                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        color: "#CCFFFFFF"
                        font.pixelSize: Theme.fontSizeTiny
                        visible: cover.favoriteStateLabel(modelData).length > 0
                        text: cover.favoriteStateLabel(modelData)
                    }
                }
            }
        }

        Item {
            width: 1
            height: Theme.paddingSmall
            visible: cover.pageCount > 1
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: cover.pageCount > 1
            color: "#B3FFFFFF"
            font.pixelSize: Theme.fontSizeTiny
            text: (cover.coverPage + 1) + " / " + cover.pageCount
        }
    }

    CoverActionList {
        enabled: cover.showingFavorites && cover.pageEntities.length >= 2
                 && (cover.leftActionEnabled || cover.rightActionEnabled) && !cover.coverActionOdd
        CoverAction {
            iconSource: cover.leftToggleIcon
            onTriggered: cover.toggleFavorite(cover.leftEntity)
        }
        CoverAction {
            iconSource: cover.rightToggleIcon
            onTriggered: cover.toggleFavorite(cover.rightEntity)
        }
    }

    CoverActionList {
        enabled: cover.showingFavorites && cover.pageEntities.length >= 2
                 && (cover.leftActionEnabled || cover.rightActionEnabled) && cover.coverActionOdd
        CoverAction {
            iconSource: cover.leftToggleIcon
            onTriggered: cover.toggleFavorite(cover.leftEntity)
        }
        CoverAction {
            iconSource: cover.rightToggleIcon
            onTriggered: cover.toggleFavorite(cover.rightEntity)
        }
    }

    CoverActionList {
        enabled: cover.showingFavorites && cover.pageEntities.length === 1 && cover.pageCount > 1 && !cover.coverActionOdd
        CoverAction {
            iconSource: cover.leftToggleIcon
            onTriggered: cover.toggleFavorite(cover.leftEntity)
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: cover.nextCoverPage()
        }
    }

    CoverActionList {
        enabled: cover.showingFavorites && cover.pageEntities.length === 1 && cover.pageCount > 1 && cover.coverActionOdd
        CoverAction {
            iconSource: cover.leftToggleIcon
            onTriggered: cover.toggleFavorite(cover.leftEntity)
        }
        CoverAction {
            iconSource: "image://theme/icon-cover-next"
            onTriggered: cover.nextCoverPage()
        }
    }

    CoverActionList {
        enabled: cover.showingFavorites && cover.pageEntities.length === 1 && cover.pageCount === 1
                 && cover.leftActionEnabled && !cover.coverActionOdd
        CoverAction {
            iconSource: cover.leftToggleIcon
            onTriggered: cover.toggleFavorite(cover.leftEntity)
        }
    }

    CoverActionList {
        enabled: cover.showingFavorites && cover.pageEntities.length === 1 && cover.pageCount === 1
                 && cover.leftActionEnabled && cover.coverActionOdd
        CoverAction {
            iconSource: cover.leftToggleIcon
            onTriggered: cover.toggleFavorite(cover.leftEntity)
        }
    }
}
