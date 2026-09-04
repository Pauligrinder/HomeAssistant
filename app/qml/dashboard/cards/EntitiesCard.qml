import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    readonly property var entities: (card && card.entities) ? card.entities : []
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    Label {
        width: parent.width
        visible: card && card.title && String(card.title).length > 0
        text: card && card.title ? card.title : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
        truncationMode: TruncationMode.Fade
    }

    Repeater {
        model: root.entities
        BackgroundItem {
            id: row
            width: parent.width
            height: Theme.itemSizeSmall
            property var entry: typeof modelData === "object" ? modelData : { "entity": String(modelData) }
            property string entityId: {
                if (typeof modelData === "string")
                    return modelData
                if (modelData && modelData.entity)
                    return String(modelData.entity)
                if (modelData && modelData.type === "weblink")
                    return ""
                return ""
            }
            property string rowType: (typeof modelData === "object" && modelData.type) ? modelData.type : "entity"
            property bool toggleable: (rowType === "entity" && row.entityId.length > 0
                                       && dashboard && root.rev >= 0)
                                      ? dashboard.isToggleable(row.entityId) : false

            visible: rowType !== "conditional"
                     || (dashboard && root.rev >= 0 && dashboard.isVisible(entry.conditions))

            onClicked: {
                if (rowType === "weblink" && dashboard) {
                    dashboard.performAction({ "action": "url", "url_path": entry.url }, "")
                    return
                }
                if (rowType === "button" && dashboard) {
                    dashboard.performAction(entry.tap_action || { "action": "toggle" }, row.entityId)
                    return
                }
                if (row.entityId.length && dashboard)
                    dashboard.performAction(entry.tap_action || { "action": "more-info" }, row.entityId)
            }
            onPressAndHold: {
                if (row.entityId.length && dashboard)
                    dashboard.openMoreInfo(row.entityId)
            }

            Rectangle {
                visible: rowType === "divider"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 2
                color: Theme.secondaryColor
                opacity: 0.3
            }

            Label {
                visible: rowType === "section"
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: entry.label || entry.name || ""
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                font.bold: true
            }

            Row {
                visible: rowType !== "divider" && rowType !== "section"
                anchors.fill: parent
                spacing: Theme.paddingSmall

                MdiIcon {
                    y: (parent.height - height) / 2
                    mdiIcons: root.mdiIcons
                    name: {
                        if (entry.icon)
                            return entry.icon
                        if (!dashboard || !row.entityId.length || root.rev < 0)
                            return "mdi:link"
                        return dashboard.entityIcon(row.entityId)
                    }
                    iconColor: (dashboard && row.entityId.length && root.rev >= 0
                                && dashboard.isOn(row.entityId))
                               ? Theme.highlightColor : Theme.primaryColor
                    width: Theme.iconSizeSmall
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.iconSizeSmall * 2 - Theme.paddingLarge
                           - (row.toggleable ? toggle.width : 0)
                    text: {
                        if (entry.name)
                            return entry.name
                        if (rowType === "weblink")
                            return entry.url || "Link"
                        if (dashboard && row.entityId.length && root.rev >= 0)
                            return dashboard.friendlyName(row.entityId)
                        return row.entityId
                    }
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primaryColor
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.entityId.length > 0 && !row.toggleable
                    text: (dashboard && row.entityId.length && root.rev >= 0)
                          ? dashboard.formatState(row.entityId) : ""
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }

                Switch {
                    id: toggle
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.toggleable
                    automaticCheck: false
                    // root.rev is read so the switch follows entity updates.
                    checked: (row.toggleable && root.rev >= 0)
                             ? dashboard.isOn(row.entityId) : false
                    onClicked: dashboard.toggle(row.entityId)
                }
            }
        }
    }
}
