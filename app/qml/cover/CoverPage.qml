import QtQuick 2.6
import Sailfish.Silica 1.0

CoverBackground {
    id: cover
    property var hassClient
    property int notificationCount: 0
    property string notificationTitle: ""
    property string notificationBody: ""
    property string notificationColor: "#03A9F4"
    property string notificationIcon: ""
    property bool showingNotification: notificationCount > 0
            && (notificationTitle.length > 0 || notificationBody.length > 0)
    signal requestSettings

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
        visible: !cover.showingNotification
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
        opacity: 0.28
        visible: cover.showingNotification && cover.notificationIcon.length > 0
        source: {
            if (cover.notificationIcon.length === 0)
                return ""
            var path = cover.notificationIcon
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
        visible: !cover.showingNotification

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
                if (hassClient.loggedIn)
                    return hassClient.usingInternalUrl ? "Internal" : "External"
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

    CoverActionList {
        enabled: hassClient && hassClient.loggedIn
        CoverAction {
            // Bundled cog — theme has no settings-style cover icon.
            iconSource: Qt.resolvedUrl("icon-cover-settings.png")
            onTriggered: cover.requestSettings()
        }
    }
}
