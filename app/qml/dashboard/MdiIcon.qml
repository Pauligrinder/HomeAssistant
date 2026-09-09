import QtQuick 2.6
import Sailfish.Silica 1.0

Label {
    id: icon
    property var mdiIcons
    property string name
    property color iconColor: Theme.primaryColor
    property int pixelSize: Math.round(width > 0 ? width : Theme.iconSizeMedium)

    width: Theme.iconSizeMedium
    height: width
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: icon.iconColor
    font.family: icon.mdiIcons && icon.mdiIcons.ready
                 ? icon.mdiIcons.fontFamily : Theme.fontFamily
    font.pixelSize: Math.max(8, Math.round(icon.pixelSize * 0.88))
    renderType: Text.NativeRendering
    opacity: text.length ? 1 : 0
    text: {
        if (!icon.mdiIcons || !icon.mdiIcons.ready
                || !icon.name || icon.name.length === 0)
            return ""
        return icon.mdiIcons.glyph(icon.name)
    }
}
