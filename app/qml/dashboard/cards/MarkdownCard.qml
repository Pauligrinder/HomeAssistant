import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    property string rendered: ""

    Connections {
        target: dashboard
        onTemplateReady: {
            if (key === root.templateKey())
                root.rendered = value
        }
    }

    function templateKey() {
        return "md:" + (card && card.content ? card.content : "")
    }

    Component.onCompleted: {
        if (dashboard && card && card.content)
            dashboard.renderTemplate(card.content, root.templateKey())
        root.rendered = (card && card.content) ? card.content : ""
    }

    Label {
        width: parent.width
        visible: card && card.title && String(card.title).length > 0
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
    }

    Label {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        color: Theme.primaryColor
        font.pixelSize: Theme.fontSizeSmall
        text: root.rendered
    }
}
