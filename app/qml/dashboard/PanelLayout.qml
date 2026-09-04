import QtQuick 2.6
import Sailfish.Silica 1.0

Column {
    id: layout
    property var view: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingMedium

    Repeater {
        model: (layout.view && layout.view.cards) ? layout.view.cards : []
        CardLoader {
            width: layout.width
            unitWidth: layout.width
            columns: 12
            card: {
                var c = modelData || {}
                c._columns = 12
                return c
            }
            dashboard: layout.dashboard
            hassClient: layout.hassClient
            mdiIcons: layout.mdiIcons
        }
    }
}
