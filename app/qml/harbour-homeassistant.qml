import QtQuick 2.6
import Sailfish.Silica 1.0
import harbour.homeassistant 1.0
import "cover" as CoverDir
import "pages"

ApplicationWindow
{
    id: appWindow

    HassClient {
        id: hassClientInstance
    }

    initialPage: Component {
        FirstPage {
            hassClient: hassClientInstance
        }
    }
    cover: CoverDir.CoverPage {
        hassClient: hassClientInstance
    }
    allowedOrientations: Orientation.All
}
