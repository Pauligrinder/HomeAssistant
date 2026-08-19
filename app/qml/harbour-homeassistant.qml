import QtQuick 2.6
import Sailfish.Silica 1.0
import harbour.helmsman 1.0
import "cover" as CoverDir
import "pages"

ApplicationWindow
{
    id: appWindow

    HassClient {
        id: hassClientInstance
    }

    Component.onCompleted: hassClientInstance.restoreSession()

    Connections {
        target: hassClientInstance
        onRestoreFinished: function(loggedIn) {
            if (loggedIn)
                pageStack.replace(Qt.resolvedUrl("pages/HomePage.qml"), { hassClient: hassClientInstance })
        }
    }

    initialPage: Component {
        ConnectionPage {
            hassClient: hassClientInstance
        }
    }
    cover: CoverDir.CoverPage {
        hassClient: hassClientInstance
    }
    allowedOrientations: Orientation.All
}
