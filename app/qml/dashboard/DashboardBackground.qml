import QtQuick 2.6
import Sailfish.Silica 1.0

// Lovelace view / dashboard background. Priority is resolved by the caller
// (view wins over dashboard). Supports the modern map form and the legacy
// CSS string form (… url("/local/…") …).
Item {
    id: root
    property var dashboard
    property var background: null
    // Flickable content height when attachment is scroll.
    property real contentHeight: height
    property real contentY: 0

    property string imageUrl: ""
    property string mediaPath: ""

    readonly property var parsed: root.parseBackground(root.background)
    readonly property real imageOpacity: {
        var o = root.parsed.opacity
        if (!isFinite(o))
            return 1
        if (o > 1)
            return Math.max(0, Math.min(1, o / 100))
        return Math.max(0, Math.min(1, o))
    }
    readonly property bool fixed: root.parsed.attachment !== "scroll"
    readonly property int fillMode: {
        if (root.tile)
            return Image.Tile
        var s = root.parsed.size
        if (s === "contain")
            return Image.PreserveAspectFit
        if (s === "auto")
            return Image.Pad
        return Image.PreserveAspectCrop // cover / fill view
    }
    readonly property bool tile: root.parsed.repeat === "repeat"
            || root.parsed.repeat === "repeat-x"
            || root.parsed.repeat === "repeat-y"
    // Phone camera uploads are often multi-megapixel. Decoding the full frame
    // as a GL texture hangs hybris the same way unscaled camera stills did.
    readonly property int maxSourcePx: {
        var edge = Math.max(Screen.width, Screen.height) * Theme.pixelRatio
        return Math.max(1, Math.min(1920, Math.round(edge * 1.25)))
    }

    visible: root.mediaPath.length > 0 || root.imageUrl.length > 0
    clip: true

    function parseBackground(bg) {
        var out = {
            "image": "",
            "opacity": 100,
            "size": "cover",
            "alignment": "center",
            "repeat": "no-repeat",
            "attachment": "fixed"
        }
        if (bg === undefined || bg === null || bg === "")
            return out
        if (typeof bg === "string") {
            var s = bg
            var urlMatch = s.match(/url\(\s*['"]?([^'")]+)['"]?\s*\)/i)
            if (urlMatch)
                out.image = urlMatch[1]
            if (/\bcover\b/i.test(s))
                out.size = "cover"
            else if (/\bcontain\b/i.test(s))
                out.size = "contain"
            if (/\bno-repeat\b/i.test(s))
                out.repeat = "no-repeat"
            else if (/\brepeat\b/i.test(s))
                out.repeat = "repeat"
            if (/\bfixed\b/i.test(s))
                out.attachment = "fixed"
            else if (/\bscroll\b/i.test(s))
                out.attachment = "scroll"
            if (/\btop\b/i.test(s) && /\bleft\b/i.test(s))
                out.alignment = "top left"
            else if (/\btop\b/i.test(s) && /\bright\b/i.test(s))
                out.alignment = "top right"
            else if (/\btop\b/i.test(s))
                out.alignment = "top center"
            else if (/\bbottom\b/i.test(s) && /\bleft\b/i.test(s))
                out.alignment = "bottom left"
            else if (/\bbottom\b/i.test(s) && /\bright\b/i.test(s))
                out.alignment = "bottom right"
            else if (/\bbottom\b/i.test(s))
                out.alignment = "bottom center"
            else if (/\bleft\b/i.test(s))
                out.alignment = "center left"
            else if (/\bright\b/i.test(s))
                out.alignment = "center right"
            return out
        }
        if (typeof bg === "object") {
            if (bg.image !== undefined && bg.image !== null)
                out.image = bg.image
            if (bg.opacity !== undefined && bg.opacity !== null)
                out.opacity = Number(bg.opacity)
            if (bg.size)
                out.size = String(bg.size)
            if (bg.alignment)
                out.alignment = String(bg.alignment).toLowerCase()
            if (bg.repeat)
                out.repeat = String(bg.repeat).toLowerCase()
            if (bg.attachment)
                out.attachment = String(bg.attachment).toLowerCase()
        }
        return out
    }

    function resolvePath() {
        if (!dashboard)
            return ""
        var raw = root.parsed.image
        if (raw === undefined || raw === null || raw === "")
            return ""
        return dashboard.mediaPathOf(raw)
    }

    function refreshSource() {
        var path = root.resolvePath()
        root.mediaPath = path
        root.imageUrl = ""
        if (!dashboard || !path.length)
            return
        var cached = dashboard.cachedMediaUrl(path)
        if (cached && cached.length)
            root.imageUrl = cached
        else
            dashboard.prefetchMedia(path)
    }

    onBackgroundChanged: root.refreshSource()
    onDashboardChanged: root.refreshSource()
    Component.onCompleted: root.refreshSource()

    Connections {
        target: root.dashboard
        onMediaCached: {
            if (path === root.mediaPath)
                root.imageUrl = fileUrl
        }
    }

    // One Image: three copies of a multi-megapixel decode competed for GL.
    Image {
        id: picture
        width: parent.width
        height: root.fixed ? parent.height
                           : Math.max(parent.height, root.contentHeight)
        y: root.fixed ? 0 : -root.contentY
        source: root.imageUrl
        fillMode: root.fillMode
        opacity: root.imageOpacity
        asynchronous: true
        cache: true
        // Phone JPEGs store pixels sideways and tag EXIF Orientation; without
        // this they appear rotated 90° relative to the HA frontend.
        autoTransform: true
        sourceSize.width: root.maxSourcePx
        sourceSize.height: root.maxSourcePx
    }
}
