import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// HACS mushroom-title-card: heading (+ optional subtitle), no chrome.
CardChrome {
    id: root
    showBackground: false
    tapEnabled: false
    contentTopMargin: Theme.paddingSmall
    contentBottomMargin: Theme.paddingSmall

    readonly property string align: {
        var a = card && card.alignment ? String(card.alignment).toLowerCase() : "left"
        if (a === "center" || a === "right" || a === "left")
            return a
        return "left"
    }

    Label {
        width: parent.width
        visible: !!(card && card.title && String(card.title).length)
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        wrapMode: Text.Wrap
        horizontalAlignment: root.align === "center" ? Text.AlignHCenter
                           : (root.align === "right" ? Text.AlignRight : Text.AlignLeft)
    }
    Label {
        width: parent.width
        visible: !!(card && card.subtitle && String(card.subtitle).length)
        text: card && card.subtitle ? card.subtitle : ""
        color: Theme.secondaryColor
        font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.Wrap
        horizontalAlignment: root.align === "center" ? Text.AlignHCenter
                           : (root.align === "right" ? Text.AlignRight : Text.AlignLeft)
    }
}
