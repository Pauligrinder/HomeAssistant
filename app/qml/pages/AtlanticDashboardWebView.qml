import QtQuick 2.6
import Sailfish.Silica 1.0
import org.wpewebkit.qtwpe 1.0

Item {
    id: root
    property alias url: view.url
    property bool loading: false
    property int loadProgress: 0
    property bool loaded: false
    property bool _loggedViewport: false
    property int _probeHits: 0

    // WPE's built-in UA is desktop Safari/Linux (no "Mobile"). Atlantic's
    // own browser sends this phone WebKit UA; Helmsman must set it after
    // the WK view exists (setUserAgent is Q_INVOKABLE, not a QML property).
    readonly property string mobileUserAgent:
        "Mozilla/5.0 (Linux; Android 14; Mobile; SailfishOS) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 "
        + "Helmsman/1.0 Mobile Safari/605.1.15"
    // Theme.pixelRatio maps CSS px to the panel. 1.2 makes Lovelace a bit
    // larger than 1:1 physical pixels without dropping out of the phone layout.
    readonly property real contentScale: Math.max(Theme.pixelRatio, 1.0) * 1.2

    function runJavaScript(script, ok, fail) {
        // Sailfish.WebView evaluates the argument as a function body, so
        // callers start with `return ...`. WPE evaluates a script instead.
        var wrapped = "(function(){" + script + "})()"
        view.runJavaScript(wrapped, function(result) {
            if (typeof ok !== "function")
                return
            ok(root._coerceResult(result))
        })
    }

    function _coerceResult(result) {
        if (result === undefined || result === null)
            return ""
        var value = typeof result === "string" ? result : String(result)
        if (value.length >= 2 && value.charAt(0) === "\"" && value.charAt(value.length - 1) === "\"") {
            try {
                return JSON.parse(value)
            } catch (e) {
            }
        }
        return value
    }

    function _applyMobileChrome() {
        if (typeof view.setUserAgent === "function")
            view.setUserAgent(root.mobileUserAgent)
        if (typeof view.setDeviceScaleFactor === "function" && root.contentScale > 0)
            view.setDeviceScaleFactor(root.contentScale)
    }

    function _mobileHintScript() {
        return "(function(){"
                + "var ua=" + JSON.stringify(root.mobileUserAgent) + ";"
                + "try{"
                + "  Object.defineProperty(Navigator.prototype,'userAgent',{configurable:true,get:function(){return ua;}});"
                + "  Object.defineProperty(Navigator.prototype,'maxTouchPoints',{configurable:true,get:function(){return 5;}});"
                + "  Object.defineProperty(Navigator.prototype,'platform',{configurable:true,get:function(){return 'Linux armv7l';}});"
                + "}catch(e){}"
                + "try{"
                + "  if(document.head){"
                + "    var m=document.querySelector('meta[name=viewport]');"
                + "    if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}"
                + "    m.setAttribute('content','width=device-width,initial-scale=1');"
                + "  }"
                + "}catch(e2){}"
                + "return JSON.stringify({"
                + "  ua:navigator.userAgent,"
                + "  w:window.innerWidth,"
                + "  h:window.innerHeight,"
                + "  dpr:window.devicePixelRatio"
                + "});"
                + "})()"
    }

    function _isRealPage() {
        var value = String(view.url)
        return value.length > 0 && value.indexOf("about:blank") < 0
    }

    function _markLoaded() {
        if (root.loaded || !root._isRealPage())
            return
        root.loaded = true
        root.loading = false
        jsProbe.stop()
        if (!root._loggedViewport) {
            root._loggedViewport = true
            view.runJavaScript(root._mobileHintScript(), function(result) {
                console.log("Helmsman: Atlantic viewport", result)
            })
        }
    }

    WPEView {
        id: view
        anchors.fill: parent
        Component.onCompleted: {
            root._applyMobileChrome()
            // Create the WK view before Home Assistant loads, so the
            // user-agent setter has a settings object to write to.
            if (!String(view.url) || String(view.url).indexOf("about:blank") === 0)
                view.url = "about:blank"
        }
        onWebViewCreated: root._applyMobileChrome()
        onLoadingChanged: {
            if (!root._isRealPage())
                return
            var st = (typeof loadRequest !== "undefined" && loadRequest)
                    ? loadRequest.status : -1
            // WPEQtView::LoadStatus: Started=0, Stopped=1, Succeeded=2, Failed=3
            if (st === 0 || st === WPEView.LoadStartedStatus) {
                root._applyMobileChrome()
                root.loading = true
                root.loaded = false
                root._loggedViewport = false
                root._probeHits = 0
                jsProbe.start()
                return
            }
            if (st === 2 || st === WPEView.LoadSucceededStatus
                    || st === 1 || st === WPEView.LoadStoppedStatus) {
                root._markLoaded()
                return
            }
            root.loading = false
        }
        onLoadProgressChanged: {
            if (!root._isRealPage())
                return
            var p = view.loadProgress
            root.loadProgress = (p >= 0 && p <= 1.0) ? Math.round(p * 100) : Math.round(p)
            if (root.loadProgress >= 100)
                root._markLoaded()
        }
        onUrlChanged: {
            if (root._isRealPage())
                jsProbe.start()
        }
    }

    Timer {
        id: jsProbe
        interval: 400
        repeat: true
        onTriggered: {
            if (root.loaded || !root._isRealPage()) {
                if (root.loaded)
                    stop()
                return
            }
            view.runJavaScript(root._mobileHintScript(), function(result) {
                var value = root._coerceResult(result)
                if (!(value && value.indexOf("\"ua\"") >= 0))
                    return
                root._probeHits += 1
                // Wait a couple of successful JS turns so about:blank → HA
                // does not mark the view loaded on the first empty document.
                if (root._probeHits >= 2)
                    root._markLoaded()
            })
        }
    }
}
