import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    property string titleText: ""
    property string sourceUrl: ""

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: i18n.translation("refresh")
                enabled: page.sourceUrl.length > 0
                onClicked: {
                    image.source = ""
                    image.source = page.sourceUrl
                }
            }
        }

        Column {
            id: column
            width: flick.width

            PageHeader {
                title: page.titleText.length ? page.titleText
                                             : i18n.translation("media_browser_local")
            }

            Item {
                width: parent.width
                height: Math.max(Theme.itemSizeHuge * 3,
                                 Screen.height - Theme.itemSizeLarge * 2)

                Image {
                    id: image
                    anchors.fill: parent
                    anchors.margins: Theme.paddingMedium
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    source: page.sourceUrl
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Large
                    running: image.status === Image.Loading
                }

                ViewPlaceholder {
                    enabled: image.status === Image.Error
                    text: i18n.translation("media_open_failed")
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
