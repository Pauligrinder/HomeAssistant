import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

Item {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    width: parent ? parent.width : Screen.width
    implicitHeight: visible ? loader.height : 0
    height: implicitHeight
    visible: (dashboard && rev >= 0) ? dashboard.cardVisible(card) : true

    CardLoader {
        id: loader
        width: root.width
        unitWidth: root.width
        card: root.card && root.card.card ? root.card.card : ({})
        dashboard: root.dashboard
        hassClient: root.hassClient
        mdiIcons: root.mdiIcons
    }
}
