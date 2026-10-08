import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false

    readonly property var entities: (card && card.entities) ? card.entities : []
    property int listTick: 0
    readonly property int rev: root.statesRevision + listTick
    readonly property bool pictureHeader: !!(card && card.header
                                              && card.header.type === "picture")
    readonly property bool pictureFooter: !!(card && card.footer
                                              && card.footer.type === "picture")
    contentTopMargin: pictureHeader ? 0 : Theme.paddingMedium
    contentBottomMargin: pictureFooter ? 0 : Theme.paddingMedium

    function rowEntityId(entry) {
        if (typeof entry === "string")
            return entry
        if (entry && entry.entity)
            return String(entry.entity)
        return ""
    }

    Connections {
        target: dashboard
        onEntityChanged: {
            var list = root.entities
            for (var i = 0; i < list.length; ++i) {
                if (root.rowEntityId(list[i]) === entityId) {
                    root.listTick++
                    return
                }
            }
        }
    }

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
            // Prefer entity-id prefix so scripts still get a Run control before
            // states arrive (domainOf alone is fine, but keep this resilient).
            readonly property bool isScript: {
                if (row.entityId.indexOf("script.") === 0)
                    return true
                if (!dashboard || !row.entityId.length || root.rev < 0)
                    return false
                return dashboard.domainOf(row.entityId) === "script"
            }
            // Lovelace entities "button" rows render an action chip (default Run).
            readonly property bool showActionButton: rowType === "button"
            readonly property string actionButtonText: {
                if (entry && entry.action_name !== undefined && entry.action_name !== null
                        && String(entry.action_name).length)
                    return String(entry.action_name)
                return i18n.translation("run")
            }
            readonly property bool showRunText: row.isScript
                    && rowType === "entity" && row.entityId.length > 0
            readonly property bool showToggle: row.toggleable && !row.isScript
            readonly property bool showState: rowType === "entity" && row.entityId.length > 0
                    && !row.toggleable && !row.isScript

            function runRowAction() {
                if (!dashboard)
                    return
                var confirm = entry.confirmation
                if (confirm === undefined && entry.tap_action)
                    confirm = entry.tap_action.confirmation
                if (rowType === "button") {
                    dashboard.performAction(root.mergeConfirmation(entry.tap_action || { "action": "toggle" },
                                                                   confirm), row.entityId)
                    return
                }
                dashboard.performAction(root.mergeConfirmation({ "action": "toggle" }, confirm),
                                       row.entityId)
            }

            // Collapse when visibility/conditions fail or the entity is registry-hidden.
            visible: {
                if (!dashboard || root.rev < 0)
                    return true
                return !!dashboard.entityEntryVisible(row.config)
            }
            opacity: root.withPressOpacity(
                         (row.entityId.length && dashboard && root.rev >= 0
                          && dashboard.entityDimmed(row.entityId)) ? 0.45 : 1.0,
                         row.down)

            onClicked: {
                if (rowType === "weblink" && dashboard) {
                    dashboard.performAction({ "action": "url", "url_path": entry.url }, "")
                    return
                }
                if (row.showActionButton || row.showRunText) {
                    row.runRowAction()
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
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                spacing: Theme.paddingSmall

                Item {
                    id: rowIconBox
                    y: (parent.height - height) / 2
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall

                    MdiIcon {
                        id: rowIcon
                        anchors.fill: parent
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
                        opacity: (dashboard && row.entityId.length && root.rev >= 0
                                  && dashboard.isPending(row.entityId)) ? 0.55 : 1.0
                    }

                    PendingIndicator {
                        anchors.centerIn: parent
                        dashboard: root.dashboard
                        entityId: row.entityId
                    }
                }

                Label {
                    id: nameLabel
                    y: (parent.height - height) / 2
                    // Leave room for trailing state / Run / toggle; do not bind
                    // to their widths here or the Row can push them off-card.
                    width: Math.max(0, parent.width - rowIconBox.width - Theme.paddingSmall
                                    - trailingBox.width
                                    - (trailingBox.width > 0 ? Theme.paddingSmall : 0))
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

                Item {
                    id: trailingBox
                    y: (parent.height - height) / 2
                    height: parent.height
                    width: {
                        if (actionButton.visible)
                            return actionButton.width
                        if (toggle.visible)
                            return toggle.width
                        if (stateLabel.visible)
                            return Math.min(stateLabel.implicitWidth, row.width * 0.45)
                        return 0
                    }

                    Button {
                        id: actionButton
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        visible: row.showActionButton
                        preferredWidth: Theme.buttonWidthExtraSmall
                        height: Theme.itemSizeExtraSmall
                        text: row.actionButtonText
                        onClicked: row.runRowAction()
                    }

                    Label {
                        id: stateLabel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        visible: row.showState || row.showRunText
                        width: Math.min(implicitWidth, row.width * 0.45)
                        horizontalAlignment: Text.AlignRight
                        text: {
                            if (row.showRunText) {
                                if (dashboard && root.rev >= 0 && dashboard.isOn(row.entityId))
                                    return i18n.translation("running")
                                return i18n.translation("run")
                            }
                            return (dashboard && row.entityId.length && root.rev >= 0)
                                   ? dashboard.formatState(row.entityId) : ""
                        }
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Switch {
                        id: toggle
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        visible: row.showToggle
                        automaticCheck: false
                        // root.rev is read so the switch follows entity updates.
                        checked: (row.showToggle && root.rev >= 0)
                                 ? dashboard.isOn(row.entityId) : false
                        onClicked: {
                            var confirm = entry.confirmation
                            if (confirm === undefined && entry.tap_action)
                                confirm = entry.tap_action.confirmation
                            dashboard.performAction(root.mergeConfirmation({ "action": "toggle" }, confirm),
                                                   row.entityId)
                        }
                    }
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
