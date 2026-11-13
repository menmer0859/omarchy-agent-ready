#!/usr/bin/env bash
# Read-only desktop checks; all writes go to an isolated HOME.
# Never invoke on, arm, auto-arm, preview, enter-now or _arm-fire here.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash -n install.sh uninstall.sh bin/omarchy-agent-ready
omarchy plugin validate "$ROOT"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T"
unset AGENT_READY_CONFIG_DIR AGENT_READY_STATE_DIR AGENT_READY_I18N_DIR OMARCHY_LANGUAGE_FILE
export XDG_CONFIG_HOME="$T/.config" XDG_STATE_HOME="$T/.local/state" XDG_DATA_HOME="$T/.local/share"
mkdir -p "$HOME/.config/omarchy"
printf '%s\n' '{"bar":{"layout":{"center":[],"right":[]}},"idle":{"screensaver":150,"lock":300}}' > "$HOME/.config/omarchy/shell.json"
./install.sh --no-restart
CLI="$HOME/.local/bin/omarchy-agent-ready"
CFG="$HOME/.config/omarchy/agent-ready/config.json"
"$CLI" doctor
"$CLI" status-json | jq -e '.enabled == false and .pending == false and .digestHistory == [] and .config.agents.allow == []'
"$CLI" reset-config >/dev/null
jq -S . "$CFG" > "$T/reset.json"
jq -S . config/config.json > "$T/template.json"
cmp "$T/reset.json" "$T/template.json"
"$CLI" doctor | grep -F 'agent allow list (0):'
# Explicit allow-list names work, without changing the real configuration.
jq '.agents.allow = ["release-smoke-agent"]' "$CFG" > "$T/config-new.json"
mv "$T/config-new.json" "$CFG"
"$CLI" doctor | grep -F 'agent allow list (1): release-smoke-agent'
"$CLI" set arm.delaySec 7 >/dev/null
./install.sh --no-restart
jq -e '.arm.delaySec == 7 and .agents.allow == ["release-smoke-agent"]' "$CFG"
jq -e '[.bar.layout[][] | select(.id == "eclipse.agent-ready")] | length == 1' "$HOME/.config/omarchy/shell.json"
# Pure configuration and digest operations, never a watch/power transition.
"$CLI" digest set '{"agents":["example-agent"],"completed":3,"note":"synthetic smoke test"}' >/dev/null
"$CLI" digest get | jq -e '.completed == 3 and .agents == ["example-agent"]'
"$CLI" digest history | jq -e '. == []'
"$CLI" digest clear >/dev/null
"$CLI" digest history | jq -e '. == []'
for lang in en zh-CN; do
  "$CLI" set language "$lang" >/dev/null
  test "$("$CLI" lang)" = "$lang"
done
"$CLI" set language auto >/dev/null
printf 'zh-CN\n' > "$HOME/.config/omarchy/language"
test "$("$CLI" lang)" = zh-CN
printf 'de\n' > "$HOME/.config/omarchy/language"
test "$("$CLI" lang)" = en
# A failed restore must abort uninstallation and retain recovery files.
mv "$CLI" "$T/cli-saved"
printf '#!/bin/bash\nexit 1\n' > "$CLI"
chmod 755 "$CLI"
if ./uninstall.sh --no-restart --purge; then
  echo 'FAIL: uninstaller ignored a restore failure' >&2
  exit 1
fi
test -f "$CLI"
test -f "$CFG"
test -d "$HOME/.local/state/omarchy/agent-ready"
test -f "$HOME/.config/omarchy/plugins/eclipse.agent-ready/manifest.json"
jq -e '[.bar.layout[][] | select(.id == "eclipse.agent-ready")] | length == 1' "$HOME/.config/omarchy/shell.json"
mv "$T/cli-saved" "$CLI"
./uninstall.sh --no-restart --purge
test ! -e "$CLI"
test ! -e "$HOME/.config/omarchy/agent-ready"
test ! -e "$HOME/.config/omarchy/plugins/eclipse.agent-ready"
test ! -e "$HOME/.local/state/omarchy/agent-ready"
jq -e '[.bar.layout[][] | select(.id == "eclipse.agent-ready")] | length == 0' "$HOME/.config/omarchy/shell.json"
echo 'PASS: isolated install, doctor, reset/template parity, empty/custom allow list, idempotent reinstall, language, digest, restore-failure guard, uninstall --purge'
