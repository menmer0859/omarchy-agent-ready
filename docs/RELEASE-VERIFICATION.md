---
title: Agent Ready v1.1.0 release verification
type: release-verification
date: 2026-11-21
status: verified-on-2026-11-21
---

# Agent Ready v1.1.0 release verification

## TLDR / Conclusion

**Verified:** this repository passes syntax, manifest, widget lint, isolated
release-smoke, and isolated transition-smoke checks on Omarchy `4.5.0-3`.

The release now has:

- A working **empty `agents.allow`** contract with no implicit 13-name fallback.
- A bounded lock-failure retry that rolls back the actions it actually applied.
- A snapshot-driven `off` path that returns nonzero and preserves recovery
  evidence when any restore step fails.
- A locked `_arm-fire`/`disarm` critical section that closes the countdown race.
- A single QML face selector that cannot open a blank popup.
- A manual-setup warning for the marketplace's clone-and-enable path.
- A repository-relative documentation tree with no author-machine absolute paths.

All checks below were executed in an isolated `HOME` or against repository files
only. **No real lock, DPMS, suspend, or power-scene command was executed.**

## Commands and observed results

```bash
bash -n install.sh uninstall.sh bin/omarchy-agent-ready \
     tests/release-smoke.sh tests/transition-smoke.sh
```

**Result:** exit `0`; no syntax errors.

```bash
omarchy plugin validate .
```

**Result:** exit `0`; no errors.

```bash
jq empty manifest.json
```

**Result:** exit `0`.

```bash
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell Widget.qml PluginI18n.qml
```

**Result:** exit `0`; no errors. The existing unqualified-access warnings from
the Omarchy kit remain style-level only.

```bash
bash tests/release-smoke.sh
```

**Result:** exit `0`, ending with:

```text
PASS: isolated install, doctor, reset/template parity, empty/custom allow list, idempotent reinstall, language, digest, restore-failure guard, uninstall --purge
```

```bash
bash tests/transition-smoke.sh
```

**Result:** exit `0`, ending with:

```text
TRANSITION RESULT: 67 passed, 0 failed
```

## Specific regressions covered

### Empty agent allow list

- `reset-config` writes `"allow": []` and matches `config/config.json`.
- Doctor reports `agent allow list (0):` on a clean install.
- A process that is not in the allow list is still frozen when
  `freeze.enabled=true`, proving that the empty list grants no exemption.
- The frozen process is resumed by `off`.

### Automatic arming and face state

- The auto-countdown keeps its idle monitor enabled, so a genuine input event can
  cancel it and a monitor-disable transition cannot fire a spurious disarm.
- The widget uses one face selector (`settings/arming/digest/closed`), so no
  boolean combination can open an empty popup.
- Starting an arming countdown closes a stale digest face.

### Lock failure and restoration

- Four consecutive lock failures increment retry count `1 → 2 → 3`, then stop;
  the fourth failure does not schedule another retry.
- Rollback restores audio mute/suspend and display brightness, which the old
  rollback missed.
- Successful entry clears retry metadata.
- `off` and lock-failure rollback use the same `restore_applied()` helper driven
  by the snapshot's `applied.*` flags, not by the current config.

### Restore failure and evidence

Injected failures in display-on, keyboard backlight, audio mute, power profile,
idle restore, inhibitor release, and unfreeze all produce:

- nonzero `off`,
- `enabled=true` and `phase=restoring`,
- retained snapshot and per-action recovery evidence,
- successful recovery once the fault is cleared.

### Countdown race

- `_arm-fire` and `disarm` run under one action lock.
- A stale `_arm-fire` cannot enter after `disarm`.
- Two concurrent `_arm-fire` calls lock the screen at most once and end in one
  active state.

## Publication hygiene

- `README.md` and `README.zh-CN.md` cross-link each other.
- Both READMEs warn that marketplace clone-and-enable alone does not install the
  required CLI.
- `manifest.json` ends its description with `Manual setup required.` and remains
  171 characters, under the 500-character marketplace limit.
- `SUBMISSION-NOTES.md` contains the maintainer note for the manual-installation
  override.
- `.gitignore` excludes author-machine snapshots, release backups, review
  documents, and fix-round handoff files.
- `preview.png` is the root marketplace preview and is a real settings-panel
  capture.
- A repository scan finds **zero** author-machine absolute paths in
  `README.md`, `README.zh-CN.md`, `docs/`, `manifest.json`, and
  `SUBMISSION-NOTES.md`.

## Known limits of this verification

- QML interaction paths were verified by code contract and `qmllint`, not by a
  live desktop harness; no real lock or display action was triggered.
- The transition harness stubs `omarchy-system-lock`, brightness, audio, power,
  idle, and inhibit commands. It verifies state-machine behavior and command
  ordering, not real hardware effects.
- Omarchy compatibility is still limited to `4.5.0-3`.
- Recovery after a reboot while the scene is active remains a documented open
  limitation.
