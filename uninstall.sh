#!/bin/bash
# Agent Ready — uninstaller.
#
#   ./uninstall.sh            # remove program files + bar registration
#   ./uninstall.sh --purge    # also remove config, hooks and runtime history
#   ./uninstall.sh --no-restart
#   ./uninstall.sh --help
#
# Never removes anything outside Omarchy's own config/state and ~/.local/bin.

set -euo pipefail

PLUGIN_ID="eclipse.agent-ready"
PURGE=0
RESTART=1

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while (( $# > 0 )); do
  case "$1" in
    --purge)       PURGE=1; shift ;;
    --no-restart)  RESTART=0; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "uninstall.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

BIN="$HOME/.local/bin/omarchy-agent-ready"
CFG_DIR="$HOME/.config/omarchy/agent-ready"
PLG_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
STATE_DIR="$HOME/.local/state/omarchy/agent-ready"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

echo "Agent Ready — uninstall"

# Leave the machine in a normal state before removing the tool.
if [[ -x "$BIN" ]]; then
  if ! "$BIN" off; then
    warn "could not leave Agent Ready; keeping program, config and state for recovery"
    warn "retry 'omarchy-agent-ready off', then run this uninstaller again"
    exit 1
  fi
  say "Agent Ready is off (any active scene was restored)"
fi

if [[ -f "$SHELL_JSON" ]] && command -v jq >/dev/null 2>&1; then
  cp -f "$SHELL_JSON" "$SHELL_JSON.agent-ready.bak"
  tmp="$SHELL_JSON.tmp"
  jq --arg id "$PLUGIN_ID" '
     .bar.layout |= with_entries(
       if (.value | type) == "array"
       then .value = [.value[] | select((type == "object" and .id == $id) | not)]
       else . end)
   ' "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
  say "removed $PLUGIN_ID from shell.json (backup: shell.json.agent-ready.bak)"
fi

rm -f "$BIN"                 && say "removed $BIN"
rm -rf "$PLG_DIR"            && say "removed $PLG_DIR"

if (( PURGE )); then
  rm -rf "$CFG_DIR" "$STATE_DIR"
  say "purged $CFG_DIR and $STATE_DIR"
else
  say "kept $CFG_DIR and $STATE_DIR (use --purge to remove)"
fi

if (( RESTART )) && command -v omarchy >/dev/null 2>&1; then
  omarchy restart shell >/dev/null 2>&1 || warn "could not restart the shell"
  say "shell restarted"
fi

echo "Done."
