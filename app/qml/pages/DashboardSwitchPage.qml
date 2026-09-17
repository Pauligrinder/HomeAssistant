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

    function kindOf(entry) {
        return (entry && entry.kind) ? String(entry.kind) : "lovelace"
    }

    function iconOf(entry) {
        if (entry && entry.icon && String(entry.icon).length)
            return String(entry.icon)
        return page.kindOf(entry) === "lovelace" ? "mdi:view-dashboard" : "mdi:puzzle"
    }

    function activate(entry) {
        if (!page.dashboard)
            return
        var path = page.pathOf(entry)
        if (page.kindOf(entry) !== "lovelace") {
            page.dashboard.selectSwitcherPath(path)
            pageStack.pop()
            return
        }
        var norm = page.dashboard.normalizedUrlPath(path)
        var existing = pageStack.find(function(p) {
            return p && p.objectName === "HomePage" && p.boundPath === norm
        })
        if (existing) {
            pageStack.pop(existing)
            return
        }
        page.dashboard.setCurrentUrlPath(norm)
        pageStack.replace(Qt.resolvedUrl("NativeHomePage.qml"), {
                              hassClient: page.hassClient,
                              mdiIcons: page.mdiIcons,
                              followDefault: false,
                              urlPath: norm
                          })
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
                    model: page.dashboard ? page.dashboard.switcherItems : []

                    BackgroundItem {
                        id: tile
                        width: page.tileWidth
                        height: page.tileHeight
                        readonly property string dashboardPath: page.pathOf(modelData)
                        readonly property bool current: {
                            var home = pageStack.find(function(p) {
                                return p && p.objectName === "HomePage"
                            })
                            var activePath = home && home.boundPath !== undefined
                                    ? home.boundPath
                                    : (page.dashboard ? page.dashboard.currentUrlPath : "")
                            return dashboardPath === activePath
                        }

                        onClicked: page.activate(modelData)

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
                                name: page.iconOf(modelData)
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
