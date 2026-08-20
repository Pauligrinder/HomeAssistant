import QtQuick 2.6
import Nemo.DBus 2.0

Item {
    id: checker
    property string ssid: ""
    property bool connected: false

    function refresh() {
        manager.call("GetServices", undefined,
                     function(result) {
                         for (var i = 0; i < result.length; ++i) {
                             var entry = result[i][1]
                             if (entry.Type === "wifi"
                                     && (entry.State === "online" || entry.State === "ready")) {
                                 checker.ssid = entry.Name || ""
                                 checker.connected = true
                                 return
                             }
                         }
                         checker.ssid = ""
                         checker.connected = false
                     },
                     function() {
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
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: checker.refresh()
    }
}
