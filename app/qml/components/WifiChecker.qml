import QtQuick 2.6
import Nemo.DBus 2.0

Item {
    id: checker

    // ready=false until ConnMan answers. After that, connected is only true
    // when Wi-Fi is the default route (or the only online-capable service).
    property string ssid: ""
    property bool connected: false
    property bool ready: false

    signal networkChanged()

    function applyState(nextSsid, nextConnected) {
        var changed = !checker.ready
                || checker.ssid !== nextSsid
                || checker.connected !== nextConnected
        checker.ssid = nextSsid
        checker.connected = nextConnected
        checker.ready = true
        if (changed)
            checker.networkChanged()
    }

    function refresh() {
        manager.call("GetServices", [],
                     function(result) {
                         var wifiOnline = null
                         for (var i = 0; i < result.length; ++i) {
                             var entry = result[i][1]
                             if (!entry)
                                 continue
                             // ConnMan "ready" is associated with an IP, not the
                             // default route. Cellular can be "online" while
                             // home Wi-Fi stays "ready" — that is not connected.
                             if (entry.Type === "wifi" && entry.State === "online") {
                                 wifiOnline = entry
                                 break
                             }
                         }
                         if (wifiOnline)
                             checker.applyState(wifiOnline.Name || "", true)
                         else
                             checker.applyState("", false)
                     },
                     function() {
                         checker.applyState("", false)
                     })
    }

    DBusInterface {
        id: manager
        bus: DBus.SystemBus
        service: "net.connman"
        path: "/"
        iface: "net.connman.Manager"
        signalsEnabled: true
        Component.onCompleted: checker.refresh()
        function servicesChanged() { checker.refresh() }
        function propertyChanged() { checker.refresh() }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: checker.refresh()
    }
}
