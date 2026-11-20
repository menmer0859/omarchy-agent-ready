import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Controls as QQC
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Agent Ready — bar switch, arming card, watch digest and settings panel.
//
// Bar: one glyph, or the countdown number while arming. Left click arms /
// cancels / leaves, right click (or middle click) opens the settings panel.
//
// All state lives in the omarchy-agent-ready CLI. This widget only renders it
// and talks to the CLI through argv-vector Process calls — never through
// Quickshell.execDetached / `bash -lc`, which on some Surface machines produces
// an audible codec pop when the shell spawns a child.
//
// The widget owns the countdown (polls status-json once a second, fires
// `_arm-fire <token>` at the deadline), owns auto-arming via its own
// IdleMonitor, and runs a 2s reconcile tick for self-healing.
//
// Motion, theme colors, tooltips and the one-popup-at-a-time coordinator come
// from the shared kit: PopupCard, WidgetButton, PanelSectionHeader,
// PanelSeparator, Toggle, NumberField and Button. Text is PlainText and goes
// through our own PluginI18n (a Commons.Translations twin with a writable
// `language`), so the panel's language picker re-renders everything live —
// independently of the system language.
BarWidget {
  id: root
  moduleName: "eclipse.agent-ready"

  property bool popupOpen: false
  function close() { popupOpen = false }

  readonly property int panelWidth: setting("panelWidth", 340)
  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-agent-ready"

  property bool stateLoaded: false
  property bool arming: false
  property int remainingSec: 0
  property string pendingToken: ""
  property bool fireInFlight: false
  property bool wasLocked: false
  property bool leaveInFlight: false
  property bool activeState: false
  property bool inhibitAlive: false
  property var cfg: ({})
  property bool confirmReset: false
  property bool stateLogged: false
  property var commandQueue: []
  property var lastActionAt: ({})

  // extended state from status-json
  property string phase: "off"
  property var health: ({})
  property var digest: ({})
  property var autoInfo: ({})
  property var retryInfo: null
  property bool autoTriggered: false
  property bool previewActive: false
  property int previewUntil: 0
  property bool digestOpen: false
  // Where the digest card was opened from, so "Back" can return there:
  // "settings" -> the settings panel, "bar" -> the plain bar (close the card).
  property string digestOrigin: "bar"
  // Full watch history (newest first for display). Structured records from
  // history.json; the panel formats/translates every field.
  property var digestHistory: []
  readonly property bool digestEnabled: root.cfgGet(".digest.enabled", true) === true
  // Effective display code resolved by the CLI (status-json.language). It is
  // the single source of truth for BOTH the QML UI and the CLI notifications,
  // so the two can never disagree.
  property string language: "en"
  onLanguageChanged: Qt.callLater(function() {
    console.log("Agent Ready language:", language, "·", strings.t("section.language"))
  })

  // Single face selector: exactly one of closed/settings/arming/digest is
  // visible, so contradictory boolean combinations can never open a blank card.
  // Settings wins while the panel is open (its hero already shows the arming
  // countdown and its primary button becomes Cancel); otherwise an arming
  // countdown takes precedence over the digest face.
  readonly property string face: root.popupOpen ? "settings"
      : root.arming ? "arming"
      : root.digestOpen ? "digest" : "closed"
  readonly property bool showArming: root.face === "arming"
  readonly property bool showDigest: root.face === "digest"
  readonly property bool showSettings: root.face === "settings"
  readonly property bool cardOpen: root.face !== "closed"

  readonly property bool autoEnabled: root.autoInfo.enabled !== false
  readonly property bool autoAvailable: root.autoInfo.available !== false
  readonly property int autoThresholdSec: Number(root.autoInfo.thresholdSec) || 120
  readonly property int autoCooldown: Number(root.autoInfo.cooldownRemainingSec) || 0
  readonly property bool allowEnterNow: root.cfgGet(".arm.allowEnterNow", true) === true
  readonly property bool requireInhibitorsClear: root.cfgGet(".auto.requireInhibitorsClear", true) === true
  readonly property bool disarmOnInput: root.cfgGet(".auto.disarmOnInput", true) === true

  // Unlike Commons.Translations, `language` is writable here: it is driven by
  // the CLI's resolved code, which honours the plugin's own language setting
  // (config.language) without touching the system language.
  PluginI18n { id: strings; directory: Qt.resolvedUrl("i18n"); language: root.language }

  Component.onCompleted: console.log("Agent Ready widget loaded")

  function cfgGet(path, fallback) {
    var keys = String(path).replace(/^\./, "").split(".")
    var v = root.cfg
    for (var i = 0; i < keys.length; i++) {
      if (v === null || v === undefined || typeof v !== "object") return fallback
      v = v[keys[i]]
    }
    return (v === undefined || v === null) ? fallback : v
  }

  // Human-readable "what is about to happen", shown on the arming card.
  function armSummary() {
    var p = []
    if (cfgGet(".inhibit.enabled", true) === true) p.push(strings.t("summary.inhibit"))
    if (cfgGet(".idle.linkStayAwake", true) === true) p.push(strings.t("summary.idle"))
    if (cfgGet(".screen.lock", true) === true) p.push(strings.t("summary.lock"))
    if (cfgGet(".screen.dpmsOff", true) === true) p.push(strings.t("summary.dpms"))
    if (cfgGet(".audio.mute", false) === true) p.push(strings.t("summary.mute"))
    if (cfgGet(".powerProfile.enabled", true) === true) p.push(strings.t("summary.power"))
    p.push(strings.t("summary.agents"))
    return p.join(strings.t("notify.sep"))
  }

  // ---- watch history formatting (all records are language-neutral) ----

  function pad2(n) { return ("0" + n).slice(-2) }

  function fmtTime(iso) {
    if (!iso) return "?"
    var d = new Date(iso)
    if (isNaN(d.getTime())) return String(iso)
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
         + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  }

  function fmtDuration(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0))
    var h = Math.floor(sec / 3600)
    var m = Math.floor((sec % 3600) / 60)
    var s = sec % 60
    if (h > 0) return strings.t("digest.durHm").arg(h).arg(m)
    if (m > 0) return strings.t("digest.durMs").arg(m).arg(s)
    return strings.t("digest.durS").arg(s)
  }

  function actionLabels(keys) {
    var out = []
    if (!Array.isArray(keys)) return out
    for (var i = 0; i < keys.length; i++) out.push(strings.t("summary." + String(keys[i])))
    return out
  }

  function profileLabel(code) {
    var raw = String(code)
    var key = raw
    if (raw === "power-saver" || raw === "powerSaver" || raw === "power_saver") key = "powerSaver"
    else if (raw !== "balanced" && raw !== "performance") return raw
    return strings.t("profile." + key, raw)
  }

  // One record -> a multi-line, fully localised description.
  function digestRecordLines(r) {
    if (!r || typeof r !== "object") return ""
    var lines = []
    lines.push(strings.t("digest.recordTitle")
        .arg(Number(r.seq) || 0).arg(fmtTime(r.since)).arg(fmtTime(r.until)))
    lines.push(strings.t("digest.duration").arg(fmtDuration(r.durationSec)))
    var trig = String(r.trigger || "manual")
    lines.push(strings.t("digest.trigger")
        .arg(strings.t("digest.trigger." + trig, strings.t("digest.trigger.manual"))))
    var agents = Array.isArray(r.agents) ? r.agents : []
    lines.push(strings.t("digest.agentsNames")
        .arg(agents.length > 0 ? agents.join(strings.t("notify.sep")) : strings.t("digest.agentsNone")))
    var acts = actionLabels(r.actions)
    if (acts.length > 0) lines.push(strings.t("digest.actions").arg(acts.join(strings.t("notify.sep"))))
    if (r.powerProfile) lines.push(strings.t("digest.power").arg(root.profileLabel(r.powerProfile)))
    if (r.completed !== undefined && r.completed !== null)
      lines.push(strings.t("digest.completed").arg(Number(r.completed) || 0))
    if (r.failed !== undefined && r.failed !== null)
      lines.push(strings.t("digest.failed").arg(Number(r.failed) || 0))
    if (Array.isArray(r.pending) && r.pending.length > 0)
      lines.push(strings.t("digest.pending").arg(r.pending.join(strings.t("notify.sep"))))
    if (typeof r.note === "string" && r.note.length > 0)
      lines.push(strings.t("digest.note").arg(r.note))
    if (typeof r.lastEvent === "string" && r.lastEvent.length > 0)
      lines.push(strings.t("digest.lastEvent").arg(r.lastEvent))
    return lines.join("\n")
  }

  // "Back" returns to wherever the digest was opened from.
  function digestBack() {
    root.digestOpen = false
    if (root.digestOrigin === "settings") root.popupOpen = true
  }

  function healthSummary() {
    var h = root.health || ({})
    var bad = []
    if (h.inhibitor === "lost") bad.push(strings.t("health.inhibitor"))
    if (h.lock === "failed") bad.push(strings.t("health.lock"))
    if (h.dpms === "degraded") bad.push(strings.t("health.dpms"))
    if (h.auto === "degraded") bad.push(strings.t("health.auto"))
    return bad.join(" · ")
  }

  // Serial argv-vector command runner. No shell, no login shell, no
  // execDetached. Commands queue so rapid config edits never collide.
  Process {
    id: commandProc
    onExited: function() {
      Qt.callLater(function() { root.drainQueue() })
      refreshTimer.restart()
    }
  }

  function runCommand(argv) {
    root.commandQueue.push(argv)
    root.drainQueue()
  }

  function drainQueue() {
    if (commandProc.running || root.commandQueue.length === 0) return
    commandProc.command = root.commandQueue.shift()
    commandProc.running = true
  }

  // Rate-limited reconcile actions (2s tick, but a lasting condition must not
  // flood the queue).
  function actOnce(key, gapSec, argv) {
    var now = Math.floor(Date.now() / 1000)
    var last = Number(root.lastActionAt[key] || 0)
    if (now - last < gapSec) return false
    var next = {}
    for (var k in root.lastActionAt) next[k] = root.lastActionAt[k]
    next[key] = now
    root.lastActionAt = next
    root.runCommand(argv)
    return true
  }

  function setCfg(path, value) {
    var keys = String(path).replace(/^\./, "").split(".")
    var next
    try { next = JSON.parse(JSON.stringify(root.cfg)) } catch (e) { next = {} }
    var node = next
    for (var i = 0; i < keys.length - 1; i++) {
      if (!node[keys[i]] || typeof node[keys[i]] !== "object") node[keys[i]] = {}
      node = node[keys[i]]
    }
    node[keys[keys.length - 1]] = value
    root.cfg = next
    root.runCommand([root.cli, "set", path, String(value)])
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function applyState(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    root.stateLoaded = true
    root.activeState = !!s.enabled
    root.arming = !!s.pending
    root.remainingSec = Number(s.remainingSec) || 0
    root.inhibitAlive = !!s.inhibitAlive
    root.phase = String(s.phase || "off")
    root.language = String(s.language || "en")
    root.health = s.health || ({})
    root.digest = s.digest || ({})
    var hist = Array.isArray(s.digestHistory) ? s.digestHistory : []
    root.digestHistory = hist.slice().reverse()   // newest watch first
    root.autoInfo = s.auto || ({})
    root.retryInfo = s.retry || null
    root.autoTriggered = !!s.autoTriggered
    root.previewActive = !!(s.preview && s.preview.active)
    root.previewUntil = Number(s.preview && s.preview.until) || 0

    var incomingToken = String(s.pendingToken || "")
    if (incomingToken !== root.pendingToken) root.fireInFlight = false
    root.pendingToken = incomingToken

    // Arming always closes the digest face so the countdown (or the settings
    // panel's arming hero) is what the user sees, never a stale digest.
    if (root.arming && root.digestOpen) root.digestOpen = false

    if (s.config && (!root.popupOpen || Object.keys(root.cfg).length === 0))
      root.cfg = s.config
    if (!root.arming) root.fireInFlight = false

    // The countdown is ours: fire exactly once when the deadline passes.
    if (root.arming && root.remainingSec <= 0 && root.pendingToken !== "" && !root.fireInFlight) {
      root.fireInFlight = true
      root.runCommand([root.cli, "_arm-fire", root.pendingToken])
    }

    // Returning to the desktop ends the scene AND opens the watch digest,
    // so the handoff is already on screen (0 seconds). `wasLocked` guards
    // against the brief unlocked moment right after entering; `null` (IPC
    // failure) is never treated as unlocked.
    var locked = s.locked
    if (root.activeState && !root.arming) {
      if (locked === true) root.wasLocked = true
      else if (locked === false && root.wasLocked && !root.leaveInFlight) {
        root.leaveInFlight = true
        root.wasLocked = false
        root.runCommand([root.cli, "off"])
        if (!root.previewActive && !root.popupOpen && root.digestEnabled) {
          root.digestOrigin = "bar"
          root.digestOpen = true
        }
      }
    } else {
      root.wasLocked = false
      root.leaveInFlight = false
    }

    if (!root.stateLogged) {
      root.stateLogged = true
      console.log("Agent Ready state polling active")
    }
  }

  function triggerAutoArm() {
    if (root.arming || root.activeState || root.phase !== "off" || !root.stateLoaded) return
    // The monitor stays enabled during an auto countdown (for input-cancel),
    // so guard against re-arming here as well as in the CLI's pending dedupe.
    if (root.popupOpen || root.digestOpen || root.previewActive) return
    root.runCommand([root.cli, "auto-arm"])
  }

  function disarmAutoCountdown() {
    if (root.arming && root.autoTriggered && root.disarmOnInput)
      root.runCommand([root.cli, "disarm"])
  }

  function reconcile() {
    var now = Math.floor(Date.now() / 1000)
    if (root.activeState && !root.inhibitAlive && root.health.inhibitor === "lost")
      root.actOnce("repair", 6, [root.cli, "on"])
    // Only a changed monitor *set* needs a re-blank. A lit screen is normal
    // while surface.lock wakes it for face scan — blanking that breaks unlock.
    if (root.activeState && root.health.monitorsChanged === true)
      root.actOnce("reblank", 8, [root.cli, "reblank"])
    if (root.previewActive && root.previewUntil > 0 && now >= root.previewUntil && root.activeState)
      root.actOnce("previewEnd", 4, [root.cli, "off"])
    if (root.retryInfo && root.retryInfo.failed === true && root.phase === "off"
        && Number(root.retryInfo.count) < 3 && now >= Number(root.retryInfo.at))
      root.actOnce("retry", 6, [root.cli, "on"])
  }

  Process {
    id: stateProc
    command: [root.cli, "status-json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyState(text)
    }
  }

  Timer {
    // 500ms while active so the unlock -> restore handoff lands promptly;
    // 1s for countdown/panels, 5s when idle.
    interval: root.activeState ? 500
            : (root.arming || root.popupOpen || root.digestOpen) ? 1000 : 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: reconcileTimer
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: root.reconcile()
  }

  // Auto-arm uses its own IdleMonitor, independent of omarchy.idle (which is
  // disabled by the Stay Awake marker once the scene is active). The threshold
  // comes from status-json: a fixed value, or the system screensaver time minus
  // the countdown and a safety buffer.
  //
  // The monitor MUST stay enabled during an auto-triggered countdown when
  // disarmOnInput is on: disabling it would clear isIdle and both lose real
  // input events and fire a spurious cancel. Re-triggering is prevented by the
  // guards in triggerAutoArm(), not by turning the monitor off.
  //
  // While idle (the common case during a countdown) input is a real cancel, so
  // it cancels directly. While still idling, onIsIdleChanged false is not a
  // user event and must not fire.
  IdleMonitor {
    id: autoIdle
    enabled: root.stateLoaded && root.autoEnabled && root.autoAvailable
             && !root.popupOpen && !root.digestOpen
             && root.autoCooldown <= 0 && !root.previewActive
             && ((root.phase === "off" && !root.arming)
                 || (root.arming && root.autoTriggered && root.disarmOnInput))
    timeout: Math.max(1, root.autoThresholdSec)
    respectInhibitors: root.requireInhibitorsClear
    onIsIdleChanged: {
      if (isIdle) root.triggerAutoArm()
      else if (!isIdle) root.disarmAutoCountdown()
    }
  }

  onPopupOpenChanged: {
    confirmReset = false
    if (popupOpen) { root.digestOpen = false; refresh() }
  }

  // omarchy-shell eclipse.agent-ready open|close|toggle
  ShellIpc {
    target: "eclipse.agent-ready"
    function open(): void { root.popupOpen = true }
    function close(): void { root.popupOpen = false }
    function toggle(): void { root.popupOpen = !root.popupOpen }
  }

  implicitWidth: Style.bar.statusSlot
  implicitHeight: barSize

  WidgetButton {
    id: iconButton
    anchors.fill: parent
    bar: root.bar
    text: root.arming ? String(root.remainingSec) : String(root.cfgGet(".icons.active", "󰊚"))
    active: root.activeState || root.arming
    useActiveColor: false
    dimmed: !root.activeState && !root.arming
    tooltipText: {
      var idle = strings.t("tooltip.inactive")
      if (root.arming) return strings.t("tooltip.arming").arg(root.remainingSec)
      if (root.activeState) {
        var d = root.digest || ({})
        // A user-disabled inhibitor is not a fault; only a configured-but-lost
        // barrier is degraded.
        return (root.inhibitAlive || root.health.inhibitor === "disabled")
          ? strings.t("tooltip.activeDigest").arg(Number(d.agentsOnline) || 0)
          : strings.t("tooltip.degraded")
      }
      return idle
    }
    onPressed: function(button) {
      if (button === Qt.RightButton || button === Qt.MiddleButton)
        root.popupOpen = !root.popupOpen
      else
        root.runCommand([root.cli, "toggle"])
    }
  }

  // One PopupCard, three faces. Sharing the card keeps the popout coordinator
  // (one popup at a time) unambiguous.
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.cardOpen
    contentWidth: popup.fittedContentWidth(Style.space(root.panelWidth))
    // Fit the visible face's real height instead of hard-coded English line
    // counts. Chinese strings wrap differently; fixed heights either clip or
    // leave dead space. The settings face and the digest history keep a capped
    // scrolling area (the digest grows with the number of recorded watches).
    contentHeight: popup.fittedContentHeight(
        root.showArming ? armingCard.implicitHeight
      : root.showDigest ? Math.min(digestCard.desiredHeight, Style.space(430))
      : Style.space(430))

    Item {
      id: contentRoot
      anchors.fill: parent

      // ---------------- Arming card ----------------
      Column {
        id: armingCard
        anchors.fill: parent
        visible: root.showArming
        spacing: Style.space(9)

        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            id: armingHeroIcon
            textFormat: Text.PlainText
            text: String(root.cfgGet(".icons.active", "󰊚"))
            color: root.fg
            font.family: root.fontFam
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            width: parent.width - armingHeroIcon.implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: strings.t("hero.title")
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.subtitle
              font.bold: true
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              text: strings.t("arming.countdown").arg(root.remainingSec)
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.body
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Text {
          textFormat: Text.PlainText
          text: strings.t("arming.willDo")
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          width: parent.width
        }
        Text {
          textFormat: Text.PlainText
          text: root.armSummary()
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          width: parent.width
          wrapMode: Text.WordWrap
        }
        Text {
          textFormat: Text.PlainText
          text: root.autoTriggered ? strings.t("arming.hintAuto") : strings.t("arming.hint")
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          width: parent.width
          wrapMode: Text.WordWrap
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Button {
            width: root.allowEnterNow ? (parent.width - Style.space(8)) / 2 : parent.width
            text: strings.t("button.cancel")
            focusable: true
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.runCommand([root.cli, "disarm"])
          }
          Button {
            visible: root.allowEnterNow
            width: (parent.width - Style.space(8)) / 2
            text: strings.t("button.enterNow")
            focusable: true
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.runCommand([root.cli, "enter-now"])
          }
        }
      }

      // ---------------- Watch digest: full history ----------------
      // Header and actions stay put; the middle is a scrolling list of EVERY
      // completed watch (newest first), each richly described and localised.
      Item {
        id: digestCard
        anchors.fill: parent
        visible: root.showDigest

        readonly property real desiredHeight:
            digestHeader.implicitHeight + Style.space(9)
            + (digestSep.implicitHeight || Style.space(1)) + Style.space(9)
            + digestListColumn.implicitHeight + Style.space(9)
            + digestButtons.implicitHeight + Style.space(4)

        Row {
          id: digestHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(10)
          Text {
            id: digestHeroIcon
            textFormat: Text.PlainText
            text: String(root.cfgGet(".icons.active", "󰊚"))
            color: root.fg
            font.family: root.fontFam
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            width: parent.width - digestHeroIcon.implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: strings.t("digest.title")
              color: root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.subtitle
              font.bold: true
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              text: strings.t("digest.subtitle")
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }
        }

        PanelSeparator {
          id: digestSep
          anchors.top: digestHeader.bottom
          anchors.topMargin: Style.space(9)
          anchors.left: parent.left
          width: parent.width
          foreground: root.fg
        }

        QQC.ScrollView {
          id: digestScroll
          anchors.top: digestSep.bottom
          anchors.topMargin: Style.space(9)
          anchors.bottom: digestButtons.top
          anchors.bottomMargin: Style.space(9)
          anchors.left: parent.left
          anchors.right: parent.right
          clip: true
          QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
          QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded

          Column {
            id: digestListColumn
            width: digestScroll.availableWidth
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              visible: root.digestHistory.length > 0
              text: strings.t("digest.count").arg(root.digestHistory.length)
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              visible: root.healthSummary() !== ""
              text: strings.t("digest.degraded") + root.healthSummary()
              color: Qt.darker(root.fg, 1.3)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              visible: !root.digestEnabled
              text: strings.t("digest.disabled")
              color: Qt.darker(root.fg, 1.3)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }
            Text {
              textFormat: Text.PlainText
              visible: root.digestHistory.length === 0
              text: strings.t("digest.empty")
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: root.digestHistory
              delegate: Column {
                required property var modelData
                width: digestListColumn.width
                spacing: Style.space(3)
                PanelSeparator { width: parent.width; foreground: root.fg }
                Text {
                  textFormat: Text.PlainText
                  text: root.digestRecordLines(modelData)
                  color: root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.bodySmall
                  width: parent.width
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }

        Row {
          id: digestButtons
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(8)
          Button {
            width: (parent.width - Style.space(8)) / 2
            text: strings.t("button.back")
            focusable: true
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.digestBack()
          }
          Button {
            width: (parent.width - Style.space(8)) / 2
            text: strings.t("button.armAgain")
            focusable: true
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: { root.digestOpen = false; root.runCommand([root.cli, "arm"]) }
          }
        }
      }

      // ---------------- Settings panel: fixed information bar ----------------
      // The name + current state are an information bar, not a section: they
      // stay pinned at the top while the settings below scroll. Kept as direct
      // children of contentRoot (siblings of the ScrollView), so no extra
      // nesting and the card layout stays unchanged.
      Item {
        id: settingsHero
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: implicitHeight
        implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)
        visible: root.showSettings

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          text: String(root.cfgGet(".icons.active", "󰊚"))
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: heroText
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(12)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            text: strings.t("hero.title")
            color: root.fg
            font.family: root.fontFam
            font.pixelSize: Style.font.subtitle
            font.bold: true
            width: parent.width
          }
          Text {
            textFormat: Text.PlainText
            text: root.arming ? strings.t("hero.arming").arg(root.remainingSec)
                : root.activeState
                    ? ((root.inhibitAlive || root.health.inhibitor === "disabled")
                        ? strings.t("hero.active") : strings.t("hero.degraded"))
                    : strings.t("hero.off")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
          Text {
            textFormat: Text.PlainText
            visible: root.healthSummary() !== ""
            text: strings.t("digest.degraded") + root.healthSummary()
            color: Qt.darker(root.fg, 1.3)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
        }
      }
      PanelSeparator {
        id: settingsHeroSep
        anchors.top: settingsHero.bottom
        anchors.topMargin: Style.space(9)
        anchors.left: parent.left
        width: parent.width
        visible: root.showSettings
        foreground: root.fg
      }

      // ---------------- Settings panel: scrolling body ----------------
      QQC.ScrollView {
        id: scroll
        anchors.top: settingsHeroSep.bottom
        anchors.topMargin: Style.space(9)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.showSettings
        clip: true
        QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
        QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded

        Column {
          id: column
          width: scroll.availableWidth
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(8)
            Button {
              width: (parent.width - Style.space(8)) / 2
              text: root.arming ? strings.t("button.cancel")
                  : root.activeState ? strings.t("button.turnOff") : strings.t("button.turnOn")
              focusable: true
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: root.runCommand([root.cli, root.arming ? "disarm" : "toggle"])
            }
            Button {
              width: (parent.width - Style.space(8)) / 2
              text: root.confirmReset ? strings.t("button.resetConfirm") : strings.t("button.reset")
              focusable: true
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: {
                if (root.confirmReset) {
                  root.runCommand([root.cli, "reset-config"])
                  root.confirmReset = false
                } else root.confirmReset = true
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Button {
              width: root.digestEnabled ? (parent.width - Style.space(8)) / 2 : parent.width
              text: strings.t("button.preview")
              focusable: true
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: root.runCommand([root.cli, "preview"])
            }
            Button {
              visible: root.digestEnabled
              width: (parent.width - Style.space(8)) / 2
              text: strings.t("button.digest")
              focusable: true
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: {
                root.popupOpen = false
                root.digestOrigin = "settings"
                root.digestOpen = true
              }
            }
          }

          // Before entering
          PanelSeparator { foreground: root.fg }
          PanelSectionHeader {
            text: strings.t("section.timing")
            foreground: root.fg
            fontFamily: root.fontFam
          }

          NumberField {
            label: strings.t("field.delay")
            value: Number(root.cfgGet(".arm.delaySec", 3))
            from: 3
            to: 60
            stepSize: 1
            foreground: root.fg
            fontFamily: root.fontFam
            onModified: function(v) { root.setCfg(".arm.delaySec", v) }
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.notify")
            description: strings.t("toggle.notifyDesc")
            checked: root.cfgGet(".arm.notify", false) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".arm.notify", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.enterNow")
            description: strings.t("toggle.enterNowDesc")
            checked: root.allowEnterNow === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".arm.allowEnterNow", !checked)
          }

          // Auto
          PanelSeparator { foreground: root.fg }
          PanelSectionHeader {
            text: strings.t("section.auto")
            foreground: root.fg
            fontFamily: root.fontFam
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.auto")
            description: strings.t("toggle.autoDesc")
            checked: root.cfgGet(".auto.enabled", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".auto.enabled", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.disarmOnInput")
            description: strings.t("toggle.disarmOnInputDesc")
            checked: root.cfgGet(".auto.disarmOnInput", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".auto.disarmOnInput", !checked)
          }
          Text {
            textFormat: Text.PlainText
            text: strings.t("auto.status").arg(root.autoThresholdSec)
                + (root.autoAvailable ? "" : " · " + strings.t("auto.unavailable"))
                + (root.autoCooldown > 0 ? " · " + strings.t("auto.cooldown").arg(root.autoCooldown) : "")
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          // While active
          PanelSeparator { foreground: root.fg }
          PanelSectionHeader {
            text: strings.t("section.active")
            foreground: root.fg
            fontFamily: root.fontFam
          }

          Toggle {
            width: parent.width
            label: strings.t("toggle.inhibit")
            description: strings.t("toggle.inhibitDesc")
            checked: root.cfgGet(".inhibit.enabled", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".inhibit.enabled", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.idle")
            description: strings.t("toggle.idleDesc")
            checked: root.cfgGet(".idle.linkStayAwake", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".idle.linkStayAwake", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.power")
            description: strings.t("toggle.powerDesc")
            checked: root.cfgGet(".powerProfile.enabled", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".powerProfile.enabled", !checked)
          }
          // Same pattern as Omarchy's power panel: evenly divided bordered
          // chips, so the row fills the card in every language.
          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3
            Repeater {
              model: [
                { value: "balanced", label: strings.t("profile.balanced") },
                { value: "power-saver", label: strings.t("profile.powerSaver") },
                { value: "performance", label: strings.t("profile.performance") }
              ]
              Button {
                required property var modelData
                width: profileRow.cellWidth
                text: String(modelData.label)
                bordered: true
                selected: String(modelData.value) === String(root.cfgGet(".powerProfile.profile", "balanced"))
                focusable: true
                foreground: root.fg
                fontFamily: root.fontFam
                onClicked: root.setCfg(".powerProfile.profile", String(modelData.value))
              }
            }
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.lock")
            description: strings.t("toggle.lockDesc")
            checked: root.cfgGet(".screen.lock", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".screen.lock", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.dpms")
            description: strings.t("toggle.dpmsDesc")
            checked: root.cfgGet(".screen.dpmsOff", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".screen.dpmsOff", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.kbd")
            description: strings.t("toggle.kbdDesc")
            checked: root.cfgGet(".screen.keyboardBacklightOff", true) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".screen.keyboardBacklightOff", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.mute")
            description: strings.t("toggle.muteDesc")
            checked: root.cfgGet(".audio.mute", false) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".audio.mute", !checked)
          }

          // Advanced
          PanelSeparator { foreground: root.fg }
          PanelSectionHeader {
            text: strings.t("section.advanced")
            foreground: root.fg
            fontFamily: root.fontFam
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.suspendSinks")
            description: strings.t("toggle.suspendSinksDesc")
            checked: root.cfgGet(".audio.suspendSinks", false) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".audio.suspendSinks", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.freeze")
            description: strings.t("toggle.freezeDesc")
            checked: root.cfgGet(".freeze.enabled", false) === true
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".freeze.enabled", !checked)
          }
          Toggle {
            width: parent.width
            label: strings.t("toggle.digest")
            description: strings.t("toggle.digestDesc")
            checked: root.digestEnabled
            foreground: root.fg
            fontFamily: root.fontFam
            onClicked: root.setCfg(".digest.enabled", !checked)
          }

          // Language — a plugin-only option, kept down here in Advanced.
          // `auto` follows Setup > Language; a concrete code overrides it for
          // this plugin alone. The two language names are native names so they
          // stay recognisable in every UI language.
          PanelSeparator { foreground: root.fg }
          PanelSectionHeader {
            text: strings.t("section.language")
            foreground: root.fg
            fontFamily: root.fontFam
          }
          Row {
            id: languageRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3
            Button {
              width: languageRow.cellWidth
              text: strings.t("lang.system")
              bordered: true
              selected: String(root.cfgGet(".language", "auto")) === "auto"
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: root.setCfg(".language", "auto")
            }
            Button {
              width: languageRow.cellWidth
              text: strings.t("lang.english")
              bordered: true
              selected: String(root.cfgGet(".language", "auto")) === "en"
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: root.setCfg(".language", "en")
            }
            Button {
              width: languageRow.cellWidth
              text: strings.t("lang.chinese")
              bordered: true
              selected: String(root.cfgGet(".language", "auto")) === "zh-CN"
              focusable: true
              foreground: root.fg
              fontFamily: root.fontFam
              onClicked: root.setCfg(".language", "zh-CN")
            }
          }
          Text {
            textFormat: Text.PlainText
            text: strings.t("lang.hint")
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            text: strings.t("hint.nextEnter")
            color: Qt.darker(root.fg, 1.5)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
