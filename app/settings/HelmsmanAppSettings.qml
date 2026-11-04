import QtQuick 2.0
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.settings 1.0

// Same pattern as Sailfish Browser's Settings → Apps entry: only a D-Bus
// call. Cold start is handled by dbus-1 service activation for
// org.helmsman.harbour-helmsman.ui (not the widget bus name, so Events View
// heartbeats do not auto-launch the app).
ApplicationSettings {
    Button {
        anchors.horizontalCenter: parent.horizontalCenter
        preferredWidth: Theme.buttonWidthLarge
        text: "Open Helmsman settings"
        onClicked: helmsmanUi.openSettings()
    }

    DBusInterface {
        id: helmsmanUi
        bus: DBus.SessionBus
        service: "org.helmsman.harbour-helmsman.ui"
        path: "/widget"
        iface: "org.helmsman.Widget"

        function openSettings() {
            call("OpenSettings", [], function() {
            }, function(error, message) {
                console.warn("Failed to open Helmsman settings:", error, message)
            })
        }
    }
}
