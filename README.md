---
title: Agent Ready for Omarchy
type: readme
date: 2026-11-13
status: released-v1.1.0
canonical_path: /home/eclipse/omarchy-agent-ready-release/README.md
---

# Agent Ready for Omarchy

**Keep background agents running while your session locks and displays turn off.**

Agent Ready prevents system sleep; it does not suspend the machine. Install with
`git clone` and `./install.sh` below. Source: [menmer0859/omarchy-agent-ready](https://github.com/menmer0859/omarchy-agent-ready).

Agent Ready adds a third mode to Omarchy's "Stay Awake" idea. Instead of either
*keep everything awake* or *let the machine idle-lock*, it puts the machine into
an **agents-on-duty** state:

- **Agents stay online** — a `systemd-inhibit` barrier blocks suspend (including
  lid close), and Omarchy's own Stay Awake marker suppresses the screensaver and
  idle lock.
- **Everything non-essential powers down** — display output off, session locked,
  keyboard backlight off, power profile lowered, optional audio mute, optional
  freezing of non-agent processes.
- **You get a clean handoff on return** — unlock normally; the scene restores
  itself and a *watch digest* tells you what happened while you were away.

All of it is one bar icon. Left-click arms a short countdown (visible on the
icon and in a card), cancels it, or leaves the scene. Right-click opens a full
settings panel built from Omarchy's own UI kit.

> This is a userland plugin: it does **not** modify anything under
> `/usr/share/omarchy`. It only writes to `~/.config/omarchy/` and
> `~/.local/`.

## Screenshots

Captured on the author's Omarchy desktop without entering Agent Ready.
The bar icon is enlarged for visibility; settings are a real panel capture.
The digest below is a **static illustration with fictional data**, not a real watch record.

![Agent Ready bar icon (real capture, enlarged)](docs/images/bar-icon.png)

![Agent Ready settings panel (real desktop capture)](docs/images/settings.png)

![Watch digest — static illustration, fictional example data](docs/images/digest-illustration.svg)

## Features

| | |
|---|---|
| Arming countdown | Live seconds on the bar icon + a card explaining exactly what will happen; Cancel / Enter now |
| Automatic entry | A dedicated idle monitor arms the scene after a period with no local input; threshold follows `idle.screensaver` / `idle.lock` by default |
| Watch digest | Full history of every watch: start/end, duration, trigger, **agent names**, active measures, completed/failed/pending, notes |
| Language | Follow system, English, or 简体中文 — per plugin, switchable instantly in the panel |
| Resilience | Phase machine, lost-inhibitor repair, lock-failure rollback with bounded retry, monitor hotplug handling |
| Hooks | `enter.d/` / `leave.d/` scripts for Cindy sessions, Home Assistant, Bark, NAS archiving, … |
| Bark push | Optional phone notification on arming |

## Requirements

- **Omarchy** — validated on **4.5.0-3**, with Quickshell and plugin manifest
  `schemaVersion: 1`. Other versions are not verified. Uses its shell, bar-widget plugin API, `omarchy-*` helpers and
  `~/.config/omarchy/shell.json`. This is not a generic Linux tool.
- Commands already present on a stock Omarchy: `jq`, `pactl`,
  `powerprofilesctl`, `systemd-inhibit`, `hyprctl`, `brightnessctl`, `flock`,
  `nohup`, plus `omarchy-system-lock`, `omarchy-brightness-display`,
  `omarchy-brightness-keyboard`, `omarchy-toggle-idle`,
  `omarchy-audio-output-sink`, `omarchy-notification-send`.
- `curl` only if you enable Bark push.
- A Nerd Font for the `󰊚` glyph (Omarchy ships one).

Run `omarchy-agent-ready doctor` after installing to see exactly what is
available and what will happen when the scene turns on.

## Install

```bash
git clone https://github.com/menmer0859/omarchy-agent-ready.git
cd omarchy-agent-ready
./install.sh
```

`install.sh` copies the CLI to `~/.local/bin/`, the config + example hooks to
`~/.config/omarchy/agent-ready/`, the bar widget to
`~/.config/omarchy/plugins/eclipse.agent-ready/`, registers the widget in
`shell.json` (with a backup), validates the manifest, runs `doctor`, and
restarts the shell. It is **idempotent** and never overwrites an existing
`config.json` or enabled hooks.

Options: `--section center` (default `right`), `--no-restart`, `--force`
(overwrite config), `--help`.

Alternative for the widget only (you still need the CLI + config):

```bash
omarchy plugin add https://github.com/menmer0859/omarchy-agent-ready.git --enable
# From your local git checkout (the plugin command alone does not install the CLI):
./install.sh --no-restart
```

Move the icon later with
`omarchy bar move eclipse.agent-ready --section <section>`.

## Quick start

**Safety:** `preview` / **Try it** is a real power-scene rehearsal, not a
read-only visual preview: it can lock the session, blank displays, and inhibit
sleep. Do not use it during remote work unless you intend those effects.
Auto-arm is enabled by default; disable `auto.enabled` if remote sessions must
not trigger idle entry.

1. **Left-click** the bar icon → countdown → Agent Ready.
2. **Right-click** → settings panel. Everything is written to `config.json`
   immediately; most changes apply on the next entry.
3. Come back, unlock, and the **watch digest** opens with the full history.
   Its **Back** button returns to the settings panel or the plain bar.
4. Useful commands:

```bash
omarchy-agent-ready status-json   # full machine-readable state
omarchy-agent-ready doctor        # dependencies + planned actions
omarchy-agent-ready on / off      # enter / leave immediately
omarchy-agent-ready preview       # 3 s countdown → 20 s rehearsal → auto-restore
omarchy-agent-ready digest history
```

## Configuration

`~/.config/omarchy/agent-ready/config.json` — or just use the panel. Highlights:

| Key | Default | Meaning |
|---|---|---|
| `arm.delaySec` | `3` | Countdown length |
| `auto.enabled` | `true` | Auto-arm when idle |
| `auto.armAfterSec` | `null` | `null` = follow the system idle time |
| `screen.lock` / `.dpmsOff` | `true` | Lock session / blank outputs |
| `inhibit.enabled` | `true` | Block suspend (incl. lid close) |
| `audio.mute` | `false` | Off by default: the hardware mute control can pop on some machines |
| `language` | `auto` | `auto` / `en` / `zh-CN` — this plugin only |
| `digest.enabled` | `true` | Record watches + auto-open digest on unlock |
| `agents.allow` | `[]` | No machine-specific names assumed; configure for your machine |

**You must set `agents.allow` for your own machine.** The empty default counts
no agent names; it does not prevent background work or disable the sleep
inhibitor. Match actual process names (`ps -eo comm= | sort -u`), for example:

Edit the installed configuration and replace its `agents` entry, for example:

```json
"agents": { "allow": ["codex", "claude"] }
```

These are examples, not universal defaults. `node` / `python` wrappers cannot
identify the underlying agent reliably; use a hook-provided `agents` array.
Configure this list before enabling experimental freezing: it also protects
matching agent command lines from `freeze.patterns`.

Full table, all commands, hooks and recovery notes: **[docs/CLI.md](docs/CLI.md)**.
Widget internals and conventions: **[docs/PLUGIN.md](docs/PLUGIN.md)**.
Developer architecture, pitfalls, historical evidence and remaining work:
**[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**. The plugin id remains
`eclipse.agent-ready` for compatibility; the author is `menmer0859`.

## Uninstall

```bash
./uninstall.sh            # removes program files + bar registration, keeps config/history
./uninstall.sh --purge    # also removes config and runtime state
```

If restoring the scene fails, uninstall stops and preserves recovery files.
Run `omarchy-agent-ready off` successfully, then retry the uninstaller.

## Known limitations

- Agent detection matches **process names** in `agents.allow`; agents launched
  through `node` / `python` are not detected. Supply a precise list through a
  hook (`digest set '{"agents":[...]}'`) if you need one.
- `audio.mute` defaults to `false` because toggling a sink with
  `HW_MUTE_CTRL` produces an audible pop on some Surface machines.
- Only `en` and `zh-CN` catalogs ship. Adding a language is one JSON file (see
  [docs/PLUGIN.md](docs/PLUGIN.md#adding-a-language)).
- Auto-arm needs a long enough system idle time; if it is too short, the panel
  reports *auto-arm unavailable* instead of racing the screensaver.
- Reboot recovery while the scene is active is not yet fully reconciled;
  runtime state may outlive the inhibitor. See the development roadmap.
- `freeze` and sink suspension are experimental and disabled by default.
- History retains the latest 200 watches; no other languages ship yet.

## License

MIT — see [LICENSE](LICENSE).
