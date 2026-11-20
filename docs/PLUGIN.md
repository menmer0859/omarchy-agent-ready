# eclipse.agent-ready — bar widget

The status-bar front end for [Agent Ready](../README.md) (full CLI/config docs: [CLI.md](CLI.md)).
It replaces the earlier `type: command` module, which could only run a shell
command and therefore had no way to open a real panel.

## Conventions followed

This plugin is built the way Omarchy's own bar panels are:

- **`BarWidget`** as the entry point (`barWidget` in `manifest.json`), with
  `bar`, `moduleName` and `settings` injected by the host.
- **`WidgetButton`** for the bar icon: shared tooltip, press feedback, theme
  colors and the `pressed(int button)` signal (left / right / middle).
- **One `PopupCard` with three faces** — an arming card while a countdown runs,
  the settings panel otherwise, and a digest face when a watch is being shown.
  It grows out of the icon and fades using
  `Style.duration`, anchors to the bar, and registers with
  `bar.requestPopout` / `releasePopout` so only one popup is open at a time.
  No hand-written open/close animation, and no two competing popups.
- **A single face selector** (`settings / arming / digest / closed`) drives the
  visible face and the card's open state, so contradictory boolean combinations
  cannot open an empty popup.
- **Kit content components**: `PanelSectionHeader`, `PanelSeparator`, `Toggle`,
  `NumberField`, `Button`, `QQC.ScrollView` — all theme-driven through `Style`
  tokens and `Commons.Color`. Mutually-exclusive option rows (power profile,
  language) use a `Row` + `Repeater` of `bordered` buttons with an evenly
  divided `cellWidth`, matching Omarchy's own power panel.
- **`PluginI18n.qml`**, a self-contained twin of `Commons.Translations` with a
  **writable** `language` (the shared kit binds it readonly to the system-wide
  `I18n.language`). Flat `i18n/*.json` catalogs; every displayed string is
  `Text.PlainText` and translatable. Missing keys fall back through the base
  language, then `en.json`. This is what lets the panel's Language picker
  switch the UI independently of the system language, with no restart.
- **State stays in the CLI.** The widget polls `status-json` (1 s while arming
  or while the panel is open, 5 s otherwise) and writes config through `set`.

## argv-vector CLI calls — no `execDetached`

Every CLI call goes through a **serialized queue of `Quickshell.Io.Process`
objects with argv arrays**, never through `bar.run()` / `Util.execDetached` /
`bash -lc`:

```qml
readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omarchy-agent-ready"
root.runCommand([root.cli, "toggle"])
```

This is both safer (no shell parsing, no `shellQuote` needed for dynamic
values) and deliberate: `Quickshell.execDetached(["bash","-lc",...])` produced
an audible codec pop on this Surface Laptop 5 when the shell spawned a child.
A command queue prevents rapid config edits from colliding.

## The widget owns the countdown

`omarchy-agent-ready arm` only writes one `pending.json` with a token and a
deadline — it starts **no background worker**. While `pending` is true the
widget polls once a second, shows the remaining seconds on the bar icon and on
an automatically-opened arming card, and when `remainingSec` reaches 0 calls:

```
omarchy-agent-ready _arm-fire <token>
```

The CLI re-checks the token, so a cancelled arm, a re-arm, or a second widget
instance (one per monitor) can never enter the mode twice. This mirrors the
shared-kit principle of not animating / not spawning what the shell can own.

Desktop notifications are **off by default** (`arm.notify: false`) — the bar
card is the primary prompt; Bark (`arm.bark.*`) is available for remote push.

## Unlocking ends the scene

`status-json` reports `locked` (true / false / `null` = IPC unknown) while the
scene is active. The widget remembers that it saw a real lock (`wasLocked`) and,
on the **locked → unlocked** transition, queues a single `off` command. That
restores audio, power profile, backlight and display, releases the suspend
inhibitor and clears the Stay Awake marker, so the coffee icon is disabled
again when the user is back at the desktop. `null` is never treated as
unlocked, and `leaveInFlight` prevents duplicate `off` calls from the
per-monitor widget instances.

## Automatic entry

The widget owns a second `IdleMonitor` (`Quickshell.Wayland`,
`respectInhibitors: true`), independent of `omarchy.idle`. When it goes idle
and all guards pass (`stateLoaded`, `auto.enabled`, `auto.available`,
`phase === "off"`, no popup, no cooldown, not in preview), it calls `auto-arm`.
The threshold comes from `status-json.auto.thresholdSec` — a fixed
`auto.armAfterSec`, or the system screensaver time minus the countdown and a
safety buffer. A synthetic remote-desktop input resets the monitor, so working
remotely never triggers auto-arm. Input during an auto countdown calls
`disarm` (`auto.disarmOnInput`).

## Watch digest (full history & 0-second handoff)

`status-json` carries `digest` (the current/last watch), `digestHistory` (every
completed watch, newest last) and `health`. The CLI writes one structured,
language-neutral record per watch into `history.json`; the panel formats and
translates all of it (`fmtTime`, `fmtDuration`, `digestRecordLines`), rendering
number, start/end, duration, trigger, **agent names**, actions, power profile,
counts, pending items and note.

The card has a third face: on the **locked → unlocked** transition the widget
queues `off` **and** opens the digest face, so the summary is on screen the
moment the user is back. Its header and action row are fixed; the middle is a
`QQC.ScrollView` listing **all** watches, newest first, with a capped card
height so long histories scroll instead of growing the popup.

The **Back** button returns to where the card was opened from. `digestOrigin`
is set to `"settings"` by the panel's "Watch digest" button (Back reopens the
settings panel) or `"bar"` on the unlock handoff (Back closes the card to the
plain bar). "Arm again" starts a new watch. The bar tooltip shows a one-line
summary while active; a ⚠ badge appears whenever `health` is degraded.

`digest.enabled` (Advanced, default `true`) gates the whole feature: off stops
recording, disables the unlock auto-open and hides the "Watch digest" button,
while keeping the existing history.

## Reconcile & resilience

A 2 s `Timer` runs `reconcile()` with rate-limited actions (`actOnce`):
re-hang a lost inhibitor (`on` is re-entrant), `reblank` outputs only when the
monitor **set** changes (`health.monitorsChanged`), end `preview` at its
deadline, and perform a bounded retry after a lock failure. `health.dpmsLit`
is informational only — while `surface.lock` is active it owns display state
and legitimately wakes the screen for face scan; re-blanking on a lit screen
would fight its WAKE/BLANK state machine and break unlock. `phase`
(`off / arming / applying / active / restoring`) prevents double clicks while
lock/DPMS actions are in flight. All CLI calls go through the argv-vector
command queue; `flock -w 3` in the CLI absorbs the two per-monitor instances
issuing the same unlock command.

## Interaction

| Input | Action |
|---|---|
| Left click | `toggle` → arm (countdown + card), cancel the countdown, or leave |
| Right click | Open/close the settings panel |
| Middle click | Same as right click |
| Bar icon while arming | Shows the remaining seconds, updated every second |
| Arming card | Countdown, "About to:" action summary, Cancel / Enter now |
| Digest card | All watches (scrollable, newest first), ⚠ health, **Back** (returns to the settings panel or the bar) / Arm again — opens automatically on unlock |
| Settings panel | Fixed "Agent Ready / state" header + scrolling sections; "Try it" (`preview`) and "Watch digest" buttons |

The **Agent Ready / state** hero is a fixed information bar, pinned at the top
of the settings face while the sections scroll beneath it (it is a sibling of
the `ScrollView`, not a child).

The settings panel has four sections — **Before entering** (delay, optional
desktop notification, "Enter now"), **Automatic** (auto-arm), **While active**
(suspend block, Stay Awake link, power profile + profile picker, lock, DPMS,
keyboard backlight, mute) and **Advanced** (suspend sinks, freeze non-essential
processes, the digest switch, and the per-plugin **Language / 语言** picker at
the very bottom) — plus the fixed hero and buttons to turn on/off, try it, open
the digest, and reset the config. Reset needs two clicks to confirm. Changes are
written immediately; most apply the next time Agent Ready turns on.

The **Language** picker and the **digest switch** are the exceptions: they
apply immediately. Choosing a concrete code writes `config.language`, the CLI
resolves it into the effective code (`status-json.language`), and the widget
feeds that into `PluginI18n.language`, so all `t()` bindings — including the
digest history — re-render within about a second, no restart and no change to
the system language.

## IPC

```
omarchy-shell eclipse.agent-ready open
omarchy-shell eclipse.agent-ready close
omarchy-shell eclipse.agent-ready toggle
```

Useful for a keybinding that jumps straight to the settings panel, e.g. in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + SHIFT + A", "Agent Ready settings", "omarchy-shell eclipse.agent-ready toggle")
o.bind("SUPER + CTRL + A", "Toggle Agent Ready", "omarchy-agent-ready toggle")
```

## Adding a language

Copy `i18n/en.json` to `i18n/<code>.json` (codes are listed in
`/usr/share/omarchy/default/i18n/locales.json`) and translate the values.
Keep `%1` placeholders whole and use `%1` with `.arg()`; the catalog falls
back to `en.json` for missing keys.

These catalogs are the **single source of truth for both surfaces**: the QML
widget reads them through `PluginI18n`, and the `omarchy-agent-ready` CLI reads
the same files for every notification (`notify.*`, `status.*`, `summary.*`)
using its own `t()` helper. The CLI is the single authority that resolves the
effective code — `config.language` (`auto` / `en` / `zh-CN`) over the system
`~/.config/omarchy/language`, with `OMARCHY_LANGUAGE_FILE` as a test override —
and reports it in `status-json.language`; the widget feeds that into
`PluginI18n.language`. So translating one file (and picking its code in the
panel) switches the panel, the cards, the desktop notifications, the Bark
pushes, the Waybar tooltip **and the whole digest history** (records store
timestamps/seconds/keys, never translated text) all at once — no code changes
and no restart. `omarchy-agent-ready lang` shows which code the CLI resolved.

For a fourth language, also add a button for its code to the Language `Row`
(now at the bottom of **Advanced**) in `Widget.qml` and widen `cellWidth`
accordingly. Keep the language names as native names (as `English` / `简体中文`
are) so they stay recognisable in every UI language.

## Note

A newly added plugin is only registered with the bar after the shell restarts:
`omarchy restart shell`. `omarchy-shell shell rescanPlugins` reloads changed
plugin files but does not register a brand-new bar-widget id. Multi-monitor
setups create one widget instance per screen; the `ShellIpc` "handler already
registered" warnings in the journal are expected and harmless.
