import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

CardChrome {
    id: root
    tapEnabled: false
    property string imageUrl: ""
    property string requestedPath: ""
    property int listTick: 0
    readonly property int rev: root.statesRevision + listTick
    contentTopMargin: 0
    contentBottomMargin: 0
    contentHorizontalMargin: 0

    Connections {
        target: dashboard
        onEntityChanged: root.listTick++
    }
    // Sailfish DarkOnLight = light ambience (dark text); LightOnDark = dark.
    readonly property bool lightAmbience: Theme.colorScheme === Theme.DarkOnLight
    readonly property string footerEntityId: {
        if (card && card.entity)
            return String(card.entity)
        if (card && card.image_entity)
            return String(card.image_entity)
        if (card && card.camera_image)
            return String(card.camera_image)
        return ""
    }
    // Keep the last good title. onCardChanged can briefly see an empty map
    // after MoreInfo and would otherwise wipe the footer.
    property string heldTitle: ""
    readonly property string footerTitle: {
        var t = root.resolveFooterTitle()
        return t.length ? t : root.heldTitle
    }
    readonly property bool showFooterTitle: root.footerTitle.length > 0
    readonly property bool showFooterState: {
        if (!root.footerEntityId.length || !dashboard || root.rev < 0)
            return false
        return !!(card && card.show_state === true)
    }
    readonly property bool showFooterName: {
        if (!root.footerEntityId.length || !dashboard || root.rev < 0)
            return false
        return !!(card && card.show_name === true)
            && !root.showFooterTitle
    }
    readonly property bool showFooter: root.showFooterTitle || root.showFooterName
                                      || root.showFooterState

    function resolveFooterTitle() {
        if (!card)
            return ""
        if (dashboard && dashboard.cardTitle) {
            var fromDash = dashboard.cardTitle(card)
            if (fromDash && String(fromDash).length)
                return String(fromDash)
        }
        if (card._helmsman_card_title !== undefined && card._helmsman_card_title !== null
                && String(card._helmsman_card_title).length)
            return String(card._helmsman_card_title)
        if (card.title !== undefined && card.title !== null && String(card.title).length)
            return String(card.title)
        return ""
    }

    function rememberTitle() {
        var t = root.resolveFooterTitle()
        if (t.length)
            root.heldTitle = t
    }

    onCardChanged: root.rememberTitle()
    Component.onCompleted: root.rememberTitle()

    readonly property var flatElements: {
        var _ = root.rev
        return root.flattenElements((card && card.elements) ? card.elements : [])
    }

    function aspectRatioFromConfig() {
        if (!card || !card.aspect_ratio)
            return 0
        var ar = String(card.aspect_ratio).trim()
        if (!ar.length)
            return 0
        if (ar.indexOf("%") >= 0) {
            var pct = parseFloat(ar)
            return isFinite(pct) && pct > 0 ? 100 / pct : 0
        }
        var parts = ar.replace("x", ":").split(":")
        var a = parseFloat(parts[0])
        var b = parts.length > 1 ? parseFloat(parts[1]) : 1
        if (isFinite(a) && isFinite(b) && b !== 0)
            return a / b
        return 0
    }

    function mediaPath() {
        if (!dashboard)
            return ""
        if (card && card.image_entity) {
            var entity = String(card.image_entity)
            if (dashboard.domainOf(entity) === "camera")
                return dashboard.cameraPath(entity)
            var pic = dashboard.mediaPathOf(dashboard.attribute(entity, "entity_picture"))
            if (pic.length)
                return pic
        }
        var image = dashboard.mediaPathOf(card ? card.image : "")
        if (image.length)
            return image
        if (card && card.camera_image)
            return dashboard.cameraPath(String(card.camera_image))
        return ""
    }

    function flattenElements(list) {
        var out = []
        if (!list)
            return out
        for (var i = 0; i < list.length; ++i) {
            var el = list[i]
            if (!el)
                continue
            if (String(el.type || "") === "conditional") {
                if (!el.conditions || (dashboard && root.rev >= 0
                                       && dashboard.isVisible(el.conditions)))
                    out = out.concat(root.flattenElements(el.elements || []))
                continue
            }
            out.push(el)
        }
        return out
    }

    function styleNumber(style, key, fallback) {
        if (!style || style[key] === undefined || style[key] === null)
            return fallback
        var n = parseFloat(String(style[key]))
        return isFinite(n) ? n : fallback
    }

    function styleSize(style, key, fallback, reference) {
        if (!style || style[key] === undefined || style[key] === null)
            return fallback
        var s = String(style[key]).trim()
        if (!s.length)
            return fallback
        if (s.indexOf("%") >= 0)
            return reference * parseFloat(s) / 100
        var n = parseFloat(s)
        return isFinite(n) ? n : fallback
    }

    function styleColor(style, fallback) {
        if (style && style.color)
            return String(style.color)
        return fallback
    }

    Connections {
        target: dashboard
        onMediaCached: {
            if (path === root.mediaPath())
                root.imageUrl = fileUrl
        }
        onEntityChanged: {
            if (entityId === root.footerEntityId)
                root.refresh()
        }
    }

    function refresh() {
        var path = root.mediaPath()
        if (!dashboard || !path.length)
            return
        var cached = dashboard.cachedMediaUrl(path)
        if (cached && cached.length)
            root.imageUrl = cached
        else if (path !== root.requestedPath) {
            root.requestedPath = path
            dashboard.prefetchMedia(path)
        }
    }

    Component.onCompleted: root.refresh()

    Item {
        id: stage
        x: -Theme.paddingMedium
        width: root.width
        height: {
            // Square grid / forced fill: occupy the chrome height.
            if (root.fillHeight > 0)
                return root.fillHeight
            var configured = root.aspectRatioFromConfig()
            if (configured > 0)
                return width / configured
            if (background.aspectRatio > 0)
                return width / background.aspectRatio
            return Math.max(Theme.itemSizeExtraLarge, width * 0.66)
        }

        RoundedImage {
            id: background
            anchors.fill: parent
            source: root.imageUrl
            // cornerRadius 0 avoids OpacityMask layer recomposits that can
            // paint over the footer after MoreInfo / media refresh. CardChrome
            // already clips to the card radius.
            cornerRadius: 0
            fillMode: root.fillHeight > 0 ? Image.PreserveAspectCrop
                                          : Image.PreserveAspectFit
        }

        Repeater {
            model: root.flatElements
            Item {
                id: node
                property var el: modelData
                property string entityId: el && el.entity ? String(el.entity) : ""
                property string elType: el && el.type ? String(el.type) : ""
                property var style: (el && el.style) ? el.style : ({})
                property real leftPct: root.styleNumber(style, "left", 50)
                property real topPct: root.styleNumber(style, "top", 50)
                property bool centerAnchor: !(style && style.transform === "none")

                width: {
                    if (elType === "image")
                        return Math.max(Theme.paddingLarge,
                                        root.styleSize(style, "width",
                                                       stage.width * 0.12, stage.width))
                    if (elType === "action-button")
                        return Math.max(Theme.itemSizeSmall,
                                        buttonLabel.implicitWidth + Theme.paddingMedium * 2)
                    if (elType === "state-label")
                        return Math.max(Theme.itemSizeSmall, labelText.implicitWidth)
                    if (elType === "state-badge")
                        return Theme.itemSizeMedium
                    return root.styleSize(style, "width", Theme.iconSizeMedium, stage.width)
                }
                height: {
                    if (elType === "image") {
                        var forced = root.styleSize(style, "height", 0, stage.height)
                        if (forced > 0)
                            return forced
                        if (el && el.aspect_ratio) {
                            var ar = String(el.aspect_ratio)
                            if (ar.indexOf("%") >= 0)
                                return width * parseFloat(ar) / 100
                            var parts = ar.replace("x", ":").split(":")
                            var a = parseFloat(parts[0])
                            var b = parts.length > 1 ? parseFloat(parts[1]) : 1
                            if (isFinite(a) && isFinite(b) && b !== 0)
                                return width * b / a
                        }
                        if (elementImage.aspectRatio > 0)
                            return width / elementImage.aspectRatio
                        return width
                    }
                    if (elType === "action-button")
                        return Theme.itemSizeExtraSmall
                    if (elType === "state-label")
                        return labelText.implicitHeight
                    if (elType === "state-badge")
                        return Theme.itemSizeMedium
                    return root.styleSize(style, "height", Theme.iconSizeMedium, stage.height)
                }
                x: stage.width * leftPct / 100 - (centerAnchor ? width / 2 : 0)
                y: stage.height * topPct / 100 - (centerAnchor ? height / 2 : 0)
                z: 1
                visible: {
                    if (dashboard && root.rev >= 0 && entityId.length
                            && dashboard.isEntityHidden(entityId))
                        return false
                    if (!el || !el.conditions)
                        return true
                    return !!(dashboard && root.rev >= 0 && dashboard.isVisible(el.conditions))
                }
                opacity: (dashboard && root.rev >= 0 && entityId.length
                          && dashboard.entityDimmed(entityId)) ? 0.45 : 1.0

                MouseArea {
                    anchors.fill: parent
                    enabled: elType !== ""
                    onClicked: {
                        if (!dashboard || !el)
                            return
                        if (elType === "action-button") {
                            var action = el.action ? String(el.action) : ""
                            var parts = action.split(".")
                            if (parts.length >= 2) {
                                var data = el.data ? el.data : ({})
                                var target = el.target ? el.target : ({})
                                var payload = {}
                                for (var k in data) {
                                    if (data.hasOwnProperty(k))
                                        payload[k] = data[k]
                                }
                                if (target.entity_id)
                                    payload.entity_id = target.entity_id
                                dashboard.callService(parts[0], parts.slice(1).join("."),
                                                      payload, payload.entity_id || "")
                            }
                            return
                        }
                        if (el.tap_action)
                            dashboard.performAction(el.tap_action, entityId)
                        else if (entityId.length)
                            dashboard.openMoreInfo(entityId)
                    }
                }

                // --- image element ---
                RoundedImage {
                    id: elementImage
                    anchors.fill: parent
                    visible: elType === "image"
                    cornerRadius: root.styleNumber(style, "border-radius", 0)
                    fillMode: Image.PreserveAspectFit
                    source: elementImage.resolvedUrl
                    property string resolvedUrl: ""
                    property string requestedPath: ""

                    function mediaPath() {
                        if (!dashboard || !el)
                            return ""
                        var state = (entityId.length && root.rev >= 0)
                                    ? dashboard.entityState(entityId) : ""
                        if (el.state_image && state && el.state_image[state] !== undefined)
                            return dashboard.mediaPathOf(el.state_image[state])
                        if (el.image)
                            return dashboard.mediaPathOf(el.image)
                        if (el.camera_image)
                            return dashboard.cameraPath(String(el.camera_image))
                        if (entityId.length && dashboard.domainOf(entityId) === "camera")
                            return dashboard.cameraPath(entityId)
                        if (entityId.length) {
                            var pic = dashboard.mediaPathOf(
                                        dashboard.attribute(entityId, "entity_picture"))
                            if (pic.length)
                                return pic
                        }
                        return ""
                    }

                    function refresh() {
                        var path = elementImage.mediaPath()
                        if (!dashboard || !path.length) {
                            elementImage.resolvedUrl = ""
                            return
                        }
                        var cached = dashboard.cachedMediaUrl(path)
                        if (cached && cached.length)
                            elementImage.resolvedUrl = cached
                        else if (path !== elementImage.requestedPath) {
                            elementImage.requestedPath = path
                            dashboard.prefetchMedia(path)
                        }
                    }

                    Connections {
                        target: dashboard
                        onMediaCached: {
                            if (path === elementImage.mediaPath())
                                elementImage.resolvedUrl = fileUrl
                        }
                        onStatesRevisionChanged: elementImage.refresh()
                        onEntityChanged: {
                            if (entityId === node.entityId)
                                elementImage.refresh()
                        }
                    }
                    Component.onCompleted: elementImage.refresh()
                    onVisibleChanged: if (visible) elementImage.refresh()
                }

                // --- icons ---
                MdiIcon {
                    id: icon
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: elType === "state-badge" ? parent.top : undefined
                    anchors.verticalCenter: elType === "state-badge" ? undefined
                                                                    : parent.verticalCenter
                    visible: elType === "state-icon" || elType === "icon"
                             || elType === "state-badge"
                    mdiIcons: root.mdiIcons
                    name: {
                        if (el && el.icon)
                            return String(el.icon)
                        return (dashboard && root.rev >= 0 && entityId.length)
                               ? dashboard.entityIcon(entityId) : ""
                    }
                    iconColor: {
                        if (style && style.color)
                            return String(style.color)
                        if (dashboard && root.rev >= 0 && entityId.length
                                && dashboard.isOn(entityId)
                                && (elType !== "state-icon" || el.state_color !== false))
                            return Theme.highlightColor
                        return "white"
                    }
                    width: Math.min(parent.width, parent.height
                                    - (elType === "state-badge" ? Theme.fontSizeTiny : 0))
                    height: width
                    opacity: (dashboard && root.rev >= 0 && entityId.length
                              && dashboard.isPending(entityId)) ? 0.55 : 1.0
                }

                PendingIndicator {
                    anchors.centerIn: icon
                    visible: icon.visible
                    dashboard: root.dashboard
                    entityId: entityId
                }

                // --- labels / badges / buttons ---
                Label {
                    id: labelText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: elType === "state-badge" ? icon.bottom : undefined
                    anchors.verticalCenter: (elType === "state-label")
                                            ? parent.verticalCenter : undefined
                    visible: elType === "state-label" || elType === "state-badge"
                    color: root.styleColor(style, "white")
                    font.pixelSize: elType === "state-badge" ? Theme.fontSizeTiny
                                                             : Theme.fontSizeExtraSmall
                    font.bold: elType === "state-badge"
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        var _ = root.rev
                        if (!el)
                            return ""
                        if (elType === "state-badge" && el.name === null)
                            return ""
                        if (entityId.length && dashboard && root.rev >= 0) {
                            var value
                            if (el.attribute)
                                value = dashboard.attribute(entityId, String(el.attribute))
                            else
                                value = dashboard.formatState(entityId)
                            var prefix = el.prefix ? String(el.prefix) : ""
                            var suffix = el.suffix ? String(el.suffix) : ""
                            return prefix + (value !== undefined && value !== null
                                             ? String(value) : "") + suffix
                        }
                        return el.title ? String(el.title) : ""
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: elType === "action-button"
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.75)
                    border.width: 1
                    border.color: Theme.rgba("white", 0.35)

                    Label {
                        id: buttonLabel
                        anchors.centerIn: parent
                        color: root.styleColor(style, "white")
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: (el && el.title) ? String(el.title) : ""
                    }
                }
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: footerColumn.height + 2 * Theme.paddingSmall
            visible: root.showFooter
            z: 10

            Rectangle {
                anchors.fill: parent
                radius: root.radius
                color: root.lightAmbience ? "#FFFFFF" : "#000000"
                opacity: 0.55

                // Cover the top rounded corners so the bar stays flush under the image.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.radius
                    color: parent.color
                }
            }

            Column {
                id: footerColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.paddingSmall

                Label {
                    width: parent.width
                    visible: root.showFooterTitle
                    text: root.footerTitle
                    color: root.lightAmbience ? "#111111" : "#FFFFFF"
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                }

                Label {
                    width: parent.width
                    visible: root.showFooterState
                    text: (dashboard && root.rev >= 0 && root.footerEntityId.length)
                          ? dashboard.formatState(root.footerEntityId) : ""
                    color: root.lightAmbience ? "#333333" : "#F0F0F0"
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }
    }
}
