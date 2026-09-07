import QtQuick 2.6
import Sailfish.Silica 1.0
import "../dashboard"

// Dashboard picker laid out like the Sailfish app covers: a grid of tiles,
// the active one highlighted.
Page {
    id: page
    property var hassClient
    property var mdiIcons
    property var dashboard: hassClient ? hassClient.lovelace : null

    readonly property real tileWidth: (page.width - 3 * Theme.horizontalPageMargin) / 2
    readonly property real tileHeight: tileWidth * 1.2

    function pathOf(entry) {
        return (entry && entry.url_path) ? String(entry.url_path) : ""
    }

    function titleOf(entry) {
        if (entry && entry.title && String(entry.title).length)
            return String(entry.title)
        var path = page.pathOf(entry)
        return path.length ? path : "Overview"
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        VerticalScrollDecorator {}

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader { title: "Change dashboard" }

            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.horizontalPageMargin

                Repeater {
                    model: page.dashboard ? page.dashboard.dashboards : []

                    BackgroundItem {
                        id: tile
                        width: page.tileWidth
                        height: page.tileHeight
                        readonly property string dashboardPath: page.pathOf(modelData)
                        readonly property bool current: page.dashboard
                                && dashboardPath === (page.dashboard.currentUrlPath || "")

                        onClicked: {
                            if (page.dashboard)
                                page.dashboard.setCurrentUrlPath(tile.dashboardPath)
                            pageStack.pop()
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.paddingMedium
                            color: Theme.rgba(tile.current ? Theme.highlightBackgroundColor
                                                           : Theme.secondaryColor,
                                              tile.current ? Theme.highlightBackgroundOpacity
                                                           : 0.1)
                            border.width: tile.current ? 2 : 0
                            border.color: Theme.highlightColor
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 2 * Theme.paddingMedium
                            spacing: Theme.paddingMedium

                            MdiIcon {
                                x: (parent.width - width) / 2
                                width: Theme.iconSizeLarge
                                height: width
                                mdiIcons: page.mdiIcons
                                name: (modelData && modelData.icon)
                                      ? String(modelData.icon) : "mdi:view-dashboard"
                                iconColor: tile.current ? Theme.highlightColor
                                                        : Theme.primaryColor
                            }

                            Label {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                font.pixelSize: Theme.fontSizeSmall
                                color: tile.current ? Theme.highlightColor : Theme.primaryColor
                                text: page.titleOf(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
