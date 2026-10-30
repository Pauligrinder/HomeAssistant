import QtQuick 2.6
import Sailfish.Silica 1.0
import "../dashboard"

Page {
    id: page
    property var hassClient
    property var mdiIcons
    property var dashboard: hassClient ? hassClient.lovelace : null
    property var markers: []
    property string title: ""
    // Finite defaults only — MapLibre aborts on NaN center (domain_error / exit 134).
    property real latitude: 64.95
    property real longitude: 25.75
    property real zoom: 5
    property bool autoFit: true

    allowedOrientations: Orientation.All
    // MapLibre pans via a nested Flickable; Silica back-swipe steals horizontal
    // drags and rubber-bands the map. Use an explicit back control instead.
    backNavigation: false

    // Opaque sink so taps never fall through to the dashboard underneath while
    // MapLibre is loading or when the GL item does not accept a click.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: 0
    }
    MouseArea {
        anchors.fill: parent
        z: 0
        // Swallow presses that miss map gestures / chrome.
        onPressed: mouse.accepted = true
        onClicked: {}
    }

    // Destroy MapLibre before the page finishes popping — tearing it down with
    // the Page caused mali heap corruption (exit 134) when leaving map views.
    // Wait until Active and sized; Activating at 0×0 has also aborted MapLibre.
    Loader {
        id: mapLoader
        anchors.fill: parent
        z: 1
        active: page.status === PageStatus.Active
                && page.width > Theme.itemSizeLarge
                && page.height > Theme.itemSizeLarge
        sourceComponent: mapComp
    }

    Component {
        id: mapComp
        MapLibreMap {
            anchors.fill: parent
            dashboard: page.dashboard
            markers: page.markers
            latitude: page.latitude
            longitude: page.longitude
            zoom: page.zoom
            autoFit: page.autoFit
            interactive: true
            topContentInset: Theme.itemSizeLarge
            onMarkerClicked: {
                if (page.dashboard)
                    page.dashboard.openMoreInfo(entityId)
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: headerLabel.height + Theme.paddingLarge + 2 * Theme.paddingMedium
        visible: headerLabel.visible
        color: "#000000"
        opacity: 0.55
        z: 40
    }

    MapBackButton {
        anchors.left: parent.left
        anchors.top: parent.top
        z: 50
        onClicked: pageStack.pop()
    }

    Label {
        id: headerLabel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Theme.paddingLarge + Theme.paddingMedium
        anchors.leftMargin: Theme.itemSizeLarge
        anchors.rightMargin: Theme.horizontalPageMargin
        z: 41
        text: page.title.length ? page.title : i18n.translation("map")
        visible: text.length > 0
        color: "#FFFFFF"
        font.pixelSize: Theme.fontSizeLarge
        truncationMode: TruncationMode.Fade
    }
}
