import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

Column {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingSmall

    Repeater {
        model: (root.card && root.card.cards) ? root.card.cards : []
        CardLoader {
            width: root.width
            unitWidth: root.width
            columns: 12
            card: modelData
            dashboard: root.dashboard
            hassClient: root.hassClient
            mdiIcons: root.mdiIcons
        }
    }
}
