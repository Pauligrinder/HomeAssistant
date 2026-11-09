import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    contentTopMargin: Theme.paddingMedium
    contentBottomMargin: Theme.paddingMedium
    contentHorizontalMargin: Theme.paddingMedium
    readonly property Item hostPage: {
        var p = parent
        while (p) {
            if (p.hasOwnProperty && p.hasOwnProperty("status")
                    && p.hasOwnProperty("orientationTransitionRunning"))
                return p
            p = p.parent
        }
        return null
    }
    readonly property bool pageActive: !root.hostPage
                                       || (root.hostPage.status === PageStatus.Active
                                           && !root.hostPage.orientationTransitionRunning)
    readonly property var cameraEntries: {
        var entries = []
        var cameras = card && card.cameras ? card.cameras : []
        for (var i = 0; i < cameras.length; ++i) {
            var camera = cameras[i]
            var entity = typeof camera === "string" ? camera
                         : (camera && camera.entity ? String(camera.entity) : "")
            if (entity.length)
                entries.push({
                    entity: entity,
                    name: camera && camera.name ? String(camera.name) : ""
                })
        }
        var single = card && card.camera_entity ? String(card.camera_entity) : ""
        if (single.length) {
            var found = false
            for (var j = 0; j < entries.length; ++j) {
                if (entries[j].entity === single)
                    found = true
            }
            if (!found)
                entries.unshift({ entity: single, name: "" })
        }
        return entries
    }
    property int selectedCameraIndex: 0
    readonly property string cameraEntity: root.cameraEntries.length
                                           && root.selectedCameraIndex < root.cameraEntries.length
                                           ? root.cameraEntries[root.selectedCameraIndex].entity : ""
    readonly property string cameraName: {
        if (!root.cameraEntity.length || !dashboard)
            return root.cameraEntity
        var name = root.cameraEntries[root.selectedCameraIndex].name
        return dashboard.friendlyName(root.cameraEntity, name)
    }
    readonly property string titleText: card && card.title
                                        ? String(card.title) : root.cameraName

    tapHandler: function() {
        if (dashboard && root.cameraEntity.length)
            dashboard.openMoreInfo(root.cameraEntity)
    }

    onCameraEntriesChanged: {
        if (root.selectedCameraIndex >= root.cameraEntries.length)
            root.selectedCameraIndex = 0
    }

    Column {
        width: parent.width
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            visible: text.length > 0
            text: root.titleText
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }

        Flow {
            width: parent.width
            spacing: Theme.paddingSmall
            visible: root.cameraEntries.length > 1

            Repeater {
                model: root.cameraEntries

                BackgroundItem {
                    width: cameraLabel.implicitWidth + 2 * Theme.paddingMedium
                    height: Theme.itemSizeSmall
                    highlighted: index === root.selectedCameraIndex
                    onClicked: root.selectedCameraIndex = index

                    Label {
                        id: cameraLabel
                        anchors.centerIn: parent
                        text: modelData.name.length ? modelData.name : modelData.entity
                        color: index === root.selectedCameraIndex
                               ? Theme.highlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }
        }

        FrigateGo2rtcStream {
            id: streamPlayer
            width: parent.width
            height: Math.max(Theme.itemSizeExtraLarge, width * 9 / 16)
            dashboard: root.dashboard
            hassClient: root.hassClient
            entityId: root.cameraEntity
            cameraTitle: root.titleText
            hostPage: root.hostPage
            active: root.visible && (root.pageActive || streamPlayer.fullscreenOpen)
                    && Qt.application.state === Qt.ApplicationActive
        }
    }
}
