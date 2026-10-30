import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

Column {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    width: parent ? parent.width : Screen.width
    spacing: Theme.paddingSmall

    Repeater {
        model: (root.card && root.card.cards) ? root.card.cards : []
        CardLoader {
            width: root.width
            unitWidth: root.width
            columns: 12
            // Nested maps must stay compact EntityMap previews, never panel MapLibre.
            fillHeight: 0
            panelMap: false
            card: modelData
            dashboard: root.dashboard
            hassClient: root.hassClient
            mdiIcons: root.mdiIcons
        }
    }
}
