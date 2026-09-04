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

    Repeater {
        model: (layout.view && layout.view.sections) ? layout.view.sections : []
        Column {
            width: layout.width
            spacing: Theme.paddingSmall

            CardFlow {
                width: parent.width
                cards: modelData.cards || []
                dashboard: layout.dashboard
                hassClient: layout.hassClient
                mdiIcons: layout.mdiIcons
                columns: 12
            }
        }
    }
}
