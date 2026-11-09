import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

Item {
    id: root
    property var dashboard
    property var hassClient
    property string entityId: ""
    property string cameraTitle: ""
    property var hostPage
    property bool active: false
    property bool allowFullscreen: true
    property bool fullscreenOpen: false
    property bool legacyPath: false
    property bool usingMjpegFallback: false
    property bool viewerInjected: false
    property bool viewerPlaying: false
    property bool initialized: false
    property string signedPath: ""
    property string requestKey: ""
    property string lastFailure: ""
    property int requestSerial: 0
    readonly property string instanceKey: Date.now().toString(36)
                                             + "-" + Math.random().toString(36).slice(2)
    readonly property string webViewEngine: hassClient
                                             ? String(hassClient.webViewEngineActive) : "stock"
    readonly property url viewerSource: {
        if (root.webViewEngine === "atlantic")
            return Qt.resolvedUrl("../../pages/AtlanticDashboardWebView.qml")
        if (root.webViewEngine === "next153")
            return Qt.resolvedUrl("../../pages/Next153DashboardWebView.qml")
        return Qt.resolvedUrl("../../pages/StockDashboardWebView.qml")
    }
    readonly property var viewer: viewerLoader.item
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property string clientId: {
        var _ = root.rev
        if (!dashboard || !root.entityId.length)
            return ""
        var value = dashboard.attribute(root.entityId, "client_id")
        if (!value)
            value = dashboard.attribute(root.entityId, "mqtt_client_id")
        return value ? String(value) : "frigate"
    }
    readonly property string frigateCameraName: {
        var _ = root.rev
        if (!dashboard || !root.entityId.length)
            return ""
        var value = dashboard.attribute(root.entityId, "camera_name")
        if (value)
            return String(value)
        var dot = root.entityId.indexOf(".")
        return dot >= 0 ? root.entityId.substring(dot + 1) : root.entityId
    }
    readonly property string baseUrl: hassClient ? String(hassClient.baseUrl) : ""
    readonly property string wsUrl: {
        if (!root.signedPath.length || !root.baseUrl.length)
            return ""
        if (root.signedPath.indexOf("https://") === 0)
            return "wss://" + root.signedPath.substring(8)
        if (root.signedPath.indexOf("http://") === 0)
            return "ws://" + root.signedPath.substring(7)
        var wsBase = root.baseUrl.replace(/\/+$/, "")
                .replace(/^http:/, "ws:").replace(/^https:/, "wss:")
        return wsBase + root.signedPath
    }
    function nextRequestKey() {
        root.requestSerial += 1
        return "frigate-stream-" + root.instanceKey + "-"
                + root.requestSerial + "-" + root.entityId
    }

    function requestPath(useLegacy, reason) {
        if (!root.active || !root.entityId.length || !dashboard || !dashboard.signFrigateStreamPath) {
            root.useFallback(reason || "Frigate stream path is unavailable")
            return
        }
        if (reason)
            root.lastFailure = reason
        viewerTimeout.stop()
        if (root.viewerInjected || root.signedPath.length) {
            if (root.viewer)
                root.viewer.url = "about:blank"
            viewerReload.restart()
        }
        root.legacyPath = useLegacy
        root.requestKey = root.nextRequestKey()
        root.signedPath = ""
        dashboard.signFrigateStreamPath(root.clientId, root.frigateCameraName,
                                        useLegacy, root.requestKey)
        signTimeout.restart()
    }

    function useFallback(reason) {
        signTimeout.stop()
        viewerTimeout.stop()
        viewerReload.stop()
        root.requestKey = ""
        root.signedPath = ""
        root.viewerInjected = false
        root.viewerPlaying = false
        root.lastFailure = reason || root.lastFailure || "go2rtc is unavailable"
        root.usingMjpegFallback = true
        if (root.viewer)
            root.viewer.url = "about:blank"
    }

    function resetViewer() {
        signTimeout.stop()
        viewerTimeout.stop()
        viewerReload.stop()
        root.requestKey = ""
        root.lastFailure = ""
        root.signedPath = ""
        root.viewerInjected = false
        root.viewerPlaying = false
        root.usingMjpegFallback = false
        if (root.viewer)
            root.viewer.url = "about:blank"
    }

    function startStream(forceRestart) {
        if (!root.active) {
            root.resetViewer()
            return
        }
        if (!root.viewer)
            return
        if (!forceRestart && (root.viewerPlaying || root.usingMjpegFallback
                              || root.signedPath.length || signTimeout.running
                              || viewerTimeout.running))
            return
        root.resetViewer()
        root.viewer.url = root.baseUrl
        root.requestPath(false)
    }

    function finishFullscreen() {
        resumeFullscreenTimer.start()
    }

    function resumeFullscreen() {
        if (root.viewerPlaying && root.viewer) {
            root.viewer.runJavaScript("return (function(){"
                                      + "var v=document.getElementById('v');"
                                      + "if(!v)return 'missing';"
                                      + "if(v.buffered.length)"
                                      + "v.currentTime=v.buffered.end(v.buffered.length-1)-0.1;"
                                      + "v.play();return 'resumed';})();")
        }
        root.fullscreenOpen = false
    }

    function handleViewerFailure(reason) {
        viewerTimeout.stop()
        if (reason === "MediaSource is not supported"
                || reason === "No supported MSE codecs") {
            root.useFallback(reason)
        } else if (!root.legacyPath) {
            root.requestPath(true, reason)
        } else {
            root.useFallback(reason)
        }
    }

    function openFullscreen() {
        if (!root.allowFullscreen || root.fullscreenOpen || !root.active
                || !pageStack || pageStack.busy)
            return
        if (root.viewerPlaying && root.viewer) {
            root.viewer.runJavaScript("return (function(){"
                                      + "var v=document.getElementById('v');"
                                      + "if(v)v.pause();return 'paused';})();")
        }
        root.fullscreenOpen = true
        pageStack.push(Qt.resolvedUrl("/usr/share/harbour-helmsman/qml/pages/FrigateStreamPage.qml"), {
                           hassClient: root.hassClient,
                           dashboard: root.dashboard,
                           entityId: root.entityId,
                           titleText: root.cameraTitle,
                           sourcePlayer: root
                       })
    }

    function playerDocument() {
        var script = "(function(){"
                + "var v=document.getElementById('v'),u=" + JSON.stringify(root.wsUrl) + ";"
                + "var title=function(s){document.title='frigate-'+s;};"
                + "if(!('MediaSource' in window)){title('error:MediaSource is not supported');return;}"
                + "var codecs=['avc1.42E01E','avc1.4D401E','avc1.64001E','avc1.640028',"
                + "'avc1.640029','avc1.64002A','avc1.640033','hvc1.1.6.L153.B0',"
                + "'mp4a.40.2','mp4a.40.5','flac','opus'].filter(function(c){"
                + "return MediaSource.isTypeSupported('video/mp4; codecs=\\\"'+c+'\\\"');}).join(',');"
                + "if(!codecs){title('error:No supported MSE codecs');return;}"
                + "var ms,ws,sb=null,q=[],offered=false;"
                + "try{ms=new MediaSource();ws=new WebSocket(u);}"
                + "catch(x){title('error:'+x.message);return;}"
                + "ws.binaryType='arraybuffer';v.src=URL.createObjectURL(ms);"
                + "function offer(){if(!offered&&ws.readyState===1&&ms.readyState==='open'){"
                + "offered=true;ws.send(JSON.stringify({type:'mse',value:codecs}));}}"
                + "ms.addEventListener('sourceopen',offer);ws.addEventListener('open',offer);"
                + "function append(){if(!sb||sb.updating||!q.length)return;"
                + "var size=0;for(var i=0;i<q.length;i++)size+=q[i].byteLength;"
                + "var data=new Uint8Array(size),offset=0;"
                + "for(var j=0;j<q.length;j++){data.set(new Uint8Array(q[j]),offset);offset+=q[j].byteLength;}"
                + "q=[];try{sb.appendBuffer(data.buffer);}catch(e){title('error:MSE buffer: '+e.message);}}"
                + "function maintainLiveBuffer(){if(!sb||sb.updating||!sb.buffered.length)return;"
                + "var end=sb.buffered.end(sb.buffered.length-1),start=Math.max(0,end-5),start0=sb.buffered.start(0);"
                + "if(start>start0){try{sb.remove(start0,start);"
                + "if(ms.setLiveSeekableRange)ms.setLiveSeekableRange(start,end);return;}"
                + "catch(e){title('error:MSE buffer trim: '+e.message);return;}}"
                + "if(v.currentTime<start)v.currentTime=start;"
                + "var gap=end-v.currentTime;v.playbackRate=gap>1.25?Math.min(1.5,gap):1;}"
                + "ws.onmessage=function(e){if(typeof e.data==='string'){"
                + "var m;try{m=JSON.parse(e.data);}catch(x){title('error:Invalid go2rtc response');return;}"
                + "if(m.type==='mse'){try{sb=ms.addSourceBuffer(m.value);sb.mode='segments';"
                + "sb.addEventListener('updateend',function(){maintainLiveBuffer();append();});append();}"
                + "catch(x){title('error:MSE codec: '+x.message);}}else if(m.type==='error'){"
                + "title('error:go2rtc: '+String(m.value||m.error||'stream error'));}}"
                + "else if(sb){q.push(e.data);append();}};"
                + "v.onplaying=function(){title('playing');};"
                + "v.onerror=function(){title('error:video playback error '+(v.error?v.error.code:''));};"
                + "ws.onerror=function(){title('error:WebSocket connection failed');};"
                + "ws.onclose=function(e){if(document.title!=='frigate-playing')"
                + "title('error:WebSocket closed '+e.code+(e.reason?': '+e.reason:''));};"
                + "title('connecting');"
                + "})();";
        return "<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
                + "<style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}"
                + "video{width:100%;height:100%;object-fit:contain;background:#000}</style></head>"
                + "<body><video id='v' autoplay muted playsinline></video><script>"
                + script + "</script></body></html>";
    }

    function injectViewer() {
        if (!root.active || !root.viewer || !root.signedPath.length || root.viewerInjected
                || String(root.viewer.url) === "about:blank" || root.viewer.loadProgress < 100)
            return
        root.viewerInjected = true
        viewerTimeout.restart()
        var html = root.playerDocument()
        root.viewer.runJavaScript("return (function(){document.open();document.write("
                             + JSON.stringify(html)
                             + ");document.close();return 'ok';})();")
    }

    function pollViewer() {
        if (!root.active || !root.viewerInjected || root.usingMjpegFallback)
            return
        root.viewer.runJavaScript("return document.title;", function(result) {
            var status = String(result || "")
            if (status === "frigate-playing") {
                root.viewerPlaying = true
                viewerTimeout.stop()
            } else if (status.indexOf("frigate-error:") === 0) {
                root.handleViewerFailure(status.substring("frigate-error:".length))
            }
        })
    }

    Connections {
        target: dashboard
        onFrigateStreamPathReady: {
            if (!root.active || key !== root.requestKey)
                return
            signTimeout.stop()
            root.signedPath = path
            root.viewerInjected = false
            root.viewerPlaying = false
            viewerTimeout.restart()
            root.injectViewer()
        }
        onFrigateStreamPathFailed: {
            if (!root.active || key !== root.requestKey)
                return
            signTimeout.stop()
            if (!root.legacyPath)
                root.requestPath(true, message)
            else
                root.useFallback(message || "Home Assistant could not sign the Frigate MSE path")
        }
    }

    onActiveChanged: {
        if (root.initialized)
            root.startStream()
    }
    onFullscreenOpenChanged: {
        if (root.fullscreenOpen)
            resumeFullscreenTimer.stop()
    }
    onEntityIdChanged: {
        if (root.initialized)
            root.startStream(true)
    }
    onClientIdChanged: {
        if (root.initialized)
            root.startStream(true)
    }
    onFrigateCameraNameChanged: {
        if (root.initialized)
            root.startStream(true)
    }

    Component.onCompleted: {
        root.initialized = true
        root.startStream()
    }
    Component.onDestruction: root.resetViewer()

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Loader {
        id: viewerLoader
        anchors.fill: parent
        source: root.viewerSource
        active: root.active && !root.usingMjpegFallback
        visible: active
        onLoaded: root.startStream()
    }

    Connections {
        target: root.viewer
        onLoadProgressChanged: root.injectViewer()
    }

    Rectangle {
        anchors.fill: parent
        visible: root.active && !root.usingMjpegFallback && !root.viewerPlaying
        color: "black"
        z: 1
    }

    CameraStreamPlayer {
        anchors.fill: parent
        stream: dashboard ? dashboard.cameraStream : null
        entityId: root.entityId
        active: root.active && root.usingMjpegFallback
        visible: root.active && root.usingMjpegFallback
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.paddingSmall
        width: Math.min(modeLabel.implicitWidth, root.width - 4 * Theme.paddingSmall)
               + 2 * Theme.paddingSmall
        height: modeLabel.implicitHeight + Theme.paddingSmall
        radius: height / 2
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)
        visible: root.active && (root.viewerPlaying || root.usingMjpegFallback)
        z: 3

        Label {
            id: modeLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, root.width - 4 * Theme.paddingSmall)
            text: root.usingMjpegFallback
                  ? "MJPEG · " + root.lastFailure
                  : "go2rtc · MSE"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeTiny
            truncationMode: TruncationMode.Fade
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Medium
        running: root.active && !root.usingMjpegFallback && !root.viewerPlaying
        visible: running
        z: 2
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.active && root.allowFullscreen && !root.fullscreenOpen
        z: 4
        onClicked: root.openFullscreen()
    }

    Timer {
        id: signTimeout
        interval: 8000
        repeat: false
        onTriggered: {
            if (!root.legacyPath)
                root.requestPath(true, "Path signing timed out")
            else
                root.useFallback("Path signing timed out")
        }
    }

    Timer {
        id: viewerTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (!root.legacyPath)
                root.requestPath(true, "go2rtc stream timed out")
            else
                root.useFallback("go2rtc stream timed out")
        }
    }

    Timer {
        id: viewerReload
        interval: 100
        repeat: false
        onTriggered: {
            if (root.active && root.viewer && root.baseUrl.length)
                root.viewer.url = root.baseUrl
        }
    }

    Timer {
        id: resumeFullscreenTimer
        interval: 100
        repeat: true
        onTriggered: {
            if (!root.hostPage
                    || (root.hostPage.status === PageStatus.Active
                        && !root.hostPage.orientationTransitionRunning)) {
                stop()
                root.resumeFullscreen()
            }
        }
    }

    Timer {
        interval: 750
        repeat: true
        running: root.active && root.viewer && root.viewerInjected && !root.usingMjpegFallback
        onTriggered: root.pollViewer()
    }
}
