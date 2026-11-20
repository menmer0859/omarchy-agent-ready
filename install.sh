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
  sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

echo "Agent Ready — install"

# ------------------------------------------------------------------ checks ----

required=(
  manifest.json
  Widget.qml
  PluginI18n.qml
  bin/omarchy-agent-ready
  config/config.json
  config/enter.d/README.md
  config/leave.d/README.md
  i18n/en.json
  i18n/zh-CN.json
)
for f in "${required[@]}"; do
  [[ -e "$REPO_DIR/$f" ]] || die "missing required file: $f"
done
[[ -x "$REPO_DIR/bin/omarchy-agent-ready" ]] || die "CLI is not executable"
for f in manifest.json config/config.json i18n/en.json i18n/zh-CN.json; do
  jq empty "$REPO_DIR/$f" >/dev/null 2>&1 || die "invalid JSON: $f"
done

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

# ------------------------------------------------------- stage / transaction ----

WORK="$(mktemp -d)"
STAGE="$WORK/stage"
BACKUP="$WORK/backup"
mkdir -p "$STAGE" "$BACKUP"
TOUCHED=()

cleanup() { rm -rf "$WORK"; }
trap 'rc=$?; if (( rc != 0 )); then rollback; fi; cleanup' EXIT

backup_path() {
  local target="$1"
  local backup="$BACKUP$target"
  if [[ -e "$target" ]]; then
    mkdir -p "$(dirname "$backup")"
    cp -a "$target" "$backup"
  fi
}

stage_path() {
  local source="$1"
  local target="$2"
  local staged="$STAGE$target"
  mkdir -p "$(dirname "$staged")"
  cp -a "$source" "$staged"
}

commit_path() {
  local target="$1"
  local staged="$STAGE$target"
  [[ -e "$staged" ]] || die "internal error: missing staged file for $target"
  mkdir -p "$(dirname "$target")"
  backup_path "$target"
  mv -f "$staged" "$target"
  TOUCHED+=("$target")
}

rollback() {
  local target backup
  for target in "${TOUCHED[@]}"; do
    backup="$BACKUP$target"
    if [[ -e "$backup" ]]; then
      mkdir -p "$(dirname "$target")"
      mv -f "$backup" "$target"
    else
      rm -f "$target"
    fi
  done
}

# Stage files that will actually be written. Existing user config/hooks are
# preserved unless --force is used for config, and hooks are never overwritten.
stage_path "$REPO_DIR/bin/omarchy-agent-ready" "$BIN_DIR/omarchy-agent-ready"

if [[ ! -f "$CFG_DIR/config.json" || $FORCE -eq 1 ]]; then
  stage_path "$REPO_DIR/config/config.json" "$CFG_DIR/config.json"
  say "config -> $CFG_DIR/config.json"
else
  say "config unchanged (existing config.json kept; --force to overwrite)"
fi

for f in "$REPO_DIR"/config/enter.d/* "$REPO_DIR"/config/leave.d/*; do
  [[ -f "$f" ]] || continue
  sub="$(basename "$(dirname "$f")")"
  target="$CFG_DIR/$sub/$(basename "$f")"
  if [[ -e "$target" ]]; then
    continue
  fi
  stage_path "$f" "$target"
done
say "hooks  -> $CFG_DIR/{enter.d,leave.d}/ (examples disabled)"

for f in manifest.json Widget.qml PluginI18n.qml; do
  stage_path "$REPO_DIR/$f" "$PLG_DIR/$f"
done
for f in "$REPO_DIR"/i18n/*.json; do
  stage_path "$f" "$PLG_DIR/i18n/$(basename "$f")"
done
say "plugin -> $PLG_DIR/"

# Validate the staged plugin before touching the live installation.
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$STAGE$PLG_DIR" >/dev/null 2>&1 \
    || die "staged manifest failed validation"
fi

# Stage shell.json if registration is needed.
NEED_REGISTER=0
if [[ -f "$SHELL_JSON" ]]; then
  if jq -e --arg id "$PLUGIN_ID" '
       [.bar.layout[]? | select(type == "array") | .[]?
        | select(type == "object" and .id == $id)] | length > 0
     ' "$SHELL_JSON" >/dev/null 2>&1; then
    say "bar widget already registered in shell.json"
  else
    NEED_REGISTER=1
    jq --arg id "$PLUGIN_ID" --arg sec "$SECTION" \
       '.bar.layout[$sec] = ((.bar.layout[$sec] // []) + [{"id": $id}])' \
       "$SHELL_JSON" > "$STAGE$SHELL_JSON" \
       || die "could not stage shell.json registration"
  fi
else
  warn "no shell.json — add {\"id\":\"$PLUGIN_ID\"} to a bar.layout section yourself"
fi

# ---------------------------------------------------------------- commit ----

if (( NEED_REGISTER )); then
  stamp="$(date +%Y%m%d%H%M%S).$$"
  cp -a "$SHELL_JSON" "$SHELL_JSON.agent-ready.bak.$stamp"
  say "backup -> shell.json.agent-ready.bak.$stamp"
fi

for target in \
  "$BIN_DIR/omarchy-agent-ready" \
  "$PLG_DIR/manifest.json" \
  "$PLG_DIR/Widget.qml" \
  "$PLG_DIR/PluginI18n.qml" \
  "$PLG_DIR/i18n/en.json" \
  "$PLG_DIR/i18n/zh-CN.json"; do
  commit_path "$target"
done

for f in "$REPO_DIR"/config/enter.d/* "$REPO_DIR"/config/leave.d/*; do
  [[ -f "$f" ]] || continue
  sub="$(basename "$(dirname "$f")")"
  target="$CFG_DIR/$sub/$(basename "$f")"
  [[ -e "$STAGE$target" ]] && commit_path "$target"
done

if [[ -e "$STAGE$CFG_DIR/config.json" ]]; then
  commit_path "$CFG_DIR/config.json"
fi

if (( NEED_REGISTER )); then
  commit_path "$SHELL_JSON"
  say "registered $PLUGIN_ID into bar.layout.$SECTION"
fi

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$PLG_DIR" >/dev/null 2>&1 \
    && say "manifest validation: OK" \
    || die "installed manifest failed validation"
fi

if [[ -x "$BIN_DIR/omarchy-agent-ready" ]]; then
  say "--- doctor ---"
  "$BIN_DIR/omarchy-agent-ready" doctor 2>&1 | sed 's/^/    /' || true
fi

if (( RESTART )) && command -v omarchy >/dev/null 2>&1; then
  if omarchy restart shell >/dev/null 2>&1; then
    say "shell restarted"
  else
    warn "could not restart the shell; do it manually"
  fi
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
