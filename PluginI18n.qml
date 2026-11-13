import QtQuick
import Quickshell.Io

// A self-contained counterpart to Commons.Translations with ONE difference:
// `language` is writable. The shared kit binds it (readonly) to I18n.language,
// i.e. the whole system's language, so it cannot honour a plugin-only choice.
// Here the bar widget sets `language` from status-json (the CLI is the single
// authority that resolves the plugin setting) and switching it re-renders
// every binding that calls t() immediately — no restart, no system change.
//
// Catalogs are flat JSON files in `directory`: en.json is the base, the
// selected language overlays it, and a regional code (zh-CN) also falls back
// to its base language (zh). Missing keys fall back per string, exactly like
// the shared kit. This plugin only needs t(); plural catalogs (tn) are unused.
QtObject {
  id: root

  property var directory: ""
  property string language: "en"

  readonly property string baseLanguage: language.split("-")[0]
  readonly property string directoryPath: String(directory).replace(/^file:\/\//, "").replace(/\/+$/, "")

  readonly property var englishStrings: parseCatalog(englishFile.text())
  readonly property var baseStrings: parseCatalog(baseFile.text())
  readonly property var languageStrings: parseCatalog(languageFile.text())

  readonly property var strings: {
    var merged = ({})
    var layers = [root.englishStrings, root.baseStrings, root.languageStrings]
    for (var i = 0; i < layers.length; i++)
      for (var key in layers[i])
        if (typeof layers[i][key] === "string") merged[key] = layers[i][key]
    return merged
  }

  function t(key, fallback) {
    var value = root.strings[key]
    if (typeof value === "string" && value.length > 0) return value
    return fallback !== undefined ? fallback : key
  }

  function parseCatalog(raw) {
    try {
      var parsed = JSON.parse(raw || "{}")
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      return ({})
    }
  }

  function catalogPath(code) {
    return root.directoryPath !== "" ? root.directoryPath + "/" + code + ".json" : ""
  }

  property FileView englishFile: FileView {
    path: root.catalogPath("en")
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  // Only read for a regional code; for "en" or "zh-CN" the language file
  // covers it. An empty path keeps the FileView inert.
  property FileView baseFile: FileView {
    path: root.baseLanguage !== root.language && root.baseLanguage !== "en" ? root.catalogPath(root.baseLanguage) : ""
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }

  property FileView languageFile: FileView {
    path: root.language !== "en" ? root.catalogPath(root.language) : ""
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }
}
