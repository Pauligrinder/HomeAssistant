import QtQuick 2.6
import Sailfish.Silica 1.0

Item {
    id: root
    property var stream
    property string entityId: ""
    property bool active: false
    property bool userPaused: false

    width: parent.width
    height: {
        if (!root.visible)
            return 0
        if (stream && stream.frameWidth > 0 && stream.frameHeight > 0)
            return Math.round(width * stream.frameHeight / stream.frameWidth)
        return Math.round(width * 9 / 16)
    }

    function sync() {
        if (!stream || !root.entityId.length)
            return
        if (!root.active) {
            root.userPaused = false
            stream.stop()
            return
        }
        if (root.userPaused)
            return
        stream.start(root.entityId)
    }

    onActiveChanged: root.sync()
    onEntityIdChanged: root.sync()
    onStreamChanged: root.sync()
    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (stream)
            stream.stop()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Image {
        id: frame
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: false
        visible: status === Image.Ready
    }

    Connections {
        target: stream
        onFrameUrlChanged: {
            frame.source = ""
            frame.source = stream.frameUrl
        }
        onPlayingChanged: {
            if (stream && stream.playing)
                root.userPaused = false
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: stream && stream.loading && !frame.visible
    }

    Label {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.horizontalPageMargin
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: Theme.secondaryColor
        visible: stream && stream.error.length > 0 && !frame.visible
        text: stream ? stream.error : ""
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Theme.paddingMedium
        width: liveLabel.width + 2 * Theme.paddingSmall
        height: liveLabel.height + Theme.paddingSmall
        radius: height / 2
        color: Theme.errorColor
        visible: stream && stream.playing && frame.visible
        opacity: 0.9

        Label {
            id: liveLabel
            anchors.centerIn: parent
            text: "LIVE"
            font.pixelSize: Theme.fontSizeTiny
            font.bold: true
            color: "white"
        }
    }

    IconButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.paddingSmall
        icon.source: stream && (stream.playing || stream.loading)
                     ? "image://theme/icon-m-pause"
                     : "image://theme/icon-m-play"
        onClicked: {
            if (!stream || !root.entityId.length)
                return
            if (stream.playing || stream.loading) {
                root.userPaused = true
                stream.stop()
            } else {
                root.userPaused = false
                stream.start(root.entityId)
            }
        }
    }
}
