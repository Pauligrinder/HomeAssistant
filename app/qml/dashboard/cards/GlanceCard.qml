import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    contentTopMargin: Theme.paddingSmall
    contentBottomMargin: Theme.paddingSmall

    readonly property var entities: (card && card.entities) ? card.entities : []
    readonly property bool hasTitle: !!(card && card.title && String(card.title).length > 0)
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property bool showName: !card || card.show_name !== false
    readonly property bool showIcon: !card || card.show_icon !== false
    readonly property bool showState: !card || card.show_state !== false
    // HA: columns, or min(entities, 5) so a short list fills the row.
    // A set columns value keeps empty space on the right when the row is short.
    readonly property int columnCount: {
        var configured = 0
        if (card && card.columns !== undefined && card.columns !== null && card.columns !== "")
            configured = Number(card.columns)
        if (configured > 0)
            return Math.max(1, Math.round(configured))
        var n = root.entities.length
        if (n < 1)
            return 1
        return Math.min(n, 5)
    }

    Label {
        width: parent.width
        visible: root.hasTitle
        height: visible ? implicitHeight : 0
        text: root.hasTitle ? String(card.title) : ""
        color: Theme.highlightColor
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
        truncationMode: TruncationMode.Fade
    }

    Grid {
        id: grid
        width: parent.width
        columns: root.columnCount
        rowSpacing: Theme.paddingSmall
        columnSpacing: 0

        Repeater {
            model: root.entities
            MouseArea {
                width: Math.floor(grid.width / Math.max(1, grid.columns))
                height: cell.height
                property string entityId: typeof modelData === "string"
                                          ? modelData
                                          : (modelData.entity ? String(modelData.entity) : "")
                property bool entityShowState: root.showState
                        && !(modelData && modelData.show_state === false)
                onClicked: {
                    if (dashboard && entityId.length) {
                        var card = { "entity": entityId }
                        if (typeof modelData === "object") {
                            if (modelData.tap_action)
                                card.tap_action = modelData.tap_action
                            if (modelData.confirmation !== undefined)
                                card.confirmation = modelData.confirmation
                        }
                        dashboard.handleCardTap(card)
                    }
                }
                onPressAndHold: {
                    if (dashboard && entityId.length)
                        dashboard.openMoreInfo(entityId)
                }

                Column {
                    id: cell
                    width: parent.width
                    spacing: 0

                    Label {
                        width: parent.width
                        visible: root.showName
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.secondaryColor
                        text: (modelData && modelData.name) ? modelData.name
                              : ((dashboard && root.rev >= 0) ? dashboard.friendlyName(entityId) : entityId)
                    }

                    Item {
                        visible: root.showIcon
                        x: Math.round((parent.width - width) / 2)
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall

                        MdiIcon {
                            anchors.fill: parent
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            mdiIcons: root.mdiIcons
                            name: (dashboard && root.rev >= 0) ? dashboard.entityIcon(entityId, modelData.icon || "") : ""
                            iconColor: (dashboard && root.rev >= 0 && dashboard.isOn(entityId))
                                       ? Theme.highlightColor : Theme.primaryColor
                            opacity: (dashboard && root.rev >= 0 && dashboard.isPending(entityId)) ? 0.55 : 1.0
                        }

                        PendingIndicator {
                            anchors.centerIn: parent
                            dashboard: root.dashboard
                            entityId: entityId
                        }
                    }

                    Label {
                        width: parent.width
                        visible: entityShowState && entityId.indexOf("script.") !== 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.primaryColor
                        text: (dashboard && root.rev >= 0) ? dashboard.formatState(entityId) : ""
                    }
                    Label {
                        width: parent.width
                        visible: entityId.indexOf("script.") === 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        wrapMode: Text.NoWrap
                        font.pixelSize: Theme.fontSizeTiny
                        color: Theme.highlightColor
                        text: qsTr("Run")
                    }
                }
            }
        }
    }
}
