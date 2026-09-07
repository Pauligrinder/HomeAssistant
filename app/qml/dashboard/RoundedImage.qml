import QtQuick 2.6
import QtGraphicalEffects 1.0

// A picture clipped to the rounded corners of the card it sits in. Only the
// edges that touch the outside of the card are rounded, so a header keeps its
// square bottom and a footer its square top.
Item {
    id: root
    property alias source: image.source
    property int fillMode: Image.PreserveAspectCrop
    property real cornerRadius: 0
    property bool roundTop: true
    property bool roundBottom: true
    // Natural width/height of the loaded picture, 0 until it arrives. Callers
    // use it to give the picture the height Home Assistant would.
    readonly property real aspectRatio: image.implicitHeight > 0
                                        ? image.implicitWidth / image.implicitHeight : 0

    Image {
        id: image
        anchors.fill: parent
        fillMode: root.fillMode
        asynchronous: true
        layer.enabled: root.cornerRadius > 0
        layer.effect: OpacityMask { maskSource: mask }
    }

    // The mask matches the item exactly; squaring off an edge is done by
    // painting over its corners rather than by resizing the mask, which would
    // scale it and distort the rounding.
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.cornerRadius
        visible: false
        layer.enabled: true

        Rectangle {
            visible: !root.roundTop
            width: parent.width
            height: root.cornerRadius
            color: parent.color
        }

        Rectangle {
            visible: !root.roundBottom
            y: parent.height - root.cornerRadius
            width: parent.width
            height: root.cornerRadius
            color: parent.color
        }
    }
}
