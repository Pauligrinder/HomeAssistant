.pragma library

// Lipstick loads the Events View widget outside the app, so it cannot use the
// C++ catalog. Same JSON files, same keys. A missing key or language falls
// back to English.

var loaded = false
var english = {}
var localized = {}

function readJson(url) {
    try {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url, false)
        xhr.send(null)
        if (!xhr.responseText)
            return {}
        var data = JSON.parse(xhr.responseText)
        return data && typeof data === "object" ? data : {}
    } catch (e) {
        return {}
    }
}

function candidates() {
    var name = String(Qt.locale().name || "").replace("-", "_")
    if (!name || name === "C" || name === "en")
        return []
    var mapped = name
    if (name === "no" || name.indexOf("nb") === 0)
        mapped = "nb"
    else if (name === "zh" || name === "zh_Hans" || name.indexOf("zh_CN") === 0
             || name.indexOf("zh_Hans") === 0)
        mapped = "zh_CN"
    else if (name === "zh_HK")
        mapped = "zh_HK"
    else if (name === "zh_Hant" || name.indexOf("zh_TW") === 0
             || name.indexOf("zh_Hant") === 0)
        mapped = "zh_TW"
    else if (name.indexOf("pt_BR") === 0 || name === "pt_br")
        mapped = "pt_BR"
    var out = []
    if (mapped !== "en")
        out.push(mapped)
    var bare = mapped.split("_")[0]
    if (bare && bare !== mapped && bare !== "en" && bare !== "zh" && bare !== "pt")
        out.push(bare)
    return out
}

function ensure() {
    if (loaded)
        return
    loaded = true
    var dir = Qt.resolvedUrl("../translations/")
    english = readJson(dir + "en.json")
    var codes = candidates()
    for (var i = 0; i < codes.length; ++i) {
        var over = readJson(dir + codes[i] + ".json")
        if (over && Object.keys(over).length) {
            localized = over
            return
        }
    }
}

function text(key) {
    ensure()
    if (localized[key])
        return localized[key]
    if (english[key])
        return english[key]
    return key
}
