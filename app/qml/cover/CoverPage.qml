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

    // Default house watermark when idle.
    Item {
        id: houseWatermark
        anchors.centerIn: parent
        width: parent.width * 1.65
        height: width
        opacity: 0.22
        rotation: -32
        visible: !cover.showingNotification
        z: 0

        Canvas {
            id: homeCanvas
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                var w = width
                var h = height
                ctx.clearRect(0, 0, w, h)

                var cx = w * 0.5
                var cy = h * 0.52
                var s = Math.min(w, h) * 0.50

                ctx.fillStyle = "#FFFFFF"
                ctx.beginPath()
                // Roof
                ctx.moveTo(cx, cy - s * 0.95)
                ctx.lineTo(cx + s * 0.92, cy - s * 0.12)
                ctx.lineTo(cx - s * 0.92, cy - s * 0.12)
                ctx.closePath()
                ctx.fill()

                // Body
                ctx.beginPath()
                ctx.moveTo(cx - s * 0.72, cy - s * 0.05)
                ctx.lineTo(cx + s * 0.72, cy - s * 0.05)
                ctx.lineTo(cx + s * 0.72, cy + s * 0.85)
                ctx.lineTo(cx - s * 0.72, cy + s * 0.85)
                ctx.closePath()
                ctx.fill()

                // Door cut-out
                ctx.clearRect(cx - s * 0.16, cy + s * 0.25, s * 0.32, s * 0.60)
            }

            Component.onCompleted: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    // Notification icon watermark (drawn white for contrast on tinted cover).
    Image {
        id: iconWatermark
        anchors.centerIn: parent
        width: parent.width * 1.65
        height: width
        opacity: 0.28
        rotation: -32
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
