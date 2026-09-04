import QtQuick 2.6
import Sailfish.Silica 1.0

Column {
    id: layout
    property var view: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingLarge

    CardFlow {
        width: parent.width
        cards: (layout.view && layout.view.cards) ? layout.view.cards : []
        dashboard: layout.dashboard
        hassClient: layout.hassClient
        mdiIcons: layout.mdiIcons
    }
}
