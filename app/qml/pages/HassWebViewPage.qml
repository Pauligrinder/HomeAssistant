import QtQuick 2.6
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import "../components"

Page {
    id: page
    objectName: page.isHome ? "HomePage" : "HassWebViewPage"
    property var hassClient
    property string startPath: "/lovelace"
    property string ingressSession: ""
    property bool ingressCookieSet: false
    property bool chromeless: false
    property bool isHome: false
    property bool tokensInjected: false
    property bool bridgeInstalled: false
    property bool dashboardReady: false
    property bool webViewFailed: false
    property bool readyCheckRunning: false
    property int readyCheckAttempts: 0
    property bool resumeProbeRunning: false
    property int resumeDeadCount: 0
    property double lastBackgroundedAt: 0
    property bool appActive: Qt.application.active
    property bool capturingSnapshot: false
    property int snapshotRevision: 1
    property bool snapshotUsable: false
    property string lastLoadedBase: ""
    property bool filePickPending: false
    // WebViewPage is only a Page with this marker; WebView looks it up on
    // a parent so either Gecko stack can sit in the same Silica page.
    property int __sailfish_webviewpage
    readonly property var dashboardView: webViewLoader.item
    readonly property string webViewEngine: hassClient ? hassClient.webViewEngineActive : "stock"
    // Always use ImagePickerPage for <input type=file accept=image…>. Gecko
    // only opens the gallery when mimeType is exactly "image/*"; HA sends
    // "image/png, image/jpeg, image/gif" and the fallback ContentPicker is
    // blank. Atlantic has no chooser at all.
    readonly property bool nativeImagePick: true
    property color overlayBackgroundColor: page.fallbackOverlayBackground
    property color overlayTextColor: page.fallbackOverlayText
    readonly property color haDarkBackground: "#111111"
    readonly property color haDarkText: "#e1e1e1"
    readonly property color haLightBackground: "#fafafa"
    readonly property color haLightText: "#212121"
    readonly property color fallbackOverlayBackground: {
        // Atlantic has no Gecko chrome; the cutout strip must match Lovelace,
        // which is dark here. Sailfish light ambience would otherwise leave a
        // white band above the webview.
        if (page.webViewEngine === "atlantic")
            return page.haDarkBackground
        return Theme.colorScheme === Theme.LightOnDark
                ? page.haDarkBackground
                : page.haLightBackground
    }
    readonly property color fallbackOverlayText: {
        if (page.webViewEngine === "atlantic")
            return page.haDarkText
        return Theme.colorScheme === Theme.LightOnDark
                ? page.haDarkText
                : page.haLightText
    }
    readonly property bool needsIngressCookie: page.ingressSession.length > 0
            && String(page.startPath || "").indexOf("/api/hassio_ingress/") >= 0
    readonly property bool skipFrontendChrome: {
        if (page.chromeless || page.needsIngressCookie)
            return true
        var path = String(page.startPath || "")
        return path.indexOf("http://") === 0 || path.indexOf("https://") === 0
    }
    property string startUrl: {
        if (!hassClient || hassClient.baseUrl.length === 0)
            return ""
        if (page.needsIngressCookie && !page.ingressCookieSet)
            return page.instancePath("/")
        return page.instancePath(page.startPath || "/lovelace")
    }
    property string dashboardUrl: page.startUrl
    property int authHops: 0
    // Gecko already lays out below the punch-hole. Only Atlantic's WPE view
    // draws edge-to-edge in portrait.
    readonly property int topCutoutHeight: {
        if (page.webViewEngine !== "atlantic" || !page.isPortrait)
            return 0
        if (typeof Screen === "undefined" || !Screen.topCutout)
            return 0
        return Math.max(0, Screen.topCutout.height)
    }
    property string loadStatusText: {
        if (page.webViewFailed)
            return qsTr("Browser engine failed to load.")
        if (page.skipFrontendChrome)
            return qsTr("Loading…")
        if (!page.tokensInjected)
            return qsTr("Preparing session...")
        if (dashboardView && dashboardView.loading && dashboardView.loadProgress > 0)
            return qsTr("Loading dashboard… %1%").arg(dashboardView.loadProgress)
        if (page.readyCheckRunning)
            return qsTr("Loading dashboard…")
        return qsTr("Loading dashboard…")
    }
    // Leave the Silica edge-swipe free while the frontend can go back on its
    // own (settings subpages, add-on history). Pop the page only at the URL
    // this webview was opened with.
    property bool spaCanGoBack: false
    property bool holdBackOff: false
    readonly property bool startedAtConfig: page.isConfigHomePath(page.startPath)
    readonly property bool onConfigRoot: page.isConfigHomePath(dashboardView ? dashboardView.url : "")
    backNavigation: !page.isHome && !page.blockSilicaBack
    readonly property bool webHasHistory: page.spaCanGoBack || page.pathLeftStart
    readonly property bool pathLeftStart: {
        if (!dashboardView)
            return false
        return page.webPath(dashboardView.url) !== page.webPath(page.startPath)
    }
    readonly property bool blockSilicaBack: {
        if (!page.dashboardReady)
            return false
        if (page.startedAtConfig)
            return !page.onConfigRoot || page.holdBackOff
        return page.webHasHistory || page.holdBackOff
    }

    onOnConfigRootChanged: {
        if (!page.startedAtConfig)
            return
        if (!page.onConfigRoot) {
            page.holdBackOff = true
            historyReleaseTimer.stop()
            return
        }
        historyReleaseTimer.restart()
    }

    onWebHasHistoryChanged: {
        if (page.startedAtConfig)
            return
        if (page.webHasHistory) {
            page.holdBackOff = true
            historyReleaseTimer.stop()
            return
        }
        historyReleaseTimer.restart()
    }

    function jsString(value) {
        return JSON.stringify(value ? String(value) : "")
    }

    function webPath(value) {
        var s = String(value || "")
        if (s.indexOf("homeassistant://") === 0)
            s = "/" + s.substring(16)
        if (s.indexOf("http://") === 0 || s.indexOf("https://") === 0) {
            var slash = s.indexOf("/", s.indexOf("://") + 3)
            s = slash >= 0 ? s.substring(slash) : "/"
        }
        if (!s.length || s.charAt(0) !== "/")
            s = "/" + s
        var cut = s.indexOf("?")
        if (cut >= 0)
            s = s.substring(0, cut)
        cut = s.indexOf("#")
        if (cut >= 0)
            s = s.substring(0, cut)
        if (s.length > 1 && s.charAt(s.length - 1) === "/")
            s = s.substring(0, s.length - 1)
        return s
    }

    function isConfigHomePath(value) {
        var p = page.webPath(value)
        return p === "/config" || p === "/config/dashboard"
    }

    function runViewJavaScript(script, ok, fail) {
        if (!dashboardView)
            return
        if (typeof ok === "function" && typeof fail === "function")
            dashboardView.runJavaScript(script, ok, fail)
        else if (typeof ok === "function")
            dashboardView.runJavaScript(script, ok)
        else
            dashboardView.runJavaScript(script)
    }

    function instancePath(path) {
        var value = String(path || "")
        if (value.indexOf("http://") === 0 || value.indexOf("https://") === 0)
            return value
        if (value.indexOf("homeassistant://") === 0)
            value = "/" + value.substring(16)
        var base = hassClient.baseUrl
        if (!base || base.length === 0)
            return ""
        if (base.charAt(base.length - 1) === "/")
            base = base.substring(0, base.length - 1)
        if (!value.length || value.charAt(0) !== "/")
            value = "/" + value
        return base + value
    }

    function applyIngressCookie(done) {
        var session = page.ingressSession || ""
        if (!session.length) {
            if (typeof done === "function")
                done(false)
            return
        }
        var secure = String(hassClient.baseUrl).indexOf("https://") === 0
                ? ";Secure" : ""
        var script = "return (function(){"
                + "try{"
                + "  document.cookie='ingress_session='+" + page.jsString(session)
                + "+';path=/api/hassio_ingress/;SameSite=Strict" + secure + "';"
                + "  return 'ok';"
                + "}catch(e){return 'fail';}"
                + "})();"
        page.runViewJavaScript(
                    script,
                    function(result) {
                        if (typeof done === "function")
                            done(result === "ok")
                    },
                    function() {
                        if (typeof done === "function")
                            done(false)
                    })
    }

    function openChromelessTarget() {
        if (!dashboardView)
            return
        var target = page.instancePath(page.startPath)
        if (!target.length)
            return
        dashboardView.url = target
    }

    function isHassFrontendUrl(value) {
        var url = String(value)
        var base = hassClient.baseUrl
        if (!base || url.length === 0 || url.indexOf(base) !== 0)
            return false
        if (url.indexOf("/auth/authorize") >= 0 || url.indexOf("/auth/login_flow") >= 0)
            return false
        if (url.indexOf("/_my_redirect/companion_app") >= 0)
            return false
        return true
    }

    function openSettings() {
        pageStack.push(Qt.resolvedUrl("SettingsPage.qml"), { hassClient: hassClient })
    }

    function openFrontendAfterAuth() {
        if (page.authHops >= 2) {
            console.log("Helmsman: auth redirect loop — showing webview")
            page.finishDashboardLoad()
            return
        }
        page.authHops += 1
        if (dashboardView)
            dashboardView.url = page.dashboardUrl
    }

    function resetDashboardState() {
        page.dashboardReady = false
        page.tokensInjected = false
        page.bridgeInstalled = false
        page.readyCheckRunning = false
        page.readyCheckAttempts = 0
        page.authHops = 0
        page.resumeProbeRunning = false
        page.resumeDeadCount = 0
        resumeProbeTimer.stop()
        resumeProbeStartTimer.stop()
        openedPathTimer.stop()
        snapshotDelayTimer.stop()
        page.overlayBackgroundColor = page.fallbackOverlayBackground
        page.overlayTextColor = page.fallbackOverlayText
        readyCheckTimer.stop()
        page.lastLoadedBase = ""
        page.ingressCookieSet = false
        page.spaCanGoBack = false
    }

    function applyLoadingTheme(raw) {
        if (!raw || raw.length === 0)
            return
        var colors
        try {
            colors = JSON.parse(raw)
        } catch (e) {
            return
        }
        if (colors.bg)
            page.overlayBackgroundColor = colors.bg
        if (colors.fg)
            page.overlayTextColor = colors.fg
    }

    function updateLoadingThemeFromWebView() {
        var script = "return (function(){"
                + "try {"
                + "  var root=document.documentElement;"
                + "  var bg=getComputedStyle(root).getPropertyValue('--primary-background-color').trim();"
                + "  var fg=getComputedStyle(root).getPropertyValue('--primary-text-color').trim();"
                + "  if(bg&&fg)return JSON.stringify({bg:bg,fg:fg});"
                + "} catch (e) {}"
                + "try {"
                + "  var dark=window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches;"
                + "  var raw=localStorage.getItem('selectedThemeSettings')||localStorage.getItem('selectedTheme');"
                + "  if(raw){"
                + "    var s=JSON.parse(raw);"
                + "    if(s&&s.dark===true)dark=true;"
                + "    else if(s&&s.dark===false)dark=false;"
                + "  }"
                + "  if(dark)return JSON.stringify({bg:'#111111',fg:'#e1e1e1'});"
                + "} catch (e2) {}"
                + "return JSON.stringify({bg:'#fafafa',fg:'#212121'});"
                + "})();"

        page.runViewJavaScript(
                    script,
                    function(result) {
                        page.applyLoadingTheme(result)
                    },
                    function(error) {
                        console.log("Loading theme detection failed:", error)
                    })
    }

    function reloadDashboard() {
        page.resetDashboardState()
        if (dashboardView)
            dashboardView.url = page.startUrl
    }

    // Keep the live Lovelace document warm across cover/background. Never
    // hide it for a probe — only reload if the document is confirmed dead.
    function onAppForegrounded() {
        if (!hassClient || !hassClient.loggedIn)
            return
        if (!page.dashboardReady || page.readyCheckRunning)
            return
        if (page.status !== PageStatus.Active || !Qt.application.active)
            return

        if (page.skipFrontendChrome) {
            if (page.needsIngressCookie)
                page.applyIngressCookie()
            return
        }

        page.ensureSessionFresh()

        var awayMs = page.lastBackgroundedAt > 0
                ? (Date.now() - page.lastBackgroundedAt)
                : 0
        // Short cover / app switches keep the HA websocket alive. Probing
        // gecko while it is still waking is what triggered the overlay.
        if (awayMs < 60000)
            return

        page.beginResumeProbe()
    }

    function ensureSessionFresh() {
        var expires = hassClient.accessExpiresAtMs
        if (expires > 0 && (expires - Date.now()) < 120 * 1000) {
            hassClient.refreshAccessToken()
            return
        }
        page.injectSessionAndBridge(true)
    }

    function beginResumeProbe() {
        if (page.resumeProbeRunning)
            return
        page.resumeProbeRunning = true
        page.resumeDeadCount = 0
        // Let gecko become active again before the first JS call.
        resumeProbeStartTimer.start()
    }

    function finishResumeProbe(ok) {
        resumeProbeTimer.stop()
        resumeProbeStartTimer.stop()
        page.resumeProbeRunning = false
        page.resumeDeadCount = 0
        if (ok)
            return
        console.log("Helmsman: warm resume failed — reloading dashboard")
        page.reloadDashboard()
    }

    function runResumeProbe() {
        if (!page.resumeProbeRunning)
            return
        if (page.status !== PageStatus.Active || !Qt.application.active)
            return

        var script = "return (function(){"
                + "try {"
                + "  var ha=document.querySelector('home-assistant');"
                + "  if(!ha||!ha.hass||!ha.hass.connection)return 'dead';"
                + "  if(ha.hass.connection.connected){"
                + "    var main=ha.shadowRoot&&ha.shadowRoot.querySelector('home-assistant-main');"
                + "    if(main||document.querySelector('hui-root'))return 'ready';"
                + "    return 'wait';"
                + "  }"
                + "  try {"
                + "    if(typeof ha.hass.connection.reconnect==='function')"
                + "      ha.hass.connection.reconnect();"
                + "  } catch (e) {}"
                + "  return 'reconnecting';"
                + "} catch (e2) { return 'dead'; }"
                + "})();"

        page.runViewJavaScript(
                    script,
                    function(result) {
                        if (!page.resumeProbeRunning)
                            return
                        if (result === "ready") {
                            page.finishResumeProbe(true)
                            return
                        }
                        if (result === "dead") {
                            page.resumeDeadCount += 1
                            if (page.resumeDeadCount >= 20)
                                page.finishResumeProbe(false)
                            return
                        }
                        // wait / reconnecting: keep the live view, do not reload.
                        page.resumeDeadCount = 0
                    },
                    function(error) {
                        // Compositor often rejects JS while waking; never treat
                        // that as a dead document.
                        console.log("Helmsman: resume probe JS failed:", error)
                    })
    }

    function finishDashboardLoad() {
        readyCheckTimer.stop()
        page.readyCheckRunning = false
        page.dashboardReady = true
        page.pollBridge()
        page.refreshWebHistory()
        // Sensor startup waits for this: its webhook calls must not compete
        // with the dashboard for the UI thread.
        // Overflow WebView is not the native home screen; sensors already
        // start from the native dashboard.
        if (hassClient && page.isHome)
            hassClient.notifyDashboardReady()
        // Navigate only after the dashboard is on screen. Doing this during
        // the ready-check hangs Gecko on external/reverse-proxy origins.
        openedPathTimer.restart()
    }

    function navigateOpenedPathOnce() {
        if (page.skipFrontendChrome)
            return
        if (page.isHome) {
            page.navigateDefaultPanelOnce()
            return
        }
        var want = page.startPath || ""
        if (!want.length)
            return
        var script = "return (function(){"
                + "try{"
                + "  var want=" + page.jsString(want) + ";"
                + "  if(want.charAt(0)!=='/')want='/'+want;"
                + "  var cur=location.pathname||'/';"
                + "  if(cur.length>1&&cur.charAt(cur.length-1)==='/')cur=cur.slice(0,-1);"
                + "  var dest=want;"
                + "  if(dest.length>1&&dest.charAt(dest.length-1)==='/')dest=dest.slice(0,-1);"
                + "  if(cur===dest||cur.indexOf(dest+'/')===0)return 'ok';"
                + "  history.replaceState(history.state,'',want);"
                + "  window.dispatchEvent(new CustomEvent('location-changed',{detail:{replace:true},bubbles:true,composed:true}));"
                + "  return 'moved';"
                + "}catch(e){return 'skip';}"
                + "})();"
        page.runViewJavaScript(script)
    }

    function navigateDefaultPanelOnce() {
        var script = "return (function(){"
                + "try{"
                + "  var ha=document.querySelector('home-assistant');"
                + "  if(!ha||!ha.hass||!ha.hass.panels)return 'skip';"
                + "  var hass=ha.hass;"
                + "  var def='';"
                + "  if(hass.userData&&hass.userData.default_panel)def=hass.userData.default_panel;"
                + "  else if(hass.systemData&&hass.systemData.default_panel)def=hass.systemData.default_panel;"
                + "  else{try{var raw=localStorage.getItem('defaultPanel');if(raw)def=JSON.parse(raw);}catch(e1){}}"
                + "  if(!def)def=(hass.panels.home)?'home':'lovelace';"
                + "  if(def==='lovelace'&&hass.panels.home&&!(hass.panels.lovelace&&hass.panels.lovelace.config))def='home';"
                + "  if(!def||!hass.panels[def])return 'skip';"
                + "  var want='/'+def;"
                + "  var cur=location.pathname||'/';"
                + "  if(cur.length>1&&cur.charAt(cur.length-1)==='/')cur=cur.slice(0,-1);"
                + "  if(cur===want||cur.indexOf(want+'/')===0)return 'ok';"
                + "  history.replaceState(history.state,'',want);"
                + "  window.dispatchEvent(new CustomEvent('location-changed',{detail:{replace:true},bubbles:true,composed:true}));"
                + "  return 'moved';"
                + "}catch(e){return 'skip';}"
                + "})();"

        page.runViewJavaScript(
                    script,
                    function() { snapshotDelayTimer.restart() },
                    function() { snapshotDelayTimer.restart() })
    }

    function refreshSnapshotState() {
        // The PNG is cleared on sign-out. Show it whenever it exists so the
        // blur still appears after an internal↔external (or host:port) change.
        page.snapshotUsable = !!(hassClient
                                 && hassClient.dashboardSnapshotPath
                                 && hassClient.dashboardSnapshotMatches(hassClient.baseUrl))
        page.snapshotRevision += 1
    }

    function captureDashboardSnapshot() {
        if (page.capturingSnapshot || !page.dashboardReady)
            return
        if (!hassClient || !hassClient.loggedIn)
            return
        if (!dashboardView || dashboardView.width < 8 || dashboardView.height < 8)
            return

        page.capturingSnapshot = true
        dashboardView.grabToImage(function(result) {
            page.capturingSnapshot = false
            if (!result)
                return
            var path = hassClient.dashboardSnapshotPath
            if (!result.saveToFile(path)) {
                console.log("Helmsman: failed to save dashboard snapshot")
                return
            }
            hassClient.rememberDashboardSnapshot(hassClient.baseUrl)
            page.refreshSnapshotState()
        }, Qt.size(Math.max(48, Math.round(dashboardView.width / 6)),
                   Math.max(48, Math.round(dashboardView.height / 6))))
    }

    function beginReadyCheck() {
        if (page.dashboardReady || page.readyCheckRunning)
            return
        page.updateLoadingThemeFromWebView()
        page.readyCheckRunning = true
        page.readyCheckAttempts = 0
        readyCheckTimer.start()
        page.checkDashboardReady()
    }

    function checkDashboardReady() {
        if (!page.readyCheckRunning)
            return

        var script = "return (function(){"
                + "try{window.__helmsmanAttachExternal&&window.__helmsmanAttachExternal();}catch(e){}"
                + "var ha=document.querySelector('home-assistant');"
                + "if(!ha||!ha.hass||!ha.hass.connection||!ha.hass.connection.connected)return 'wait';"
                + "var main=ha.shadowRoot&&ha.shadowRoot.querySelector('home-assistant-main');"
                + "if(main||document.querySelector('hui-root'))return 'ready';"
                + "return 'wait';"
                + "})();"

        page.runViewJavaScript(
                    script,
                    function(result) {
                        if (!page.readyCheckRunning)
                            return
                        if (result === "ready") {
                            page.finishDashboardLoad()
                            return
                        }
                        page.readyCheckAttempts += 1
                        if (page.readyCheckAttempts >= 30)
                            page.finishDashboardLoad()
                    },
                    function(error) {
                        console.log("Dashboard ready check failed:", error)
                        page.readyCheckAttempts += 1
                        if (page.readyCheckAttempts >= 30)
                            page.finishDashboardLoad()
                    })
    }

    function jsQuote(s) {
        return "'" + String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"
    }

    function settingsExitJs() {
        // Patch ha-config-navigation.pages so "Back to dashboard" is part of
        // the same list Home Assistant renders. Re-splicing on poll or scroll
        // briefly shows a duplicate row under Companion app.
        if (!hassClient || !hassClient.nativeDashboardEnabled || page.isHome)
            return ""
        var backName = qsTr("Back to dashboard")
        var backDesc = qsTr("Return to the native dashboard")
        return "window.__helmsmanInstallSettingsExit=function(){"
                + "try{"
                + "  var backName=" + jsQuote(backName) + ";"
                + "  var backDesc=" + jsQuote(backDesc) + ";"
                + "  var fire=function(){"
                + "    var now=Date.now();"
                + "    if(window.__helmsmanBackAt&&now-window.__helmsmanBackAt<1000)return;"
                + "    window.__helmsmanBackAt=now;"
                + "    try{"
                + "      if(String(location.hash).indexOf('helmsman-back-dashboard')>=0)"
                + "        history.replaceState(history.state,'',location.pathname+location.search);"
                + "    }catch(e3){}"
                + "    window.__helmsmanQueue=window.__helmsmanQueue||[];"
                + "    window.__helmsmanQueue.push({type:'externalBus',opts:JSON.stringify({type:'helmsman/back_dashboard'})});"
                + "  };"
                + "  if(!window.__helmsmanBackHook){"
                + "    window.__helmsmanBackHook=true;"
                + "    document.addEventListener('click',function(ev){"
                + "      var path=ev.composedPath?ev.composedPath():[];"
                + "      for(var i=0;i<path.length;i++){"
                + "        var n=path[i];"
                + "        if(!n)continue;"
                + "        var href='';"
                + "        if(n.getAttribute)href=n.getAttribute('href')||'';"
                + "        if(!href&&n.href)href=String(n.href);"
                + "        var txt=n.textContent?String(n.textContent):'';"
                + "        var tag=n.tagName?String(n.tagName).toLowerCase():'';"
                + "        var isItem=tag.indexOf('list-item')>=0;"
                + "        if(String(href).indexOf('helmsman-back-dashboard')>=0"
                + "            ||(isItem&&txt.indexOf(backDesc)>=0&&txt.length<160)){"
                + "          ev.preventDefault();"
                + "          if(ev.stopImmediatePropagation)ev.stopImmediatePropagation();"
                + "          else ev.stopPropagation();"
                + "          fire();return;"
                + "        }"
                + "      }"
                + "    },true);"
                + "  }"
                + "  var isRoot=function(){"
                + "    var loc=String(location.pathname||'');"
                + "    if(loc.length>1&&loc.charAt(loc.length-1)==='/')loc=loc.slice(0,-1);"
                + "    return loc==='/config'||loc==='/config/dashboard';"
                + "  };"
                + "  var isBack=function(p){"
                + "    if(!p)return false;"
                + "    if(p.__helmsman)return true;"
                + "    var path=String(p.path||'');"
                + "    if(path.indexOf('helmsman-back-dashboard')>=0)return true;"
                + "    return p.name===backName;"
                + "  };"
                + "  var backPage={path:'#helmsman-back-dashboard',name:backName,"
                + "    description:backDesc,"
                + "    iconPath:'M20,11V13H8L13.5,18.5L12.08,19.92L4.16,12L12.08,4.08L13.5,5.5L8,11H20Z',"
                + "    iconColor:'#B1345C',core:true,__helmsman:true};"
                + "  var withBack=function(pages){"
                + "    if(!pages||!pages.length)return pages;"
                + "    var out=[],idx=-1;"
                + "    for(var i=0;i<pages.length;i++){"
                + "      if(isBack(pages[i]))continue;"
                + "      if(pages[i]&&pages[i].path==='#external-app-configuration')idx=out.length;"
                + "      out.push(pages[i]);"
                + "    }"
                + "    if(idx>=0)out.splice(idx+1,0,backPage);"
                + "    return out;"
                + "  };"
                + "  var same=function(a,b){"
                + "    if(a===b)return true;"
                + "    if(!a||!b||a.length!==b.length)return false;"
                + "    for(var i=0;i<a.length;i++){"
                + "      if((a[i]&&a[i].path)!==(b[i]&&b[i].path))return false;"
                + "    }"
                + "    return true;"
                + "  };"
                + "  var patchNav=function(nav){"
                + "    if(!nav||nav.__helmsmanPatched)return !!nav;"
                + "    var held=withBack(nav.pages);"
                + "    nav.__helmsmanPatched=true;"
                + "    try{"
                + "      Object.defineProperty(nav,'pages',{"
                + "        configurable:true,enumerable:true,"
                + "        get:function(){return held;},"
                + "        set:function(v){"
                + "          var next=withBack(v);"
                + "          var changed=!same(held,next);"
                + "          held=next;"
                + "          if(changed){try{nav.requestUpdate();}catch(e1){}}"
                + "        }"
                + "      });"
                + "    }catch(e2){return false;}"
                + "    try{nav.requestUpdate();}catch(e5){}"
                + "    return true;"
                + "  };"
                + "  var findNavs=function(){"
                + "    var found=[];"
                + "    var walk=function(root){"
                + "      if(!root||!root.querySelectorAll)return;"
                + "      var navs=root.querySelectorAll('ha-config-navigation');"
                + "      for(var i=0;i<navs.length;i++)found.push(navs[i]);"
                + "      var all=root.querySelectorAll('*');"
                + "      for(var j=0;j<all.length;j++){if(all[j].shadowRoot)walk(all[j].shadowRoot);}"
                + "    };"
                + "    walk(document);"
                + "    var ha=document.querySelector('home-assistant');"
                + "    if(ha&&ha.shadowRoot)walk(ha.shadowRoot);"
                + "    return found;"
                + "  };"
                + "  var patchAll=function(){"
                + "    if(!isRoot())return false;"
                + "    var found=findNavs(),ok=false;"
                + "    for(var k=0;k<found.length;k++){"
                + "      var pages=found[k].pages,hasC=false;"
                + "      if(!pages)continue;"
                + "      for(var p=0;p<pages.length;p++){"
                + "        if(pages[p]&&pages[p].path==='#external-app-configuration')hasC=true;"
                + "      }"
                + "      if(hasC&&patchNav(found[k]))ok=true;"
                + "    }"
                + "    return ok;"
                + "  };"
                + "  if(!window.__helmsmanExitWatching){"
                + "    window.__helmsmanExitWatching=true;"
                + "    var start=function(){"
                + "      if(!isRoot())return;"
                + "      if(patchAll())return;"
                + "      if((window.__helmsmanExitTries||0)>20)return;"
                + "      window.__helmsmanExitTries=(window.__helmsmanExitTries||0)+1;"
                + "      setTimeout(start,300);"
                + "    };"
                + "    window.addEventListener('location-changed',function(){"
                + "      if(!isRoot())return;"
                + "      window.__helmsmanExitTries=0;"
                + "      start();"
                + "    });"
                + "    window.__helmsmanExitTries=0;"
                + "    start();"
                + "  }"
                + "}catch(e){}"
                + "};"
    }

    function filePickerHookJs() {
        // Home Assistant picture upload uses accept="image/png, image/jpeg,
        // image/gif". Gecko's PickerCreator only opens the gallery for
        // exactly "image/*"; anything else is ContentPickerPage, which is
        // blank without MediaIndexing. Rewrite first so the Sailfish
        // gallery is used. Atlantic has no PickerOpener, so those clicks
        // are turned into ImagePickerPage instead of a blank WPE chooser.
        return "window.__helmsmanInstallFilePicker=function(){"
                + "try{"
                + "  window.__helmsmanNativeImagePick="
                + (page.nativeImagePick ? "true" : "false") + ";"
                + "  window.__helmsmanApplyPickedFile=function(name,mime,b64){"
                + "    window.__helmsmanPickBusy=false;"
                + "    var input=window.__helmsmanPendingFileInput;"
                + "    window.__helmsmanPendingFileInput=null;"
                + "    if(!input)return 'no-input';"
                + "    try{"
                + "      var bin=atob(b64);"
                + "      var bytes=new Uint8Array(bin.length);"
                + "      for(var i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);"
                + "      var file=new File([bytes],name||'image.jpg',{type:mime||'image/jpeg'});"
                + "      var dt=new DataTransfer();"
                + "      dt.items.add(file);"
                + "      input.files=dt.files;"
                + "      input.dispatchEvent(new Event('change',{bubbles:true,composed:true}));"
                + "      return 'ok';"
                + "    }catch(e){return 'fail:'+e;}"
                + "  };"
                + "  window.__helmsmanCancelPickedFile=function(){"
                + "    window.__helmsmanPickBusy=false;"
                + "    window.__helmsmanPendingFileInput=null;"
                + "  };"
                + "  var wantsImage=function(input){"
                + "    if(!input||String(input.type).toLowerCase()!=='file')return false;"
                + "    var a=String(input.accept||'').toLowerCase();"
                + "    return a.indexOf('image')>=0||a.indexOf('.png')>=0||a.indexOf('.jpg')>=0"
                + "      ||a.indexOf('.jpeg')>=0||a.indexOf('.gif')>=0||a.indexOf('.webp')>=0;"
                + "  };"
                + "  var rewrite=function(input){"
                + "    if(wantsImage(input)&&String(input.accept)!=='image/*')"
                + "      input.accept='image/*';"
                + "  };"
                + "  var fileInputFromEvent=function(ev){"
                + "    var path=ev.composedPath?ev.composedPath():[];"
                + "    var found=null;"
                + "    for(var i=0;i<path.length;i++){"
                + "      var n=path[i];"
                + "      if(!n)continue;"
                + "      if(n.tagName==='INPUT'&&String(n.type).toLowerCase()==='file'){"
                + "        rewrite(n);"
                + "        if(wantsImage(n))found=found||n;"
                + "      }"
                + "      var scan=function(root){"
                + "        if(!root||!root.querySelectorAll)return;"
                + "        try{"
                + "          var ins=root.querySelectorAll('input[type=file]');"
                + "          for(var j=0;j<ins.length;j++){"
                + "            rewrite(ins[j]);"
                + "            if(wantsImage(ins[j]))found=found||ins[j];"
                + "          }"
                + "        }catch(e1){}"
                + "      };"
                + "      scan(n);"
                + "      if(n.shadowRoot)scan(n.shadowRoot);"
                + "    }"
                + "    return found;"
                + "  };"
                + "  if(!window.__helmsmanFilePickHook){"
                + "    window.__helmsmanFilePickHook=true;"
                + "    document.addEventListener('touchstart',function(ev){"
                + "      fileInputFromEvent(ev);"
                + "    },true);"
                + "    document.addEventListener('mousedown',function(ev){"
                + "      fileInputFromEvent(ev);"
                + "    },true);"
                + "    document.addEventListener('click',function(ev){"
                + "      var input=fileInputFromEvent(ev);"
                + "      if(!input||!window.__helmsmanNativeImagePick)return;"
                + "      ev.preventDefault();"
                + "      if(ev.stopImmediatePropagation)ev.stopImmediatePropagation();"
                + "      else ev.stopPropagation();"
                + "      if(window.__helmsmanPickBusy)return;"
                + "      window.__helmsmanPickBusy=true;"
                + "      window.__helmsmanPendingFileInput=input;"
                + "      window.__helmsmanQueue=window.__helmsmanQueue||[];"
                + "      window.__helmsmanQueue.push({type:'externalBus',"
                + "        opts:JSON.stringify({type:'helmsman/pick_image'})});"
                + "    },true);"
                + "  }"
                + "}catch(e){}"
                + "};"
    }

    function injectSessionAndBridge(silent) {
        if (!hassClient.accessToken || hassClient.accessToken.length === 0)
            return

        var expires = hassClient.accessExpiresAtMs > 0
                ? hassClient.accessExpiresAtMs
                : (Date.now() + 1800 * 1000)
        var expiresIn = Math.max(60, Math.floor((expires - Date.now()) / 1000))

        var script = "return (function(){"
                + "var origin=(typeof location!=='undefined'&&location.origin)?location.origin:"
                + page.jsString(hassClient.baseUrl) + ";"
                + "var tokens={"
                + "access_token:" + page.jsString(hassClient.accessToken) + ","
                + "expires_in:" + String(expiresIn) + ","
                + "token_type:'Bearer',"
                + "hassUrl:origin,"
                + "clientId:" + page.jsString(hassClient.authClientId) + ","
                + "expires:" + String(expires) + ","
                + "refresh_token:" + page.jsString(hassClient.refreshToken)
                + "};"
                + "try {"
                + "  localStorage.setItem('hassTokens', JSON.stringify(tokens));"
                + "  sessionStorage.setItem('hassTokens', JSON.stringify(tokens));"
                + "} catch (e) { return 'storage-error'; }"
                + "window.__helmsmanQueue = window.__helmsmanQueue || [];"
                + "window.externalApp = window.externalApp || {"
                + "  externalBus: function(message) {"
                + "    window.__helmsmanQueue.push({type:'externalBus', opts: typeof message === 'string' ? message : JSON.stringify(message || {})});"
                + "  }"
                + "};"
                + "window.__helmsmanAttachExternal = function() {"
                + "  var ha=document.querySelector('home-assistant');"
                + "  if(!ha||!ha.hass||!ha.hass.auth)return false;"
                + "  var existing=ha.hass.auth.external;"
                + "  if(existing&&!existing.__helmsman){"
                + "    if(existing.config)existing.config.hasSettingsScreen=true;"
                + "    return true;"
                + "  }"
                + "  if(existing&&existing.__helmsman&&existing.config&&existing.config.hasSettingsScreen)return true;"
                + "  ha.hass.auth.external={"
                + "    __helmsman:true,"
                + "    config:{hasSettingsScreen:true,appVersion:" + page.jsString(hassClient.appVersion) + "},"
                + "    fireMessage:function(msg){"
                + "      window.__helmsmanQueue=window.__helmsmanQueue||[];"
                + "      window.__helmsmanQueue.push({type:'externalBus',opts:typeof msg==='string'?msg:JSON.stringify(msg||{})});"
                + "    }"
                + "  };"
                + "  try{ha.requestUpdate();}catch(e){}"
                + "  return true;"
                + "};"
                + "try{window.__helmsmanAttachExternal();}catch(e){}"
                + page.settingsExitJs()
                + page.filePickerHookJs()
                + "try{window.__helmsmanInstallSettingsExit&&window.__helmsmanInstallSettingsExit();}catch(e2){}"
                + "try{window.__helmsmanInstallFilePicker&&window.__helmsmanInstallFilePicker();}catch(e3){}"
                + "window.__helmsmanBridge = true;"
                + "return 'ok';"
                + "})();"

        page.runViewJavaScript(
                    script,
                    function(result) {
                        if (result !== "ok") {
                            console.log("Token injection result:", result)
                            return
                        }
                        page.bridgeInstalled = true
                        page.updateLoadingThemeFromWebView()
                        if (!page.tokensInjected) {
                            page.tokensInjected = true
                            if (dashboardView && page.isHassFrontendUrl(dashboardView.url))
                                page.beginReadyCheck()
                            else
                                page.openFrontendAfterAuth()
                            return
                        }
                        if (silent)
                            return
                        if (dashboardView && page.isHassFrontendUrl(dashboardView.url))
                            page.beginReadyCheck()
                        else
                            page.pollBridge()
                    },
                    function(error) {
                        console.log("Token injection failed:", error)
                    })
    }

    function refreshWebHistory() {
        if (page.isHome || !page.dashboardReady)
            return
        page.runViewJavaScript(
                    "return (function(){"
                    + "try{"
                    + "  if(!window.__helmsmanHistHook){"
                    + "    window.__helmsmanHistHook=true;"
                    + "    window.__helmsmanHistDepth=0;"
                    + "    var push=history.pushState;"
                    + "    history.pushState=function(){"
                    + "      window.__helmsmanHistDepth=(window.__helmsmanHistDepth||0)+1;"
                    + "      return push.apply(this,arguments);"
                    + "    };"
                    + "    window.addEventListener('popstate',function(){"
                    + "      if(window.__helmsmanHistDepth>0)window.__helmsmanHistDepth-=1;"
                    + "    });"
                    + "  }"
                    + "  return window.__helmsmanHistDepth>0?'1':'0';"
                    + "}catch(e){return '0';}"
                    + "})();",
                    function(result) {
                        page.spaCanGoBack = result === "1" || result === 1
                    })
    }

    function pollBridge() {
        if (!page.bridgeInstalled || !page.dashboardReady)
            return

        page.runViewJavaScript(
                    "return (function(){"
                    + "try{window.__helmsmanAttachExternal&&window.__helmsmanAttachExternal();}catch(e){}"
                    + "var q=window.__helmsmanQueue||[]; window.__helmsmanQueue=[]; return JSON.stringify(q);"
                    + "})();",
                    function(result) {
                        page.handleBridgeQueue(result)
                    },
                    function(error) {
                        console.log("Bridge poll failed:", error)
                    })
    }

    function handleBridgeQueue(raw) {
        if (!raw || raw.length === 0 || raw === "[]")
            return

        var queue
        try {
            queue = JSON.parse(raw)
        } catch (e) {
            return
        }

        for (var i = 0; i < queue.length; ++i) {
            var item = queue[i]
            if (!item || !item.type)
                continue
            if (item.type === "externalBus")
                page.handleExternalBus(item.opts)
        }
    }

    function sendExternalBusResult(id, success, resultObj) {
        var payload = {
            id: id,
            type: "result",
            success: success
        }
        if (success)
            payload.result = resultObj
        else
            payload.error = resultObj

        page.runViewJavaScript(
                    "window.externalBus && window.externalBus("
                    + JSON.stringify(payload)
                    + "); return true;")
    }

    function handleExternalBus(raw) {
        var msg
        try {
            msg = JSON.parse(raw || "{}")
        } catch (e) {
            return
        }
        if (!msg || !msg.type)
            return

        if (msg.type === "config/get") {
            page.sendExternalBusResult(msg.id, true, {
                                           hasSettingsScreen: true,
                                           appVersion: hassClient.appVersion
                                       })
            return
        }
        if (msg.type === "config_screen/show") {
            page.openSettings()
            return
        }
        if (msg.type === "helmsman/back_dashboard") {
            if (!page.isHome && hassClient && hassClient.nativeDashboardEnabled)
                pageStack.pop()
            return
        }
        if (msg.type === "helmsman/pick_image")
            page.openImagePicker()
    }

    function openImagePicker() {
        if (page.filePickPending)
            return
        page.filePickPending = true
        pageStack.push(imagePickerComponent)
    }

    function finishFilePick(props) {
        page.filePickPending = false
        if (!props || !props.filePath || !hassClient) {
            page.cancelFilePick()
            return
        }
        var data = hassClient.readLocalImage(props.filePath)
        if (!data || !data.base64) {
            console.log("Helmsman: cannot read picked image")
            page.cancelFilePick()
            return
        }
        page.runViewJavaScript(
                    "return (function(){"
                    + "try{"
                    + "  if(!window.__helmsmanApplyPickedFile)return 'no-fn';"
                    + "  return window.__helmsmanApplyPickedFile("
                    + page.jsString(data.name) + ","
                    + page.jsString(data.mime) + ","
                    + page.jsString(data.base64)
                    + ");"
                    + "}catch(e){return 'fail:'+e;}"
                    + "})();",
                    function(result) {
                        if (result !== "ok")
                            console.log("Helmsman: applying picked image failed:", result)
                    })
    }

    function cancelFilePick() {
        page.filePickPending = false
        page.runViewJavaScript(
                    "return (function(){"
                    + "try{window.__helmsmanCancelPickedFile&&window.__helmsmanCancelPickedFile();}"
                    + "catch(e){}"
                    + "return 'ok';"
                    + "})();")
    }

    WifiChecker {
        id: wifi
        onNetworkChanged: hassClient.updateNetworkState(wifi.ready, wifi.connected, wifi.ssid)
    }

    Connections {
        target: hassClient
        onLoggedInChanged: {
            if (!hassClient.loggedIn)
                pageStack.replaceAbove(null, Qt.resolvedUrl("ConnectionPage.qml"), { hassClient: hassClient })
        }
        onAccessTokenChanged: {
            if (!hassClient.loggedIn || !hassClient.accessToken
                    || hassClient.accessToken.length === 0)
                return
            page.injectSessionAndBridge(page.dashboardReady)
        }
        onBaseUrlChanged: {
            if (page.status !== PageStatus.Active || !hassClient.loggedIn)
                return
            if (page.lastLoadedBase === hassClient.baseUrl)
                return
            page.refreshSnapshotState()
            page.reloadDashboard()
        }
    }

    Connections {
        target: hassClient && hassClient.lovelace ? hassClient.lovelace : null
        onIngressSessionChanged: {
            if (!hassClient || !hassClient.lovelace)
                return
            var next = hassClient.lovelace.ingressSession || ""
            if (next === page.ingressSession)
                return
            page.ingressSession = next
            if (page.ingressCookieSet && next.length)
                page.applyIngressCookie()
        }
    }

    Timer {
        id: ingressKeepAliveTimer
        interval: 60000
        repeat: true
        running: page.status === PageStatus.Active
                 && page.needsIngressCookie
                 && hassClient && hassClient.loggedIn
        onTriggered: {
            if (hassClient && hassClient.lovelace)
                hassClient.lovelace.keepIngressSessionAlive()
        }
    }

    Rectangle {
        id: cutoutFill
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: page.topCutoutHeight
        visible: height > 0
        color: page.overlayBackgroundColor
        z: 3
    }

    Loader {
        id: webViewLoader
        anchors.fill: parent
        anchors.topMargin: page.topCutoutHeight
        // Keep the engine painted under the overlay. WPE WebKit only creates
        // its view on a real scene-graph frame; opacity 0 left Atlantic stuck
        // on "Preparing session...".
        source: page.webViewEngine === "next153"
                ? Qt.resolvedUrl("Next153DashboardWebView.qml")
                : (page.webViewEngine === "atlantic"
                   ? Qt.resolvedUrl("AtlanticDashboardWebView.qml")
                   : Qt.resolvedUrl("StockDashboardWebView.qml"))
        onStatusChanged: {
            if (status === Loader.Error) {
                page.webViewFailed = true
                console.log("Helmsman: dashboard webview failed to load")
            }
        }
    }

    Connections {
        target: dashboardView
        onLoadedChanged: {
            if (!dashboardView || !dashboardView.loaded)
                return
            page.lastLoadedBase = hassClient.baseUrl
            if (page.skipFrontendChrome) {
                if (page.needsIngressCookie && !page.ingressCookieSet) {
                    page.applyIngressCookie(function() {
                        page.ingressCookieSet = true
                        page.openChromelessTarget()
                    })
                    return
                }
                page.finishDashboardLoad()
                return
            }
            page.injectSessionAndBridge()
        }
        onUrlChanged: {
            if (!hassClient.loggedIn || !dashboardView)
                return
            var value = String(dashboardView.url)
            if (value.indexOf("/_my_redirect/companion_app") >= 0
                    || value.indexOf("#external-app-configuration") >= 0) {
                page.openSettings()
                if (page.dashboardUrl.length > 0 && value.indexOf("/_my_redirect/companion_app") >= 0)
                    dashboardView.url = page.dashboardUrl
                return
            }
            if (page.tokensInjected
                    && (value.indexOf("/auth/authorize") >= 0
                        || value.indexOf("/auth/login_flow") >= 0)) {
                page.dashboardReady = false
                page.readyCheckRunning = false
                readyCheckTimer.stop()
                page.tokensInjected = false
                page.injectSessionAndBridge()
            }
        }
    }

    Timer {
        id: readyCheckTimer
        interval: 250
        repeat: true
        onTriggered: page.checkDashboardReady()
    }

    Timer {
        id: snapshotDelayTimer
        interval: 900
        repeat: false
        onTriggered: page.captureDashboardSnapshot()
    }

    Timer {
        id: openedPathTimer
        interval: 800
        repeat: false
        onTriggered: page.navigateOpenedPathOnce()
    }

    Timer {
        id: resumeProbeStartTimer
        interval: 800
        repeat: false
        onTriggered: {
            resumeProbeTimer.start()
            page.runResumeProbe()
        }
    }

    Timer {
        id: resumeProbeTimer
        interval: 500
        repeat: true
        onTriggered: page.runResumeProbe()
    }

    Component.onCompleted: page.refreshSnapshotState()

    onStatusChanged: {
        if (status === PageStatus.Active)
            startWebViewTimer.start()
    }

    Timer {
        id: injectRetryTimer
        interval: 500
        repeat: true
        running: !page.skipFrontendChrome
                 && !!(dashboardView && dashboardView.loaded
                       && hassClient && hassClient.loggedIn
                       && !page.tokensInjected)
        onTriggered: page.injectSessionAndBridge()
    }

    Timer {
        id: startWebViewTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (!hassClient || !hassClient.loggedIn)
                return
            if (!dashboardView) {
                startWebViewTimer.start()
                return
            }
            var current = String(dashboardView.url)
            if (current.length > 0 && current.indexOf("about:blank") < 0)
                return
            if (page.startUrl.length > 0)
                dashboardView.url = page.startUrl
        }
    }

    onAppActiveChanged: {
        if (!page.appActive)
            page.lastBackgroundedAt = Date.now()
    }

    Timer {
        id: historyReleaseTimer
        interval: 500
        repeat: false
        onTriggered: page.holdBackOff = false
    }

    Timer {
        id: historyPollTimer
        interval: 250
        repeat: true
        running: page.status === PageStatus.Active
                 && !page.isHome
                 && page.dashboardReady
                 && hassClient && hassClient.loggedIn
        onTriggered: page.refreshWebHistory()
    }

    Timer {
        id: bridgePollTimer
        interval: 300
        repeat: true
        running: page.status === PageStatus.Active
                 && Qt.application.active
                 && hassClient.loggedIn
                 && page.dashboardReady
                 && page.bridgeInstalled
        onTriggered: page.pollBridge()
    }

    // Cover the WebView until Lovelace is ready so users do not see partial renders.
    Rectangle {
        id: loadingOverlay
        anchors.fill: parent
        anchors.topMargin: page.topCutoutHeight
        color: page.overlayBackgroundColor
        visible: !page.dashboardReady
        z: 2

        Image {
            id: snapshotImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: status === Image.Ready
            source: page.snapshotUsable
                    ? ("file://" + hassClient.dashboardSnapshotPath + "?" + page.snapshotRevision)
                    : ""
        }

        Rectangle {
            anchors.fill: parent
            color: page.overlayBackgroundColor
            opacity: snapshotImage.status === Image.Ready ? 0.55 : 1.0
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.horizontalPageMargin
            spacing: Theme.paddingLarge

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                running: loadingOverlay.visible && !page.webViewFailed
                size: BusyIndicatorSize.Large
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: page.overlayTextColor
                font.pixelSize: Theme.fontSizeSmall
                text: page.loadStatusText
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: page.webViewFailed
                text: qsTr("Open settings")
                onClicked: page.openSettings()
            }
        }
    }

    Component {
        id: imagePickerComponent
        ImagePickerPage {
            title: qsTr("Select picture")
            property bool picked: false
            onSelectedContentPropertiesChanged: {
                if (!selectedContentProperties || !selectedContentProperties.filePath)
                    return
                picked = true
                page.finishFilePick(selectedContentProperties)
            }
            Component.onDestruction: {
                if (!picked)
                    page.cancelFilePick()
            }
        }
    }
}
