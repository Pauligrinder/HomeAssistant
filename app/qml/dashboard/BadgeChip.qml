import QtQuick 2.6
import Sailfish.Silica 1.0

// Lovelace view badges: HA's current look is a capsule with an icon and
// the entity state, not a bare label.
Rectangle {
    id: pill
    property var dashboard
    property var mdiIcons
    property var badge
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    signal clicked(string entityId)

    readonly property string entityId: {
        if (typeof pill.badge === "string")
            return pill.badge
        if (pill.badge && pill.badge.entity)
            return String(pill.badge.entity)
        return ""
    }
    readonly property bool showIcon: !(pill.badge && typeof pill.badge === "object"
                                       && pill.badge.show_icon === false)
    readonly property string iconName: {
        if (!pill.showIcon || pill.rev < 0)
            return ""
        var custom = (pill.badge && typeof pill.badge === "object" && pill.badge.icon)
                     ? String(pill.badge.icon) : ""
        if (!dashboard || pill.entityId.length === 0)
            return custom
        return dashboard.entityIcon(pill.entityId, custom)
    }
    readonly property string labelText: {
        var showState = !(pill.badge && typeof pill.badge === "object"
                          && pill.badge.show_state === false)
        if (pill.rev < 0 || !dashboard || pill.entityId.length === 0)
            return (pill.badge && typeof pill.badge === "object" && pill.badge.name)
                   ? String(pill.badge.name) : ""
        if (pill.entityId.indexOf("script.") === 0)
            return qsTr("Run")
        if (showState)
            return dashboard.formatState(pill.entityId)
        if (pill.badge && typeof pill.badge === "object" && pill.badge.name)
            return String(pill.badge.name)
        return dashboard.friendlyName(pill.entityId)
    }

    height: Theme.itemSizeExtraSmall
    radius: height / 2
    width: Math.ceil(content.implicitWidth + Theme.paddingMedium * 2)
    color: Theme.rgba(Theme.primaryColor,
                      Theme.colorScheme === Theme.LightOnDark ? 0.20 : 0.10)
    opacity: (!dashboard || pill.entityId.length === 0
              || dashboard.isAvailable(pill.entityId)) ? 1.0 : 0.45
    visible: pill.entityId.length > 0 && pill.labelText.length > 0

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.paddingMedium
        spacing: Theme.paddingSmall

        MdiIcon {
            visible: pill.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
            mdiIcons: pill.mdiIcons
            name: pill.iconName
            width: Theme.iconSizeSmall
            iconColor: (dashboard && dashboard.isOn(pill.entityId))
                       ? Theme.highlightColor : Theme.primaryColor
            opacity: (dashboard && pill.rev >= 0 && dashboard.isPending(pill.entityId)) ? 0.55 : 1.0
        }

        PendingIndicator {
            visible: running
            anchors.verticalCenter: parent.verticalCenter
            dashboard: pill.dashboard
            entityId: pill.entityId
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.labelText
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: pill.entityId.length > 0
        onClicked: pill.clicked(pill.entityId)
    }
}
