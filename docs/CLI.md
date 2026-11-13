---
title: Agent Ready CLI and configuration reference
type: cli-reference
date: 2026-11-13
status: release-preparation
canonical_path: /home/eclipse/omarchy-agent-ready-release/docs/CLI.md
---

# Agent Ready — CLI and configuration reference

## TLDR

For developers and users configuring Agent Ready **1.1.0**: the release author is
**menmer0859**, the repository is https://github.com/menmer0859/omarchy-agent-ready
(clone: https://github.com/menmer0859/omarchy-agent-ready.git), and the plugin id
remains **`eclipse.agent-ready`**.

**`agents.allow` defaults to `[]`. You must configure your own process names.**
An empty list means no configured names for automatic agent detection; it does
not disable the suspend inhibitor or change the power scene. Detection counts
matching process-name kinds, not PIDs or command-line/path mentions. Agents whose
process name is still `node` or `python` cannot be identified as individual
agents this way; do not add generic interpreter names just to inflate the count.
Hooks can supply a precise `agents` array using `digest set` instead.

## Evidence and path conventions

The configuration template is
`/home/eclipse/omarchy-agent-ready-release/config/config.json`; detection and
freeze protection are implemented separately in
`/home/eclipse/omarchy-agent-ready-release/bin/omarchy-agent-ready`
(`agent_names`, `load_agent_allow`, `is_agent_cmd`). Release defaults above are
the publication baseline, not a claim of new live-system verification.

Repository references use `/home/eclipse/omarchy-agent-ready-release` as the
absolute local checkout. Installed paths use `$HOME`, which the shell expands
to **the installing user's own absolute home**, not the author's `/home/eclipse`.
Surface audio and `surface.lock` observations below are author-machine history,
not requirements for other machines. Operational examples below are documentation;
commands that arm, preview, modify state or control power require an appropriate
isolated test environment or explicit permission before execution.

## Setup steps — configure agent names first

Inspect your process names and substitute the actual names in the example list.
The CLI `set` command only parses booleans, integers and strings, **not JSON
arrays**. Edit `$HOME/.config/omarchy/agent-ready/config.json` directly, or use
this same-directory temporary-file update (back up your config first; run only
when no panel or other process is editing it):

```bash
ps -eo comm= | sort -u
(
  set -e
  config="$HOME/.config/omarchy/agent-ready/config.json"
  tmp=$(mktemp "${config}.tmp.XXXXXX")
  trap 'rm -f -- "$tmp"' EXIT
  jq '.agents.allow = ["pi", "codex"]' "$config" > "$tmp"
  chmod --reference="$config" "$tmp"
  mv -- "$tmp" "$config"
)
omarchy-agent-ready config-json | jq '.agents.allow'
omarchy-agent-ready doctor
```

The old list of 13 names (`pi`, `oh-my-pi`, `pyagent`, `py-agent`, `hermes`,
`opencode`, `cindy`, `codex`, `chatgpt`, `magpie`, `claude`, `grok`, `omp`)
is **only the historical author's machine list**, not a recommended default.
**An empty allow-list also provides no freeze protection for agents.** Before
enabling experimental freeze, you must configure the allow-list and review both
`.freeze.patterns` and allow-list protection; freezing is disabled by default. A hook can publish names separately:

```bash
omarchy-agent-ready digest set '{"agents":["my-node-agent","my-python-agent"]}'
```

This writes digest state; it does not change process detection or freeze protection.

## Path index

- Developer history and pitfalls: `/home/eclipse/omarchy-agent-ready-release/docs/DEVELOPMENT.md`.
- Widget internals: `/home/eclipse/omarchy-agent-ready-release/docs/PLUGIN.md`.
- User installation guide: `/home/eclipse/omarchy-agent-ready-release/README.md`.
- Installed configuration: `$HOME/.config/omarchy/agent-ready/config.json`.

## Overview

A third power scene for Omarchy, sitting alongside the built-in **Stay Awake**
switch. It is for the case where you step away but want every background agent
(pi / PyAgent / Hermes / OpenCode / Cindy / ChatGPT-Codex / magpie / …) to keep
running and stay reachable, while everything that is not needed — the screen,
speakers, keyboard backlight, CPU appetite — powers down.

It is **not** a `power-profiles-daemon` toggle and it is **not** the Stay Awake
button. It composes several existing Omarchy primitives into one switch.

## What the switch actually does

| | idle screensaver / lock | system suspend | display | audio | power profile | agents |
|---|---|---|---|---|---|---|
| Default (allow idle) | 150s / 300s | normal | on | normal | current | normal |
| Stay Awake | **off** | normal | stays on | normal | unchanged | benefits |
| **Agent Ready** | **off** | **blocked (incl. lid)** | **off + locked** | muted | `balanced` | **online** |

### Arming: a bar card, not a system notification

Clicking the icon does **not** lock the screen immediately. It first *arms*:

1. The bar icon turns into a **live countdown** (`3 2 1`).
2. A **QML card grows out of the icon**, explaining exactly what is about to
   happen and how many seconds are left, with **取消 / 立即进入** buttons.
3. Clicking the icon again (or 取消) aborts without changing anything;
   立即进入 skips the wait.

Only when the countdown finishes does the mode engage. The delay is
`arm.delaySec` (default 3 s; 3–60 in the panel) and can be disabled with
`arm.enabled: false` for instant entry.

**The countdown is owned by the bar widget**, not by a background process: while
pending, the plugin polls `status-json` once a second and calls
`_arm-fire <token>` when the deadline passes. A token check makes cancelled and
re-armed countdowns harmless. There is **no detached worker**, no repeated
pending-file churn, and — importantly — **no `Quickshell.execDetached` /
`bash -lc`** anywhere in the click path (that path produced an audible codec
pop on some Surface machines).

Desktop notifications are **off by default** (`arm.notify: false`): a card on a
locked, blanked screen is useless anyway. Re-enable them if you want, or push to
your phone with Bark (`arm.bark.*`).

### Entering Agent Ready, in order

1. Holds a `systemd-inhibit --what=sleep:idle --mode=block` barrier. This is the
   same mechanism `magpie` already uses while agents are active
   (`--why=Agents are working through magpie`); Agent Ready adds a permanent
   one so the machine stays up even between agent turns.
2. Turns on Omarchy's own **Stay Awake** marker
   (`$HOME/.local/state/omarchy/indicators/stay-awake`), so `omarchy.idle` stops
   the 150s screensaver and 300s auto-lock. The idle service watches that file
   and picks the change up live.
3. Switches the power profile to `balanced` (configurable). `performance` is
   restored on exit if it was the pre-entry profile (the snapshot, not a fixed
   `performance` default, controls restoration). Uses `powerprofilesctl` directly,
   so your saved AC/battery preferences in
   `$HOME/.local/state/omarchy/powerprofiles/` are untouched.
4. Optionally mutes the output sink (**off by default** — see `audio.mute` below).
5. Turns off the keyboard backlight; optionally dims the panel backlight.
6. Locks the session with `omarchy-system-lock`, then blanks all outputs via
   DPMS. Hyprland re-lights the screen on keypress/mouse move when you return.
7. Optionally freezes non-essential processes (see below).
8. Runs every `*.sh` in `$HOME/.config/omarchy/agent-ready/enter.d/`.

Leaving reverses all of it from a snapshot taken on the way in. It **does not
unlock the session** — unlock normally, then click the bar icon. Only the Stay
Awake marker that Agent Ready itself enabled is removed; if you had Stay Awake
on already, it stays on.

State, the pre-entry snapshot, the pending countdown, the inhibitor PID and a
log live in `$HOME/.local/state/omarchy/agent-ready/`.

## Coming back: unlocking ends the scene

Agent Ready is **not** a mode you stay in while using the computer. The bar
widget watches the session lock (`omarchy-shell lock status`, surfaced as
`locked` in `status-json`) and, when it sees **locked → unlocked** while active,
it runs `off` automatically:

- releases the suspend inhibitor and clears the Stay Awake marker — the coffee
  icon goes back to **disabled**
- restores audio, power profile, keyboard backlight and display
- writes `enabled: false`, so the bar icon returns to its idle state

A `wasLocked` guard stops the brief unlocked moment right after entering (before
the session lock is secure) from ending the scene immediately. A failed IPC
yields `locked: null` and is never treated as "unlocked". Polling is every 500 ms
while active, so the restore normally lands within about a second of unlocking.

If `screen.lock` is disabled there is no lock transition to observe — click the
icon to leave instead. In the author's historical setup, `surface.lock` wakes the
display a few seconds after locking (to show the lock UI / prepare Howdy face
unlock) and can unlock by face without a keypress; that is the lock plugin's own
behaviour. The automatic restore happens on unlock either way.

## Automatic entry (idle)

The bar widget owns a second, independent `IdleMonitor` (`respectInhibitors:
true`), so it does not depend on `omarchy.idle` (which is disabled by the Stay
Awake marker once the scene is active). After a period with no local input it
calls `auto-arm`; the normal countdown and arming card still run.

`auto.armAfterSec: null` (default) **follows the system**: the script takes
`min(idle.screensaver, idle.lock)` from `$HOME/.config/omarchy/shell.json`, subtracts `arm.delaySec`
and a 30 s safety buffer (floor 30 s). With the stock `150 / 300` this gives
117 s — the countdown always finishes before the system screensaver starts. If
the system idle times are too short, auto-arm is reported as **unavailable**
(`health.auto: degraded`) instead of racing the screensaver. A fixed value can
be set with `omarchy-agent-ready set .auto.armAfterSec 60`.

Auto-arm only fires when **all** hold: `phase === off`, not in cooldown, panel
closed, not locked, no Wayland idle inhibitor, and the monitor reports idle.
Synthetic input from a remote desktop resets the monitor, so working remotely
does not trigger it. An auto countdown is cancelled by any input
(`auto.disarmOnInput`), and `auto.cooldownSec` (60 s) prevents re-arming right
after you return. Since nobody is at the screen when auto-arm fires, set
`arm.bark.*` + `auto.barkNotify` if you want a phone push instead of the local
card.

## Watch digest — full history & 0-second handoff

Two files in `$HOME/.local/state/omarchy/agent-ready/`:

- `$HOME/.local/state/omarchy/agent-ready/digest.json` — the **current / last** watch. Built-in fields
  (`agentsOnline`, `uptimeMin`, `lastEvent`) refresh on enter/leave; external
  fields (`completed`, `failed`, `pending`, `note`, `agents`) come from hooks or
  `digest set` and are preserved verbatim.
- `$HOME/.local/state/omarchy/agent-ready/history.json` — a rolling array of **every completed watch** (newest last,
  capped at 200). Appended once on `off`, only when the watch really ran.

Each history record is fully structured and **language-neutral**, so the panel
can translate it into whatever language is active when you read it:

| Field | Meaning |
|---|---|
| `seq`, `since`, `until`, `durationSec` | number, ISO start/end, exact duration |
| `trigger` | `manual` / `auto` / `preview` |
| `agents[]`, `agentsOnline` | **agent names** detected during the watch (or the hook-supplied `agents` array), and their count |
| `actions[]` | catalog keys for the measures that were in effect (rendered via `summary.*`) |
| `powerProfile` | the profile in use |
| `completed`, `failed`, `pending`, `note`, `lastEvent` | external digest fields, carried into the record |

No agent session log is parsed — formats are unstable. Hooks (see below) are
the extension point for Cindy sessions, HA, Bark, NAS archiving, etc.

```bash
omarchy-agent-ready digest set '{"completed":3,"pending":["check backup"],"note":"ok"}'
omarchy-agent-ready digest get          # current/last watch
omarchy-agent-ready digest history     # every watch as JSON
omarchy-agent-ready digest clear       # erase digest + whole history
```

The digest card shows **all** watches, newest first, each with its number,
start/end time, duration, trigger, agent names, actions, counts and note.
Its **Back** button returns to wherever it was opened from: the settings panel
(if launched from there) or the plain bar (when it appeared on unlock). "Arm
again" starts a new watch.

Presentation layers: the bar tooltip shows a one-line summary while active;
**unlocking automatically opens the digest card** (the handoff is on screen the
moment you are back); and hooks can push the same data to Bark / HA. The digest
is shown on the **unlocked desktop**, never on the lock screen.

The whole feature is switchable — `digest.enabled` (default `true`) in
**Advanced**. Off means: no new records, no auto-open on unlock, and the
"Watch digest" button is hidden. Existing history is kept and becomes visible
again when re-enabled.

## Resilience

- `status-json.phase`: `off → arming → applying → active → restoring → off`.
  The intermediate phases prevent double clicks while lock/DPMS actions are in
  flight.
- A **2 s reconcile tick** re-hangs a lost inhibitor, re-blanks outputs **only
  when the set of connected monitors changes** (`health.monitorsChanged`), ends
  `preview` on time, and performs a bounded retry after a lock failure.
  Rate-limited so a lasting condition cannot flood the command queue.
  `health.dpmsLit` is informational only: while a session lock is active the
  lock plugin legitimately wakes the screen for face scan, so Agent Ready must
  never re-issue DPMS off in response to a lit screen.
- A failed `omarchy-system-lock` **rolls the whole scene back to `off`** (never
  half-enabled) and schedules up to 3 retries (`enter.retrySec`).
- `health` exposes `inhibitor / lock / dpms / audio / auto` as
  `ok / unknown / failed / degraded`; the panel shows a ⚠ badge.
- `preview` is a self-contained rehearsal: short countdown → active → auto
  restore after `preview.durationSec`, with no desktop notifications.
- `flock -w 3` lets the two per-monitor widget instances issue the same unlock
  command without a spurious `ERROR`.

## Display language & notifications

Every user-facing string — the bar widget's panel/cards **and** the CLI
notifications (arming, cancelled, enter, leave, action buttons, Bark pushes and
the legacy Waybar tooltip) — is translated from the same catalogs. Which
language is used is decided **per plugin**, independently of the system:

| `config.language` | Behaviour |
|---|---|
| `"auto"` (default) | Follow the system language from **Setup → Language** (`$HOME/.config/omarchy/language`). |
| `"en"` | Force English for this plugin only. |
| `"zh-CN"` | Force 简体中文 for this plugin only. |

Pick it at the bottom of the panel under **Advanced → Language / 语言**
(`Follow system` / `English` / `简体中文`), or with
`omarchy-agent-ready set .language en|zh-CN|auto`.
**Only this plugin's panel and notifications change** — the shell, other apps
and `$HOME/.config/omarchy/language` are untouched. Switching takes effect within
about a second, with no restart: the CLI is the single authority that resolves
the effective code and reports it in `status-json.language`; the widget feeds
that into its own `PluginI18n` (a `Commons.Translations` twin with a writable
`language`), so every `t()` binding re-renders live.

All strings come from one place: the plugin's
`$HOME/.config/omarchy/plugins/eclipse.agent-ready/i18n/*.json` catalogs
(`/home/eclipse/omarchy-agent-ready-release/i18n/en.json` and
`/home/eclipse/omarchy-agent-ready-release/i18n/zh-CN.json` in the checkout). The CLI resolves regional codes against the
catalogs that exist (base language → English → key), substitutes `%1`/`%2`
placeholders, and honours `OMARCHY_LANGUAGE_FILE` as a test override (it takes
precedence over the plugin setting). `omarchy-agent-ready lang` prints the
effective code; `status-json` exposes both `language` (effective) and
`languageMode` (your `auto` / `en` / `zh-CN` choice). The language names in the
picker are written in their own language on purpose, so `简体中文` stays
recognisable even while the UI is in English.

Notification templates can still be overridden per string with `.labels.*` in
`$HOME/.config/omarchy/agent-ready/config.json` (see the table below). An override is used verbatim (legacy `%S`
= seconds, `%A` = action summary), so write it in the language you want. Left
empty — the default — the localized catalogs win. To add a third language,
copy `/home/eclipse/omarchy-agent-ready-release/i18n/en.json` to
`/home/eclipse/omarchy-agent-ready-release/i18n/<code>.json`, translate it, and either set
`.language` to that code or add it to the panel's picker.

## Status bar

The front end is a real Omarchy bar-widget plugin at
`$HOME/.config/omarchy/plugins/eclipse.agent-ready/`, registered in
`$HOME/.config/omarchy/shell.json` under `bar.layout.right`:

| Input | Action |
|---|---|
| Left click | arm → cancel → leave |
| Right click | **open the settings panel** |
| Middle click | same as right click |
| While arming | a card pops up automatically with the countdown + action summary |

The panel is built from the shared Omarchy UI kit (`PopupCard`, `WidgetButton`,
`PanelSectionHeader`, `PanelSeparator`, `Toggle`, `NumberField`, `Button`) and
is translated through `$HOME/.config/omarchy/plugins/eclipse.agent-ready/i18n/`. Sections: **Before entering**, **Automatic**,
**While active**, **Advanced** (suspend sinks, freeze, the digest switch and the
**Language / 语言** picker). The **Agent Ready / state** header is a fixed
information bar pinned to the top while the sections scroll beneath it.
Everything you change writes to `$HOME/.config/omarchy/agent-ready/config.json` immediately; most settings apply
the next time the mode turns on, while the **Language** picker and the digest
switch apply at once. See [PLUGIN.md](PLUGIN.md) (`/home/eclipse/omarchy-agent-ready-release/docs/PLUGIN.md` on the author's machine) for the widget's conventions.

All CLI calls from the plugin go through **argv-vector `Process` objects**
(no shell, no login shell, no `execDetached`), serialized through a small
command queue so rapid config edits never collide.

`omarchy-shell eclipse.agent-ready open|close|toggle` opens the panel from a
keybinding. Suggested `$HOME/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + A", "Toggle Agent Ready", "omarchy-agent-ready toggle")
o.bind("SUPER + CTRL + SHIFT + A", "Agent Ready settings", "omarchy-shell eclipse.agent-ready toggle")
```

Move the icon with `omarchy bar move eclipse.agent-ready --section <section>`.

## Commands

```bash
omarchy-agent-ready status        # Waybar-style JSON (legacy/CLI consumers)
omarchy-agent-ready status-json   # full state for the settings panel
omarchy-agent-ready config-json   # whole config as JSON
omarchy-agent-ready toggle        # arm / cancel / leave  (what the bar calls)
omarchy-agent-ready arm [seconds] # start the countdown, then enter
omarchy-agent-ready auto-arm      # internal: arm triggered by idle
omarchy-agent-ready preview       # rehearsal: short countdown, auto-restore
omarchy-agent-ready reblank       # internal: re-blank outputs after monitor change
omarchy-agent-ready disarm        # cancel a pending countdown
omarchy-agent-ready enter-now     # skip the countdown, enter immediately
omarchy-agent-ready on            # enter immediately (no countdown)
omarchy-agent-ready off           # leave and restore
omarchy-agent-ready digest get    # show the current/last watch digest
omarchy-agent-ready digest set '<json>'  # write external digest fields
omarchy-agent-ready digest history       # every completed watch (JSON)
omarchy-agent-ready digest clear         # erase digest + whole history
omarchy-agent-ready set <path> <value>   # update one config value
omarchy-agent-ready reset-config  # restore $HOME/.config/omarchy/agent-ready/config.json
omarchy-agent-ready doctor        # show config + planned actions, change nothing
omarchy-agent-ready lang          # print the resolved display language (en / zh-CN / ...)
omarchy-agent-ready edit          # open $HOME/.config/omarchy/agent-ready/config.json in $EDITOR
```

`on` is re-entrant: calling it while already on just repairs a lost inhibitor,
it will not lock the screen a second time.

**Note:** the countdown needs the bar widget to be running (it is, normally —
one instance per monitor). If you invoke `arm` from a headless CLI with no shell
running, nothing will fire the countdown; use `enter-now` or `on` instead, or
`disarm` to cancel.

## Configuration — `$HOME/.config/omarchy/agent-ready/config.json`

| Key | Default | Meaning |
|---|---|---|
| `icons.active` / `icons.inactive` | `󰊚` | Bar glyph. Same glyph both ways; `active` makes it highlight. Change if your font shows a box. |
| `notify` | `true` | Notify on enter/leave. |
| `arm.enabled` | `true` | Enable the countdown stage. `false` = enter instantly. |
| `arm.delaySec` | `3` | Seconds before entering (3–60). |
| `arm.notify` | `false` | **Desktop notification** on arming. Off by default; the bar card is the primary prompt. |
| `arm.allowEnterNow` | `true` | Add the "Enter now" button. |
| `arm.notifyCancel` | `true` | Replace the notification with a "cancelled" message on cancel. |
| `arm.bark.enabled` / `.url` / `.title` | `false` / `""` | Optional Bark push. `url` is your full GET endpoint; `title`/`body` are sent as URL-encoded query params. Leave empty to disable. |
| `auto.enabled` | `true` | Auto-arm after a period of no local input. |
| `auto.armAfterSec` | `null` | Idle threshold in seconds. `null` = follow the system (`min(idle.screensaver, idle.lock) - arm.delaySec - 30`, floor 30 s). |
| `auto.cooldownSec` | `60` | Do not auto-arm for this long after returning / leaving. |
| `auto.disarmOnInput` | `true` | Any keyboard/mouse input cancels an auto countdown. |
| `auto.requireInhibitorsClear` | `true` | Honour Wayland idle inhibitors (fullscreen video, games). |
| `auto.barkNotify` | `false` | Push to Bark when auto-arm fires (reuses `arm.bark.url`). |
| `preview.countdownSec` / `.durationSec` | `3` / `20` | Rehearsal: countdown length and how long it stays active before auto-restore. |
| `enter.retrySec` | `60` | Delay before a bounded retry after a lock failure. |
| `language` | `auto` | Per-plugin display language: `auto` (follow Setup → Language), `en`, or `zh-CN`. Affects only this plugin's panel + notifications; the system language is untouched. Set it from the panel's **Advanced → Language / 语言** picker. See **Display language & notifications**. |
| `digest.enabled` | `true` | Record every completed watch and auto-open the digest on unlock. `false` stops recording, hides the auto-open and the panel button, but keeps existing history. Toggle it under **Advanced**. See **Watch digest**. |
| `labels.*` | `{}` (empty) | Optional per-string overrides for notification titles/bodies/action labels. Empty = use the localized `$HOME/.config/omarchy/plugins/eclipse.agent-ready/i18n/*.json` catalogs. Overrides are used verbatim; legacy `%S` = seconds, `%A` = action summary. See **Display language & notifications**. |
| `inhibit.enabled` | `true` | Master switch for the suspend barrier. |
| `inhibit.what` / `.mode` | `sleep:idle` / `block` | What logind is blocked from doing. |
| `idle.linkStayAwake` | `true` | Drive the built-in Stay Awake marker too. |
| `powerProfile.enabled` / `.profile` | `true` / `balanced` | `power-saver` saves more but can slow agent responses. |
| `screen.lock` | `true` | Lock on entry. |
| `screen.dpmsOff` | `true` | Blank display outputs. |
| `screen.keyboardBacklightOff` | `true` | `omarchy-brightness-keyboard off` / `restore`. |
| `screen.dimPercent` | `0` | `0` = don't touch backlight (DPMS already blanks it). |
| `audio.mute` | `false` | `pactl set-sink-mute` on the built-in sink. **Off by default**: its Flags include `HARDWARE HW_MUTE_CTRL`, so toggling it switches the codec's amp/mute GPIO and can produce an audible pop at the blank/unblank transitions on this Surface. Use `pactl set-sink-volume 0%` instead if you want silence without touching the hardware control. |
| `audio.suspendSinks` | `false` | Also `pactl suspend-sink`. Can disrupt streams; off by default. |
| `freeze.enabled` | `false` | Enable the non-essential-process freezer. |
| `freeze.patterns` | `[]` | `pgrep -f` patterns of processes to `SIGSTOP`. |
| `agents.allow` | `[]` | **Set your own actual process names.** Agent reporting uses exact process-name matching (case-insensitive), counting distinct matching names rather than PIDs. Empty means no configured detection names and **no agent freeze protection**, not disabled power behaviour. Configure before enabling freeze. Freeze protection separately matches allow-list names in command lines; hook-supplied names do not alter it. |

`freeze.enabled`, `audio.suspendSinks` and `audio.mute` default to `false`
deliberately — freezing arbitrary DBus/browser/compositor helpers can hang a
session, and the hardware mute control produces an audible pop on this machine.

### Examples

Greener, at the cost of agent latency:

```json
"powerProfile": { "enabled": true, "profile": "power-saver" }
```

Longer grace period:

```json
"arm": { "enabled": true, "delaySec": 30 }
```

Push to your phone while away:

```json
"arm": { "bark": { "enabled": true, "url": "https://your-nas/bark/KEY", "title": "Agent Ready" } }
```

If your Bark deployment expects a different request shape, drop a script in
`$HOME/.config/omarchy/agent-ready/enter.d/` instead — hooks receive `AGENT_READY_ACTION`, `AGENT_READY_STATE_DIR`
and friends.

## Custom actions — `$HOME/.config/omarchy/agent-ready/enter.d/` and `$HOME/.config/omarchy/agent-ready/leave.d/`

Drop any `*.sh` in these directories. They run after the built-in actions, in
filename order, with:

```
AGENT_READY_ACTION=enter|leave
AGENT_READY_CONFIG_DIR   $HOME/.config/omarchy/agent-ready
AGENT_READY_STATE_DIR    $HOME/.local/state/omarchy/agent-ready
AGENT_READY_STATE_FILE   $HOME/.local/state/omarchy/agent-ready/state.json
```

Hooks should undo themselves in the matching directory. Output goes to
`$HOME/.local/state/omarchy/agent-ready/log`; a failing hook is logged and does not
abort the rest.

## Recovery / gotchas

- **Lid close no longer suspends** while Agent Ready is on. That is the point,
  but a laptop closed into a bag will keep running and warm up — turn the mode
  off before packing it.
- The screen is locked and blanked on entry, but only *after* the countdown.
  Unlock normally; the bar button is then clickable. Agent CLI/background
  processes are unaffected by the lock.
- If something goes wrong, `omarchy-agent-ready off` always tries to restore
  from the snapshot. For a hard reset:

  ```bash
  omarchy-agent-ready disarm
  kill "$(cat "$HOME/.local/state/omarchy/agent-ready/inhibit.pid")" 2>/dev/null
  rm -f "$HOME/.local/state/omarchy/agent-ready/state.json"
  omarchy-brightness-display on
  omarchy-brightness-keyboard restore
  powerprofilesctl set performance
  omarchy-toggle-idle allow-idle
  ```

- `magpie`'s own inhibitor and this one coexist; multiple `block` inhibitors
  are fine. Check with `systemd-inhibit --list`.
- A newly installed bar-widget plugin needs `omarchy restart shell` once to
  register with the bar.
- No file under `/usr/share/omarchy/` is modified, so `omarchy update` is safe.
