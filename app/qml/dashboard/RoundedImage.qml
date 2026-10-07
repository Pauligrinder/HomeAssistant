import QtQuick 2.6

// A picture clipped to the rounded corners of the card it sits in. Only the
// edges that touch the outside of the card are rounded, so a header keeps its
// square bottom and a footer its square top.
//
// Clipping is done in software. QtGraphicalEffects OpacityMask (and
// layer.enabled) allocate an OpenGL framebuffer, and on some hybris GPUs that
// framebuffer never completes. The native dashboard then never presents
// another frame and Sailfish reports the app as not responding.
Item {
    id: root
    property alias source: image.source
    property alias sourceSize: image.sourceSize
    property alias status: image.status
    property int fillMode: Image.PreserveAspectCrop
    property real cornerRadius: 0
    property bool roundTop: true
    property bool roundBottom: true
    // Natural width/height of the loaded picture, 0 until it arrives. Callers
    // use it to give the picture the height Home Assistant would.
    readonly property real aspectRatio: image.implicitHeight > 0
                                        ? image.implicitWidth / image.implicitHeight : 0
    readonly property bool clipCorners: cornerRadius > 0 && width >= 1 && height >= 1

    Image {
        id: image
        anchors.fill: parent
        fillMode: root.fillMode
        asynchronous: true
        visible: !root.clipCorners
    }

    Canvas {
        id: clip
        anchors.fill: parent
        visible: root.clipCorners
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!root.clipCorners || image.status !== Image.Ready)
                return
            var iw = image.implicitWidth
            var ih = image.implicitHeight
            if (iw < 1 || ih < 1)
                return

            var r = Math.min(root.cornerRadius, width / 2, height / 2)
            var tl = root.roundTop ? r : 0
            var tr = root.roundTop ? r : 0
            var br = root.roundBottom ? r : 0
            var bl = root.roundBottom ? r : 0
            ctx.save()
            ctx.beginPath()
            ctx.moveTo(tl, 0)
            ctx.lineTo(width - tr, 0)
            ctx.quadraticCurveTo(width, 0, width, tr)
            ctx.lineTo(width, height - br)
            ctx.quadraticCurveTo(width, height, width - br, height)
            ctx.lineTo(bl, height)
            ctx.quadraticCurveTo(0, height, 0, height - bl)
            ctx.lineTo(0, tl)
            ctx.quadraticCurveTo(0, 0, tl, 0)
            ctx.closePath()
            ctx.clip()

            if (root.fillMode === Image.PreserveAspectFit) {
                var fit = Math.min(width / iw, height / ih)
                var dw = iw * fit
                var dh = ih * fit
                ctx.drawImage(image, (width - dw) / 2, (height - dh) / 2, dw, dh)
            } else if (root.fillMode === Image.PreserveAspectCrop) {
                var crop = Math.max(width / iw, height / ih)
                var sw = width / crop
                var sh = height / crop
                ctx.drawImage(image,
                              (iw - sw) / 2, (ih - sh) / 2, sw, sh,
                              0, 0, width, height)
            } else {
                ctx.drawImage(image, 0, 0, width, height)
            }
            ctx.restore()
        }

        onAvailableChanged: {
            if (available)
                requestPaint()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    onClipCornersChanged: clip.requestPaint()
    onRoundTopChanged: clip.requestPaint()
    onRoundBottomChanged: clip.requestPaint()
    onFillModeChanged: clip.requestPaint()

    Connections {
        target: image
        onStatusChanged: clip.requestPaint()
    }
}
