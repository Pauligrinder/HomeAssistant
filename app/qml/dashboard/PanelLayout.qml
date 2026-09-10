import QtQuick 2.6
import Sailfish.Silica 1.0

Column {
    id: layout
    property var view: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingMedium

    Repeater {
        model: (layout.view && layout.view.cards && layout.view.cards.length)
               ? [layout.view.cards[0]] : []
        CardLoader {
            width: layout.width
            unitWidth: layout.width
            columns: 12
            fillHeight: index === 0 ? layout.fillHeight : 0
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
