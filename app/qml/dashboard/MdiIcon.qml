import QtQuick 2.6
import Sailfish.Silica 1.0

Image {
    id: icon
    property var mdiIcons
    property string name
    property color iconColor: Theme.primaryColor
    property int pixelSize: Math.round(width > 0 ? width : Theme.iconSizeMedium)

    width: Theme.iconSizeMedium
    height: width
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    opacity: name && name.length ? 1 : 0
    source: {
        if (!icon.mdiIcons || !icon.mdiIcons.ready
                || !icon.name || icon.name.length === 0)
            return ""
        var renderName = icon.mdiIcons.hasIcon(icon.name)
                ? icon.name : "mdi:help-circle-outline"
        var path = icon.mdiIcons.renderIconFile(renderName, String(icon.iconColor),
                                                Math.max(24, icon.pixelSize))
        return path && path.length ? ("file://" + path) : ""
    }
}
