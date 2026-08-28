import QtQuick 2.6
import Nemo.DBus 2.0

Item {
    id: checker

    // "no Wi-Fi" and "ConnMan has not answered yet" must stay distinguishable:
    // the first means the LAN address is unreachable, the second means we know
    // nothing and should leave the current endpoint alone.
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
                         for (var i = 0; i < result.length; ++i) {
                             var entry = result[i][1]
                             if (entry && entry.Type === "wifi"
                                     && (entry.State === "online" || entry.State === "ready")) {
                                 checker.applyState(entry.Name || "", true)
                                 return
                             }
                         }
                         checker.applyState("", false)
                     },
                     function() {
                         // ConnMan unreachable: report nothing rather than
                         // claiming the phone is off Wi-Fi.
                         checker.ssid = ""
                         checker.connected = false
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
