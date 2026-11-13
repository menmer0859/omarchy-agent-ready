#!/bin/bash
# Agent Ready — one-shot installer for Omarchy.
# Source: https://github.com/menmer0859/omarchy-agent-ready
#
#   ./install.sh                 # install into $HOME, restart the shell
#   ./install.sh --no-restart    # install but let the user restart manually
#   ./install.sh --section center
#   ./install.sh --force         # also overwrite an existing config.json
#   ./install.sh --help
#
# Idempotent: re-running updates program files but never destroys an existing
# config.json, enabled hooks, or the user's runtime history.

set -euo pipefail

PLUGIN_ID="eclipse.agent-ready"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECTION="right"
RESTART=1
FORCE=0

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while (( $# > 0 )); do
  case "$1" in
    --section)     SECTION="${2:-}"; shift 2 ;;
    --no-restart)  RESTART=0; shift ;;
    --force)       FORCE=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ $SECTION =~ ^(left|centerBegin|center|centerEnd|tray|right)$ ]] || {
  echo "install.sh: invalid section '$SECTION'" >&2; exit 2; }

say()  { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ checks ----
echo "Agent Ready — install"

[[ -f "$REPO_DIR/manifest.json" && -f "$REPO_DIR/Widget.qml" && -x "$REPO_DIR/bin/omarchy-agent-ready" ]] ||
  die "run this from the repository root (missing files in $REPO_DIR)"

[[ -d "$HOME/.config/omarchy" ]] ||
  die "Omarchy config not found at ~/.config/omarchy — is Omarchy installed?"

command -v jq >/dev/null 2>&1 || die "jq is required (sudo pacman -S jq)"

missing=()
for dep in pactl powerprofilesctl systemd-inhibit hyprctl brightnessctl flock nohup \
           omarchy-system-lock omarchy-brightness-display omarchy-brightness-keyboard \
           omarchy-toggle-idle omarchy-audio-output-sink omarchy-notification-send; do
  command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if (( ${#missing[@]} > 0 )); then
  warn "missing optional/runtime commands: ${missing[*]}"
  warn "some features will be skipped; run 'omarchy-agent-ready doctor' afterwards"
fi

BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/omarchy/agent-ready"
PLG_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

mkdir -p "$BIN_DIR" "$CFG_DIR/enter.d" "$CFG_DIR/leave.d" "$PLG_DIR/i18n" \
         "$HOME/.local/state/omarchy/agent-ready"

# ------------------------------------------------------------------- files ----
install -m 755 "$REPO_DIR/bin/omarchy-agent-ready" "$BIN_DIR/omarchy-agent-ready"
say "CLI -> $BIN_DIR/omarchy-agent-ready"

if [[ ! -f "$CFG_DIR/config.json" || $FORCE -eq 1 ]]; then
  cp "$REPO_DIR/config/config.json" "$CFG_DIR/config.json"
  say "config -> $CFG_DIR/config.json (defaults)"
else
  say "config unchanged (existing config.json kept; --force to overwrite)"
fi

# Example hooks stay .disabled so nothing runs until the user opts in. Never
# overwrite a hook the user may have customised.
for f in "$REPO_DIR"/config/enter.d/* "$REPO_DIR"/config/leave.d/*; do
  [[ -f "$f" ]] || continue
  sub="$(basename "$(dirname "$f")")"
  cp -n "$f" "$CFG_DIR/$sub/$(basename "$f")" 2>/dev/null || true
done
say "hooks  -> $CFG_DIR/{enter.d,leave.d}/ (examples disabled)"

for f in manifest.json Widget.qml PluginI18n.qml; do
  cp "$REPO_DIR/$f" "$PLG_DIR/$f"
done
for f in "$REPO_DIR"/i18n/*.json; do
  cp "$f" "$PLG_DIR/i18n/$(basename "$f")"
done
say "plugin -> $PLG_DIR/"

# -------------------------------------------------------- bar registration ----
if [[ -f "$SHELL_JSON" ]]; then
  cp -f "$SHELL_JSON" "$SHELL_JSON.agent-ready.bak"
  if jq -e --arg id "$PLUGIN_ID" '
       [.bar.layout[]? | select(type == "array") | .[]?
        | select(type == "object" and .id == $id)] | length > 0
     ' "$SHELL_JSON" >/dev/null 2>&1; then
    say "bar widget already registered in shell.json"
  else
    tmp="$SHELL_JSON.tmp"
    jq --arg id "$PLUGIN_ID" --arg sec "$SECTION" \
       '.bar.layout[$sec] = ((.bar.layout[$sec] // []) + [{"id": $id}])' \
       "$SHELL_JSON" > "$tmp" && mv "$tmp" "$SHELL_JSON"
    say "registered $PLUGIN_ID into bar.layout.$SECTION (backup: shell.json.agent-ready.bak)"
  fi
else
  warn "no shell.json — add {\"id\":\"$PLUGIN_ID\"} to a bar.layout section yourself"
fi

# ---------------------------------------------------------------- validation ----
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$PLG_DIR" >/dev/null 2>&1 \
    && say "manifest validation: OK" \
    || warn "omarchy-plugin-validate reported a problem with $PLG_DIR"
fi

if [[ -x "$BIN_DIR/omarchy-agent-ready" ]]; then
  say "--- doctor ---"
  "$BIN_DIR/omarchy-agent-ready" doctor 2>&1 | sed 's/^/    /' || true
fi

if (( RESTART )) && command -v omarchy >/dev/null 2>&1; then
  omarchy restart shell >/dev/null 2>&1 || warn "could not restart the shell; do it manually"
  say "shell restarted"
else
  say "run 'omarchy restart shell' to load the bar widget"
fi

cat <<EOF

Done. Quick start:
  left-click the bar icon   arm -> countdown -> Agent Ready
  right-click               settings panel (Advanced holds Language + Digest)
  $BIN_DIR/omarchy-agent-ready status-json   machine-readable state
  $BIN_DIR/omarchy-agent-ready doctor        dependency / action report

Docs: docs/CLI.md, docs/PLUGIN.md  |  Uninstall: ./uninstall.sh
EOF
