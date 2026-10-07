import QtQuick 2.6
import Sailfish.Silica 1.0

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
    // Not an alias: resume has to assign the inner source twice, which would
    // break a caller's binding if it wrote image.source directly.
    property url source
    property alias sourceSize: image.sourceSize
    property alias status: image.status
    property int fillMode: Image.PreserveAspectCrop
    property real cornerRadius: 0
    property bool roundTop: true
    property bool roundBottom: true
    // Kept across a resume reload so a card does not collapse while the
    // picture is decoded again.
    property real heldAspect: 0
    // Natural width/height of the loaded picture, 0 until it arrives. Callers
    // use it to give the picture the height Home Assistant would.
    readonly property real aspectRatio: heldAspect
    readonly property bool clipCorners: cornerRadius > 0 && width >= 1 && height >= 1
    // Set only after the picture has actually been on screen. The canvas
    // reports unavailable while it is first created, and the app becoming
    // active at launch is not a resume.
    property bool textureLost: false
    property bool canvasSeen: false
    property bool beenActive: false

    onSourceChanged: {
        resumeReload.pending = ""
        if (image)
            image.source = source
    }
    Component.onCompleted: {
        if (image && String(image.source) !== String(source))
            image.source = source
    }

    function reloadImage() {
        var url = String(source).length ? source : image.source
        if (!url || String(url).length === 0) {
            textureLost = false
            return
        }
        // Clearing and restoring in one turn never starts a new load: Image
        // keeps the previous request and stays blank.
        resumeReload.pending = url
        image.source = ""
        resumeReload.restart()
    }

    function noteImage() {
        if (image.status !== Image.Ready)
            return
        if (image.implicitHeight > 0)
            root.heldAspect = image.implicitWidth / image.implicitHeight
        clip.requestPaint()
    }

    Image {
        id: image
        anchors.fill: parent
        fillMode: root.fillMode
        asynchronous: true
        cache: true
        visible: !root.clipCorners
    }

    // Next tick, after source has actually become empty.
    Timer {
        id: resumeReload
        interval: 1
        property url pending
        onTriggered: {
            var url = pending
            pending = ""
            root.textureLost = false
            if (url && String(url).length && String(image.source).length === 0)
                image.source = url
        }
    }

    Connections {
        target: Qt.application
        onStateChanged: {
            if (Qt.application.state === Qt.ApplicationActive) {
                if (root.beenActive && root.textureLost)
                    root.reloadImage()
                else
                    root.textureLost = false
                root.beenActive = true
            } else if (root.beenActive) {
                root.textureLost = true
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        z: 2
        running: String(root.source).length > 0
                 && image.status !== Image.Ready
                 && image.status !== Image.Error
        visible: running
        size: Math.min(root.width, root.height) < Theme.itemSizeMedium
              ? BusyIndicatorSize.Small
              : BusyIndicatorSize.Medium
    }

    Canvas {
        id: clip
        anchors.fill: parent
        visible: root.clipCorners
        renderTarget: Canvas.Image
        renderStrategy: Canvas.Cooperative

        onPaint: {
            var ctx = getContext("2d")
            if (!root.clipCorners || image.status !== Image.Ready)
                return
            var iw = image.implicitWidth
            var ih = image.implicitHeight
            if (iw < 1 || ih < 1)
                return
            ctx.clearRect(0, 0, width, height)

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
            if (available) {
                if (!root.canvasSeen) {
                    root.canvasSeen = true
                    requestPaint()
                } else if (!root.textureLost) {
                    requestPaint()
                }
            } else if (root.canvasSeen) {
                root.textureLost = true
            }
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
        onStatusChanged: root.noteImage()
        onImplicitWidthChanged: root.noteImage()
        onImplicitHeightChanged: root.noteImage()
    }
}
