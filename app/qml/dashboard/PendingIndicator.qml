import QtQuick 2.6
import Sailfish.Silica 1.0

BusyIndicator {
    id: indicator
    property var dashboard
    property string entityId
    readonly property int rev: dashboard ? dashboard.statesRevision : 0

    size: BusyIndicatorSize.ExtraSmall
    running: !!(dashboard && indicator.entityId && indicator.entityId.length
                && indicator.rev >= 0 && dashboard.isPending(indicator.entityId))
    visible: running
    enabled: false
}
