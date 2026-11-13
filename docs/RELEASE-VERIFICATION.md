---
title: Agent Ready v1.1.0 release verification
type: release-verification
date: 2026-11-13
status: locally-verified
canonical_path: /home/eclipse/omarchy-agent-ready-release/docs/RELEASE-VERIFICATION.md
---

# Agent Ready v1.1.0 release verification

## TLDR / Conclusion

**Confirmed:** the release passes isolated-HOME installation, doctor, idempotent reinstallation, configuration, digest, language and purge-uninstallation checks on Omarchy `4.5.0-3`. The release workflow never invoked a real power-scene entry command. The already-installed instance independently auto-entered later during the work; see the observation below. Public repository and release receipts are recorded in the delivery message, after publication.

## Facts and evidence

Paths in this report refer to the **author's machine**, not required installation locations. The source root is `/home/eclipse/omarchy-agent-ready-release`; users install into their own `$HOME`.

### Required release checklist

| Item | Result | Evidence under the source root |
|---|---|---|
| ★1 Author | `menmer0859`; copyright year remains 2026 | `/home/eclipse/omarchy-agent-ready-release/LICENSE`, `/home/eclipse/omarchy-agent-ready-release/manifest.json` |
| ★2 Repository URL | `https://github.com/menmer0859/omarchy-agent-ready`; clone URLs append `.git` | README, installer source comment, developer documentation |
| ★3 Agent allow list | Default `[]`; CLI reset template matches; implicit machine-specific fallback removed | config template, CLI, README and CLI documentation |
| ★4 Images | Real cropped bar icon and settings panel; digest is explicitly fictional static illustration | `/home/eclipse/omarchy-agent-ready-release/docs/images/` |
| ★5 Version | manifest `1.1.0`, release tag `v1.1.0` | manifest and release receipt |
| ★6 Description | Includes auto-arm, digest history, language selection and power/digest toggles | manifest top-level and bar-widget descriptions |

The unused `AUTO_STATE_FILE` constant was removed after confirming that its definition was its only occurrence. Review also found that uninstall ignored a failed `off` command and could delete recovery files. It now aborts on failure and preserves the CLI, configuration, state, widget and bar registration. A stub-failure regression test verifies this without activating any scene. The state machine and UI layout were not reimplemented.

### Commands and observed results

```bash
cd /home/eclipse/omarchy-agent-ready-release
bash -n install.sh uninstall.sh bin/omarchy-agent-ready
omarchy plugin validate /home/eclipse/omarchy-agent-ready-release
bash /home/eclipse/omarchy-agent-ready-release/tests/release-smoke.sh
```

- Syntax and plugin validation both exit **0**; plugin validation prints no errors.
- The smoke test creates and removes a temporary HOME with a minimal shell configuration. No shell restart occurs.
- Installer copies CLI, defaults, disabled hooks and widget; prints `manifest validation: OK` and registers the widget once.
- Doctor reports all **15 dependencies** `ok`, `state OFF`, `inhibitor not running`, `agent allow list (0)`.
- Auto threshold is `117s`, `available=true`, from a 150s screensaver / 300s lock and 3s countdown. This is a query, not an automatic entry.
- CLI reset and packaged configuration compare identically after JSON normalization. An explicit test name produces `agent allow list (1): release-smoke-agent`.
- Reinstallation preserves the test user's `arm.delaySec=7` and custom allow list. Bar registration remains exactly one entry.
- Pure digest set/get/history/clear operations pass with synthetic test data; no watch is started.
- English, Simplified Chinese, automatic Chinese selection and unknown-language fallback to English pass.
- With a temporary CLI stub returning failure, uninstall exits 1 before removing any recovery files or bar registration. The test then restores the actual isolated CLI.
- `uninstall --no-restart --purge` removes the isolated CLI, plugin, configuration and state; registration count becomes zero.
- Final output: `PASS: isolated install, doctor, reset/template parity, empty/custom allow list, idempotent reinstall, language, digest, restore-failure guard, uninstall --purge`.
- Every repository JSON parses. Catalog key parity is **127 / 127**.
- File scan finds no state/digest/history/log runtime data. `git check-ignore` confirms runtime names, logs and `.local/state/` are excluded.
- SHA-256 collections for the **5 files** in the author's real runtime directory were identical before and after the first smoke-test run. A later comparison after the expanded regression run detected changes. A minimal read of state fields showed the already-installed instance active with `trigger: auto`; the release tests never invoke `auto-arm` or a scene entry command and write only inside their temporary HOME. The live instance was not changed or restored by this workflow. Consequently this report does **not** claim that live runtime data remained unchanged throughout the entire release task. No real history was copied into the project.

### Compatibility identifier and developer documentation

The plugin id remains **`eclipse.agent-ready`**, intentionally separate from author `menmer0859`. Renaming it would affect plugin discovery, installed paths, IPC, bar registration, translation lookup and uninstall behavior. Consider unified naming only with a future migration plan.

The original handoff is migrated in full to `/home/eclipse/omarchy-agent-ready-release/docs/DEVELOPMENT.md`. Its opening addresses developers; author-machine paths and historical defaults are labeled, and the release changes are distinguished from the original development record. README links to it. The original `HANDOFF.md` is not published separately.

## Steps

1. Read the complete original handoff and retain its design and pitfalls.
2. Correct release metadata, URLs, defaults and documentation; keep the compatibility id unchanged.
3. Open the settings panel without entering the scene; capture only the plugin's region, then close it. Enlarge the real bar icon for legibility.
4. Supply an explicitly labeled fictional digest illustration instead of creating a real watch.
5. Run the isolated smoke test and static/runtime-data checks before committing and publishing.

## Risks and open questions

- No real arm/on/preview/enter-now command was run by this workflow. The live instance's separately observed automatic entry is not a controlled acceptance test. Existing lock/DPMS/audio manual acceptance records remain historical, not freshly reproduced here.
- `preview` / **Try it** is a real rehearsal with locking, blanking and sleep inhibition, not read-only preview. Auto-arm is enabled by default. README warns remote users.
- `agents.allow: []` detects no agent names and gives no freeze exemptions. It does not disable the sleep inhibitor. Configure actual local names before enabling experimental freezing.
- Only Omarchy `4.5.0-3` was verified. Process-name detection cannot identify agents hidden behind generic node/python wrappers; hooks can provide explicit names.
- Recovery after reboot during an active scene remains unfinished. Freezing and sink suspension remain experimental and disabled by default.
- The digest illustration contains fictional example data. README, alt text and the illustration itself say so; it is not a real runtime screenshot.

## Path index

- Source: `/home/eclipse/omarchy-agent-ready-release`
- User guide: `/home/eclipse/omarchy-agent-ready-release/README.md`
- Developer record: `/home/eclipse/omarchy-agent-ready-release/docs/DEVELOPMENT.md`
- Reproducible verification: `/home/eclipse/omarchy-agent-ready-release/tests/release-smoke.sh`
- Verification report: `/home/eclipse/omarchy-agent-ready-release/docs/RELEASE-VERIFICATION.md`
