import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: (card && card.title) ? card.title : (card && card.url ? String(card.url) : "Web page")
        color: Theme.highlightColor
    }
    Button {
        text: "Open"
        onClicked: {
            var url = card && (card.url || card.path) ? String(card.url || card.path) : ""
            if (!dashboard || !url.length)
                return
            if (url.charAt(0) === "/")
                dashboard.openWebPath(url)
            else
                dashboard.performAction({ "action": "url", "url_path": url }, "")
        }
    }
}
