import QtQuick 2.6
import Sailfish.Silica 1.0
import "../dashboard"

Page {
    id: page
    property var hassClient
    property var mdiIcons
    property var dashboard: hassClient ? hassClient.lovelace : null
    // Empty entityId shows the browseable-player picker.
    property string entityId: ""
    property string mediaContentId: ""
    property string mediaContentType: ""
    property string pageTitle: ""
    property var mediaChildren: []
    property bool loading: false
    property string errorText: ""
    property int playersTick: 0
    property string pendingOpenId: ""
    property string pendingOpenTitle: ""
    // Must match LovelaceCoordinator::localMediaBrowserId().
    readonly property string resolvedLocalId: "__local__"
    readonly property bool isLocal: page.entityId.length > 0
            && page.entityId === page.resolvedLocalId
    readonly property bool pickingPlayer: !page.entityId.length
    readonly property var players: {
        page.playersTick
        return (dashboard && page.pickingPlayer) ? (dashboard.browseableMediaPlayers() || []) : []
    }
    readonly property string headerTitle: {
        if (page.pageTitle.length)
            return page.pageTitle
        if (page.pickingPlayer)
            return i18n.translation("media_browser")
        if (page.isLocal)
            return i18n.translation("media_browser_local")
        if (dashboard && page.entityId.length)
            return dashboard.friendlyName(page.entityId)
        return i18n.translation("media_browser")
    }

    function refresh() {
        if (page.pickingPlayer) {
            page.playersTick++
            page.loading = false
            page.errorText = ""
            return
        }
        if (!dashboard || !page.entityId.length)
            return
        page.loading = true
        page.errorText = ""
        if (page.isLocal)
            dashboard.browseMediaSource(page.mediaContentId)
        else
            dashboard.browseMedia(page.entityId, page.mediaContentId, page.mediaContentType)
    }

    function openPlayer(entityId) {
        if (!entityId)
            return
        pageStack.push(Qt.resolvedUrl("MediaBrowserPage.qml"), {
                           hassClient: page.hassClient,
                           mdiIcons: page.mdiIcons,
                           entityId: String(entityId)
                       })
    }

    function openChild(item) {
        if (!item)
            return
        pageStack.push(Qt.resolvedUrl("MediaBrowserPage.qml"), {
                           hassClient: page.hassClient,
                           mdiIcons: page.mdiIcons,
                           entityId: page.entityId,
                           mediaContentId: item.media_content_id ? String(item.media_content_id) : "",
                           mediaContentType: item.media_content_type ? String(item.media_content_type) : "",
                           pageTitle: item.title ? String(item.title) : ""
                       })
    }

    function playItem(item) {
        if (!dashboard || !item)
            return
        var contentId = item.media_content_id ? String(item.media_content_id) : ""
        if (!contentId.length)
            return
        if (page.isLocal) {
            page.openLocalItem(item)
            return
        }
        if (!page.entityId.length)
            return
        dashboard.playMedia(page.entityId, contentId,
                            item.media_content_type ? String(item.media_content_type) : "")
    }

    function openLocalItem(item) {
        if (!dashboard || !item)
            return
        var contentId = item.media_content_id ? String(item.media_content_id) : ""
        if (!contentId.length)
            return
        page.pendingOpenId = contentId
        page.pendingOpenTitle = item.title ? String(item.title) : ""
        page.loading = true
        dashboard.openBrowsableMedia(contentId)
    }

    function activateChild(item) {
        if (!item)
            return
        if (item.can_expand)
            page.openChild(item)
        else if (item.can_play)
            page.playItem(item)
    }

    function thumbPath(item) {
        if (!dashboard || !item)
            return ""
        return dashboard.mediaPathOf(item.thumbnail) || ""
    }

    Component.onCompleted: page.refresh()

    Connections {
        target: dashboard
        onMediaBrowseReady: {
            if (entityId !== page.entityId)
                return
            if (String(mediaContentId || "") !== String(page.mediaContentId || ""))
                return
            page.loading = false
            page.errorText = ""
            if (item && item.title && !page.pageTitle.length)
                page.pageTitle = String(item.title)
            page.mediaChildren = (item && item.children) ? item.children : []
        }
        onMediaBrowseFailed: {
            if (entityId !== page.entityId)
                return
            if (String(mediaContentId || "") !== String(page.mediaContentId || ""))
                return
            page.loading = false
            page.mediaChildren = []
            page.errorText = message && String(message).length
                    ? String(message)
                    : i18n.translation("media_browse_failed")
        }
        onMediaOpenReady: {
            if (!page.isLocal)
                return
            if (String(mediaContentId || "") !== String(page.pendingOpenId || ""))
                return
            var title = page.pendingOpenTitle
            page.loading = false
            page.pendingOpenId = ""
            page.pendingOpenTitle = ""
            var url = fileUrl ? String(fileUrl) : ""
            if (!url.length) {
                page.errorText = i18n.translation("media_open_failed")
                return
            }
            var mime = mimeType ? String(mimeType).toLowerCase() : ""
            // file:// means we downloaded an image into the media cache.
            if (mime.indexOf("image/") === 0 || url.indexOf("file://") === 0) {
                pageStack.push(Qt.resolvedUrl("MediaImagePage.qml"), {
                                   titleText: title,
                                   sourceUrl: url
                               })
            }
        }
        onStatesRevisionChanged: {
            if (page.pickingPlayer)
                page.playersTick++
        }
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: page.pickingPlayer ? page.players : page.mediaChildren
        currentIndex: -1
        spacing: 0

        PullDownMenu {
            MenuItem {
                text: i18n.translation("refresh")
                onClicked: page.refresh()
            }
        }

        header: PageHeader {
            title: page.headerTitle
            description: page.pickingPlayer
                         ? i18n.translation("select_media_player")
                         : ""
        }

        ViewPlaceholder {
            enabled: !page.loading && !page.errorText.length
                     && ((page.pickingPlayer && page.players.length === 0)
                         || (!page.pickingPlayer && page.mediaChildren.length === 0))
            text: page.pickingPlayer
                  ? i18n.translation("no_browseable_media_players")
                  : i18n.translation("no_items")
        }

        ViewPlaceholder {
            enabled: page.errorText.length > 0 && !page.loading
            text: page.errorText
        }

        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: page.loading && list.count === 0
        }

        delegate: BackgroundItem {
            id: row
            width: list.width
            height: Theme.itemSizeLarge
            readonly property var item: modelData || {}
            readonly property bool isPlayer: page.pickingPlayer
            readonly property bool isLocalPlayer: row.isPlayer
                    && String(item.entity_id || "") === page.resolvedLocalId
            readonly property string titleText: {
                if (row.isPlayer)
                    return item.name ? String(item.name) : String(item.entity_id || "")
                return item.title ? String(item.title) : ""
            }
            readonly property string subtitleText: {
                if (row.isLocalPlayer)
                    return i18n.translation("media_browser_local_help")
                if (row.isPlayer)
                    return item.entity_id ? String(item.entity_id) : ""
                var bits = []
                if (item.media_class)
                    bits.push(String(item.media_class))
                if (item.can_play)
                    bits.push(i18n.translation("play"))
                return bits.join(" · ")
            }
            readonly property string thumb: row.isPlayer ? "" : page.thumbPath(item)
            property string thumbUrl: ""
            property string requestedThumb: ""

            function syncThumb() {
                var path = row.thumb
                if (!path.length || !dashboard) {
                    row.thumbUrl = ""
                    return
                }
                var cached = dashboard.cachedMediaUrl(path)
                if (cached && cached.length) {
                    row.thumbUrl = cached
                    return
                }
                row.thumbUrl = ""
                if (path !== row.requestedThumb) {
                    row.requestedThumb = path
                    dashboard.prefetchMedia(path)
                }
            }

            Component.onCompleted: row.syncThumb()
            onThumbChanged: row.syncThumb()

            Connections {
                target: dashboard
                onMediaCached: {
                    if (path === row.thumb)
                        row.thumbUrl = fileUrl
                }
            }

            onClicked: {
                if (row.isPlayer)
                    page.openPlayer(item.entity_id)
                else
                    page.activateChild(item)
            }

            RoundedImage {
                id: art
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeLarge
                height: width
                visible: row.thumbUrl.length > 0
                source: row.thumbUrl
                fillMode: Image.PreserveAspectCrop
                cornerRadius: Theme.paddingSmall
            }

            MdiIcon {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeLarge
                height: width
                visible: !art.visible
                mdiIcons: page.mdiIcons
                name: {
                    if (row.isLocalPlayer)
                        return "mdi:folder-home"
                    if (row.isPlayer)
                        return item.icon ? String(item.icon) : "mdi:cast"
                    var cls = item.media_class ? String(item.media_class) : ""
                    if (cls === "directory" || cls === "album" || cls === "playlist"
                            || cls === "podcast" || cls === "channel" || cls === "app")
                        return "mdi:folder"
                    if (cls === "image")
                        return "mdi:image"
                    if (cls === "video" || cls === "tv_show" || cls === "episode")
                        return "mdi:movie"
                    return "mdi:music"
                }
                iconColor: Theme.primaryColor
            }

            Column {
                anchors.left: art.visible ? art.right : icon.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: playButton.visible ? playButton.left : parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingSmall

                Label {
                    width: parent.width
                    text: row.titleText
                    truncationMode: TruncationMode.Fade
                    color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    visible: row.subtitleText.length > 0
                    text: row.subtitleText
                    truncationMode: TruncationMode.Fade
                    color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }

            IconButton {
                id: playButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin / 2
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.isPlayer && !!item.can_play && !!item.can_expand
                icon.source: "image://theme/icon-m-play"
                onClicked: page.playItem(item)
            }
        }

        VerticalScrollDecorator {}
    }
}
