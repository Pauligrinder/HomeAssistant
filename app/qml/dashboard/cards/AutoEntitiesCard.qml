import QtQuick 2.6
import Sailfish.Silica 1.0
import ".."

// HACS lovelace-auto-entities: resolve entities, then render the nested card.
Item {
    id: root
    property var card: ({})
    property var dashboard
    property var hassClient
    property var mdiIcons
    property int fillHeight: 0
    width: parent ? parent.width : Screen.width
    implicitHeight: loader.height
    height: implicitHeight
    readonly property int rev: dashboard ? dashboard.statesRevision : 0
    readonly property var resolvedCard: root.buildResolvedCard()

    function entryEntityId(entry) {
        if (typeof entry === "string")
            return entry
        if (entry && entry.entity)
            return String(entry.entity)
        return ""
    }

    function matchString(value, pattern) {
        var v = String(value === undefined || value === null ? "" : value)
        var p = String(pattern === undefined || pattern === null ? "" : pattern)
        if (!p.length)
            return true
        if (p.charAt(0) === "/" && p.length >= 2) {
            var end = p.lastIndexOf("/")
            var body = end > 0 ? p.substring(1, end) : p.substring(1)
            return v.indexOf(body) >= 0
        }
        if (p.indexOf("*") >= 0) {
            var parts = p.split("*")
            var idx = 0
            for (var i = 0; i < parts.length; ++i) {
                if (!parts[i].length)
                    continue
                var at = v.indexOf(parts[i], idx)
                if (at < 0)
                    return false
                idx = at + parts[i].length
            }
            return true
        }
        return v === p
    }

    function matchFilter(entityId, filter) {
        if (!filter || typeof filter !== "object")
            return true
        if (filter.state !== undefined && filter.state !== null) {
            var st = (dashboard && root.rev >= 0) ? dashboard.entityState(entityId) : ""
            if (!root.matchString(st, filter.state))
                return false
        }
        if (filter.domain) {
            var dom = (dashboard && root.rev >= 0) ? dashboard.domainOf(entityId) : ""
            if (!root.matchString(dom, filter.domain))
                return false
        }
        if (filter.entity_id) {
            if (!root.matchString(entityId, filter.entity_id))
                return false
        }
        if (filter.name) {
            var name = (dashboard && root.rev >= 0)
                       ? dashboard.friendlyName(entityId, "") : ""
            if (!root.matchString(name, filter.name))
                return false
        }
        if (filter.attributes && typeof filter.attributes === "object") {
            for (var key in filter.attributes) {
                if (!filter.attributes.hasOwnProperty(key))
                    continue
                var attr = (dashboard && root.rev >= 0)
                           ? dashboard.attribute(entityId, key) : undefined
                if (!root.matchString(attr, filter.attributes[key]))
                    return false
            }
        }
        return true
    }

    function excluded(entityId) {
        var filters = (card && card.filter && card.filter.exclude)
                      ? card.filter.exclude : []
        for (var i = 0; i < filters.length; ++i) {
            if (root.matchFilter(entityId, filters[i]))
                return true
        }
        return false
    }

    function includedFromFilters() {
        var out = []
        var filters = (card && card.filter && card.filter.include)
                      ? card.filter.include : []
        if (!filters.length || !dashboard || root.rev < 0)
            return out
        for (var i = 0; i < filters.length; ++i) {
            var f = filters[i] || {}
            if (f.type && String(f.type) !== "entity") {
                out.push(f)
                continue
            }
            var probe = { "entities": [], "domain": f.domain || "" }
            var ids = dashboard.filterEntities(probe) || []
            for (var j = 0; j < ids.length; ++j) {
                var id = String(ids[j])
                if (!root.matchFilter(id, f))
                    continue
                var entry = { "entity": id }
                if (f.options) {
                    for (var k in f.options)
                        entry[k] = f.options[k]
                }
                out.push(entry)
            }
        }
        return out
    }

    function sortKey(entry, method, attribute) {
        var id = root.entryEntityId(entry)
        if (!dashboard || root.rev < 0)
            return id
        if (method === "state")
            return dashboard.entityState(id)
        if (method === "name")
            return dashboard.friendlyName(id, id)
        if (method === "domain")
            return dashboard.domainOf(id)
        if (method === "attribute" && attribute)
            return String(dashboard.attribute(id, attribute) || "")
        return id
    }

    function buildEntities() {
        var list = []
        var src = (card && card.entities) ? card.entities : []
        for (var i = 0; i < src.length; ++i) {
            var e = src[i]
            if (typeof e === "string")
                list.push({ "entity": e })
            else if (e)
                list.push(e)
        }
        list = list.concat(root.includedFromFilters())
        var filtered = []
        var seen = {}
        for (var j = 0; j < list.length; ++j) {
            var entry = list[j]
            var id = root.entryEntityId(entry)
            if (!id) {
                filtered.push(entry)
                continue
            }
            if (seen[id])
                continue
            if (root.excluded(id))
                continue
            seen[id] = true
            filtered.push(entry)
        }
        var sort = (card && card.sort) ? card.sort : null
        if (sort && sort.method) {
            var method = String(sort.method)
            var attr = sort.attribute ? String(sort.attribute) : ""
            var reverse = !!sort.reverse
            filtered.sort(function(a, b) {
                var ka = root.sortKey(a, method, attr)
                var kb = root.sortKey(b, method, attr)
                if (ka < kb)
                    return reverse ? 1 : -1
                if (ka > kb)
                    return reverse ? -1 : 1
                return 0
            })
        }
        return filtered
    }

    function buildResolvedCard() {
        var base = (card && card.card) ? card.card : { "type": "entities" }
        var out = {}
        for (var key in base)
            out[key] = base[key]
        if (!out.type)
            out.type = "entities"
        var param = (card && card.card_param) ? String(card.card_param) : "entities"
        out[param] = root.buildEntities()
        return out
    }

    CardLoader {
        id: loader
        width: root.width
        unitWidth: root.width
        columns: 12
        fillHeight: 0
        panelMap: false
        card: root.resolvedCard
        dashboard: root.dashboard
        hassClient: root.hassClient
        mdiIcons: root.mdiIcons
    }
}
