import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    readonly property var entities: (card && card.entities) ? card.entities : []
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property bool pictureHeader: !!(card && card.header
                                              && card.header.type === "picture")
    readonly property bool pictureFooter: !!(card && card.footer
                                              && card.footer.type === "picture")
    contentTopMargin: pictureHeader ? 0 : Theme.paddingMedium
    contentBottomMargin: pictureFooter ? 0 : Theme.paddingMedium

    CardHeaderFooter {
        config: (card && card.header) ? card.header : ({})
        dashboard: root.dashboard
        edgeWidth: root.width
        edgeOffset: -Theme.paddingMedium
        cornerRadius: root.radius
        roundTop: true
    }

    Label {
        width: parent.width
        // A chained && yields undefined rather than false when the card has no
        // title, which leaves visible untouched and reserves an empty line.
        visible: !!(card && card.title && String(card.title).length > 0)
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
            height: visible ? Theme.itemSizeSmall : 0
            property var config: (modelData && typeof modelData === "object")
                                 ? modelData : { "entity": String(modelData) }
            // A conditional row holds its conditions at the top level and the
            // row they guard under "row", so the row itself is what every other
            // binding has to read.
            readonly property bool conditionalRow: String(row.config.type || "") === "conditional"
            readonly property var entry: (row.conditionalRow && row.config.row)
                                         ? row.config.row : row.config
            readonly property string rowType: (row.entry && row.entry.type)
                                              ? String(row.entry.type) : "entity"
            property string entityId: (row.entry && row.entry.entity)
                                      ? String(row.entry.entity) : ""
            property bool toggleable: (rowType === "entity" && row.entityId.length > 0
                                       && dashboard && root.rev >= 0)
                                      ? dashboard.isToggleable(row.entityId) : false

            // Both a conditional row and a plain row carrying "visibility" are
            // collapsed rather than left blank when their conditions fail.
            visible: {
                if (!dashboard || root.rev < 0)
                    return true
                if (row.conditionalRow)
                    return !!dashboard.isVisible(row.config.conditions)
                if (row.config.visibility)
                    return !!dashboard.isVisible(row.config.visibility)
                return true
            }

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
                    id: rowIcon
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
                    y: (parent.height - height) / 2
                    // The name gets whatever the icon, state and switch leave,
                    // so nothing is pushed past the edge of the card.
                    width: Math.max(0, parent.width - rowIcon.width - Theme.paddingSmall
                                    - (stateLabel.visible
                                       ? stateLabel.width + Theme.paddingSmall : 0)
                                    - (toggle.visible ? toggle.width + Theme.paddingSmall : 0))
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
                    id: stateLabel
                    y: (parent.height - height) / 2
                    visible: row.entityId.length > 0 && !row.toggleable
                    // Long states keep at most part of the row for themselves.
                    width: Math.min(implicitWidth, row.width * 0.45)
                    horizontalAlignment: Text.AlignRight
                    text: (dashboard && row.entityId.length && root.rev >= 0)
                          ? dashboard.formatState(row.entityId) : ""
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    truncationMode: TruncationMode.Fade
                }

                Switch {
                    id: toggle
                    y: (parent.height - height) / 2
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

    CardHeaderFooter {
        config: (card && card.footer) ? card.footer : ({})
        dashboard: root.dashboard
        edgeWidth: root.width
        edgeOffset: -Theme.paddingMedium
        cornerRadius: root.radius
        roundBottom: true
    }
}
