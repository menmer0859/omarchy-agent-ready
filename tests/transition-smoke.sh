#!/usr/bin/env bash
# Round-1 transition regression tests. Fully isolated: temporary HOME/config/state,
# every external power/audio/display/idle command is a logging stub, and signals
# go through an injectable kill stub. NEVER touches the real desktop or runtime.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_SRC="$ROOT/bin/omarchy-agent-ready"

T="$(mktemp -d /tmp/opencode/agent-ready-transition.XXXXXX)"
trap 'cleanup' EXIT
cleanup() {
  # Reap any test-owned inhibitor/target processes before removing the sandbox.
  if [[ -f "$T/state/inhibit.pid" ]]; then
    kill -9 "$(cat "$T/state/inhibit.pid")" 2>/dev/null || true
  fi
  [[ -n ${TARGET_PID:-} ]] && kill -9 "$TARGET_PID" 2>/dev/null || true
  rm -rf "$T"
}

export HOME="$T/home"
export AGENT_READY_CONFIG_DIR="$T/config"
export AGENT_READY_STATE_DIR="$T/state"
export AGENT_READY_I18N_DIR="$ROOT/i18n"
export OMARCHY_LANGUAGE_FILE="$T/language"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME
mkdir -p "$HOME/.config/omarchy" "$AGENT_READY_CONFIG_DIR/enter.d" \
         "$AGENT_READY_CONFIG_DIR/leave.d" "$AGENT_READY_STATE_DIR" "$T/bin" "$T/log"
printf 'en\n' > "$OMARCHY_LANGUAGE_FILE"
cp "$ROOT/config/config.json" "$AGENT_READY_CONFIG_DIR/config.json"
printf '%s\n' '{"bar":{"layout":{"right":[]}},"idle":{"screensaver":150,"lock":300}}' \
  > "$HOME/.config/omarchy/shell.json"

STUB_LOG="$T/log/stubs.log"
FAIL_FILE="$T/fail"          # one token per line; matching stub exits 1
KILL_FAIL_FILE="$T/killfail" # "TERM"/"CONT" to fail that signal class
: > "$STUB_LOG"; : > "$FAIL_FILE"; : > "$KILL_FAIL_FILE"
export STUB_LOG FAIL_FILE KILL_FAIL_FILE

make_stub() {
  local name="$1" body="$2"
  cat > "$T/bin/$name" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$name" "\$*" >> "\$STUB_LOG"
if grep -qxF "$name \${1:-}" "\$FAIL_FILE" 2>/dev/null || grep -qxF "$name" "\$FAIL_FILE" 2>/dev/null; then exit 1; fi
$body
EOF
  chmod +x "$T/bin/$name"
}

# Generic success stubs (log argv; honour FAIL_FILE tokens "<name><firstarg>").
make_stub omarchy-system-lock        'exit 0'
make_stub omarchy-brightness-display 'case "$1" in --no-osd) echo 80;; on|off) exit 0;; *) exit 0;; esac'
make_stub omarchy-brightness-keyboard 'exit 0'
make_stub omarchy-toggle-idle        'exit 0'
make_stub omarchy-notification-send  'echo 1'
make_stub omarchy-audio-output-sink  'echo test-sink'
make_stub powerprofilesctl           'case "$1" in get) echo performance;; set) exit 0;; esac'
make_stub pactl                      'case "$1" in get-sink-mute) echo "Mute: no";; get-sink-volume) echo "Volume: front-left: 65536 / 100%";; *) exit 0;; esac'
make_stub hyprctl                    'case "$1" in monitors) echo "[{\"name\":\"DP-1\",\"disabled\":false,\"dpmsStatus\":true}]";; *) exit 0;; esac'
make_stub omarchy-shell              'echo "{\"locked\":true}"'
make_stub curl                       'exit 0'
make_stub pgrep                      'exit 1'   # no agents by default
make_stub timeout                    'shift; exec "$@"'

# systemd-inhibit stub: exec the trailing bash -c so the recorded PID really is
# the marker process (lets inhibit_alive/stop_inhibit exercise real /proc checks).
cat > "$T/bin/systemd-inhibit" <<'EOF'
#!/usr/bin/env bash
printf 'systemd-inhibit %s\n' "$*" >> "$STUB_LOG"
if grep -qxF 'systemd-inhibit' "$FAIL_FILE" 2>/dev/null; then exit 1; fi
while [[ $# -gt 0 && $1 != bash ]]; do shift; done
[[ ${1:-} == bash ]] && exec "$@"
exit 0
EOF
chmod +x "$T/bin/systemd-inhibit"

# Injectable kill: -0 always delegates to the real builtin-equivalent; TERM/CONT
# can be forced to fail so release failures are deterministic. Default signal for
# a bare PID is TERM.
cat > "$T/bin/kill-stub" <<'EOF'
#!/usr/bin/env bash
printf 'kill %s\n' "$*" >> "$STUB_LOG"
sig="-TERM"
for a in "$@"; do case "$a" in -*) sig="$a"; break;; esac; done
if [[ $sig != "-0" ]] && grep -qxF "${sig#-}" "$KILL_FAIL_FILE" 2>/dev/null; then exit 1; fi
exec /usr/bin/kill "$@"
EOF
chmod +x "$T/bin/kill-stub"
export AGENT_READY_KILL_BIN="$T/bin/kill-stub"

export PATH="$T/bin:$PATH"
CLI="$T/bin/omarchy-agent-ready"
cp "$CLI_SRC" "$CLI"; chmod +x "$CLI"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 :: $2"; fi; }
cfg_set() { jq "$1" "$AGENT_READY_CONFIG_DIR/config.json" > "$T/c.tmp" && mv "$T/c.tmp" "$AGENT_READY_CONFIG_DIR/config.json"; }
state() { jq -r "$1" "$AGENT_READY_STATE_DIR/state.json" 2>/dev/null; }
reset_fail() { : > "$FAIL_FILE"; : > "$KILL_FAIL_FILE"; }
stub_count() { grep -c "^$1 " "$STUB_LOG" 2>/dev/null || true; }

# --- P0-1: empty allow list means zero detection and no freeze exemption ------
"$CLI" reset-config >/dev/null
check "P0-1 reset keeps empty allow list" \
  '[ "$(jq -c .agents.allow "$AGENT_READY_CONFIG_DIR/config.json")" = "[]" ]'
"$CLI" doctor > "$T/doctor.out" 2>&1
check "P0-1 doctor reports 0 agents" 'grep -qF "agent allow list (0):" "$T/doctor.out"'
# A uniquely-named target must be frozen when the allow list is empty. The pgrep
# stub returns this test-owned PID for the unique marker pattern only.
MARK="arfreeze$$"
bash -c "exec -a '$MARK' sleep 30" & TARGET_PID=$!
sleep 0.2
cat > "$T/bin/pgrep" <<EOF
#!/usr/bin/env bash
printf 'pgrep %s\n' "\$*" >> "\$STUB_LOG"
for a in "\$@"; do [[ \$a == "$MARK"* ]] && { echo "$TARGET_PID"; exit 0; }; done
exit 1
EOF
chmod +x "$T/bin/pgrep"
cfg_set '.freeze.enabled=true | .freeze.patterns=["'"$MARK"'"] | .agents.allow=[]'
"$CLI" on >/dev/null
check "P0-1 empty list gives no freeze exemption (target stopped)" \
  '[ "$(awk "{print \$3}" /proc/$TARGET_PID/stat 2>/dev/null)" = "T" ]'
"$CLI" off >/dev/null
sleep 0.2
check "P0-1 off resumes the frozen target" \
  '[ "$(awk "{print \$3}" /proc/$TARGET_PID/stat 2>/dev/null)" != "T" ]'
kill -9 "$TARGET_PID" 2>/dev/null; wait "$TARGET_PID" 2>/dev/null; TARGET_PID=""
make_stub pgrep 'exit 1'
cfg_set '.freeze.enabled=false | .freeze.patterns=[]'

# --- I-04: disabled inhibitor is not "lost" ----------------------------------
cfg_set '.inhibit.enabled=false'
"$CLI" on >/dev/null
check "I-04 health.inhibitor=disabled when configured off" \
  '[ "$("$CLI" status-json | jq -r .health.inhibitor)" = "disabled" ]'
"$CLI" off >/dev/null
cfg_set '.inhibit.enabled=true'

# --- B-04: lock failure rolls back audio/dim and bounds retries ---------------
cfg_set '.audio.mute=true | .audio.suspendSinks=true | .screen.dimPercent=20'
echo 'omarchy-system-lock' > "$FAIL_FILE"
for i in 1 2 3 4; do
  "$CLI" on >/dev/null 2>&1
  rc=$?
  cnt=$(state '.retryCount // 0')
  check "B-04 attempt $i returns nonzero" '[ "$rc" -ne 0 ]'
  if (( i <= 3 )); then
    check "B-04 retryCount=$i after attempt $i" '[ "$cnt" = "'"$i"'" ]'
  else
    check "B-04 retry stops at 3 (count cleared after limit)" '[ "$cnt" = "0" ]'
    check "B-04 no further retry scheduled after limit" '[ "$(state ".healthLockFailed // false")" = "false" ]'
  fi
  check "B-04 state off after rollback $i" '[ "$(state .enabled)" = "false" ]'
done
# audio mute/suspend and dim were applied then must have been restored
check "B-04 rollback unmuted sink" 'grep -q "^pactl set-sink-mute test-sink 0" "$STUB_LOG"'
check "B-04 rollback unsuspended sink" 'grep -q "^pactl suspend-sink test-sink 0" "$STUB_LOG"'
check "B-04 rollback restored brightness" 'grep -q "^omarchy-brightness-display --no-osd 80%" "$STUB_LOG"'
reset_fail
cfg_set '.audio.mute=false | .audio.suspendSinks=false | .screen.dimPercent=0'
# successful entry clears retry metadata
"$CLI" on >/dev/null
check "B-04 success clears retryCount" '[ "$(state ".retryCount // 0")" = "0" ]'
"$CLI" off >/dev/null

# --- B-10: restore failures return nonzero and keep evidence ------------------
run_restore_failure() {
  local label="$1" token="$2" evidence="$3"
  reset_fail
  "$CLI" on >/dev/null
  : > "$STUB_LOG"
  printf '%s\n' "$token" > "$FAIL_FILE"
  "$CLI" off >/dev/null 2>&1; local rc=$?
  check "B-10 $label off returns nonzero" '[ "$rc" -ne 0 ]'
  check "B-10 $label keeps enabled state" '[ "$(state .enabled)" = "true" ]'
  check "B-10 $label keeps snapshot" '[ "$(state ".snapshot | type")" = "object" ]'
  check "B-10 $label keeps evidence ($evidence)" "$evidence"
  reset_fail
  "$CLI" off >/dev/null   # recovery completes once the fault is cleared
  check "B-10 $label recovers after fault cleared" '[ "$(state .enabled)" = "false" ]'
}
run_restore_failure "display-on" "omarchy-brightness-display on" '[ "$(state ".snapshot.applied.dpms")" = "true" ]'
run_restore_failure "keyboard"   "omarchy-brightness-keyboard restore" '[ "$(state ".snapshot.applied.keyboard")" = "true" ]'
cfg_set '.audio.mute=true'
run_restore_failure "audio-mute" "pactl set-sink-mute" '[ "$(state ".snapshot.applied.mute")" = "true" ]'
cfg_set '.audio.mute=false'
run_restore_failure "power"      "powerprofilesctl set" '[ "$(state ".snapshot.applied.power")" = "true" ]'
# Idle restore has a marker-removal fallback. Force BOTH the toggle and the
# marker file removal to fail by making the marker path a directory, then off
# must fail and keep the snapshot evidence.
reset_fail; "$CLI" on >/dev/null
echo 'omarchy-toggle-idle allow-idle' > "$FAIL_FILE"
mkdir -p "$HOME/.local/state/omarchy/indicators/stay-awake"
"$CLI" off >/dev/null 2>&1; rc=$?
check "B-10 idle fallback off returns nonzero" '[ "$rc" -ne 0 ]'
check "B-10 idle fallback keeps enabled state" '[ "$(state .enabled)" = "true" ]'
check "B-10 idle fallback keeps snapshot" '[ "$(state ".snapshot.applied.idle")" = "true" ]'
rmdir "$HOME/.local/state/omarchy/indicators/stay-awake" 2>/dev/null || true
: > "$FAIL_FILE"; "$CLI" off >/dev/null
check "B-10 idle fallback recovers after fault cleared" '[ "$(state .enabled)" = "false" ]'
# inhibitor release failure via kill stub
reset_fail; "$CLI" on >/dev/null
echo TERM > "$KILL_FAIL_FILE"
"$CLI" off >/dev/null 2>&1; rc=$?
check "B-10 inhibit-release off returns nonzero" '[ "$rc" -ne 0 ]'
check "B-10 inhibit PID record kept" '[ -f "$AGENT_READY_STATE_DIR/inhibit.pid" ]'
check "B-10 applied.inhibit kept true" '[ "$(state ".snapshot.applied.inhibit")" = "true" ]'
: > "$KILL_FAIL_FILE"; "$CLI" off >/dev/null
check "B-10 inhibit recovers after fault cleared" '[ "$(state .enabled)" = "false" ]'
# unfreeze failure via kill stub
reset_fail
cfg_set '.freeze.enabled=true | .freeze.patterns=["'"$MARK"'b"]'
bash -c "exec -a '${MARK}b' sleep 30" & TARGET_PID=$!
sleep 0.2
cat > "$T/bin/pgrep" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ \$a == "${MARK}b" ]] && { echo "$TARGET_PID"; exit 0; }; done
exit 1
EOF
chmod +x "$T/bin/pgrep"
"$CLI" on >/dev/null
echo CONT > "$KILL_FAIL_FILE"
"$CLI" off >/dev/null 2>&1; rc=$?
check "B-10 unfreeze off returns nonzero" '[ "$rc" -ne 0 ]'
check "B-10 frozen record kept" '[ -s "$AGENT_READY_STATE_DIR/frozen.pids" ]'
: > "$KILL_FAIL_FILE"; "$CLI" off >/dev/null
check "B-10 unfreeze recovers after fault cleared" '[ "$(state .enabled)" = "false" ]'
kill -9 "$TARGET_PID" 2>/dev/null; wait "$TARGET_PID" 2>/dev/null; TARGET_PID=""
make_stub pgrep 'exit 1'
cfg_set '.freeze.enabled=false | .freeze.patterns=[]'

# --- B-10: restore uses snapshot, not live config -----------------------------
reset_fail
cfg_set '.audio.mute=true'
"$CLI" on >/dev/null
cfg_set '.audio.mute=false'     # user edits config while active
: > "$STUB_LOG"
"$CLI" off >/dev/null
check "B-10 off restores from snapshot despite config edit" \
  'grep -q "^pactl set-sink-mute test-sink 0" "$STUB_LOG"'
cfg_set '.audio.mute=false'

# --- B-09 / I-01: arm-fire/disarm race + auto-arm dedupe ----------------------
reset_fail
"$CLI" arm 30 >/dev/null
TOKEN=$(jq -r .token "$AGENT_READY_STATE_DIR/pending.json")
"$CLI" _arm-fire "$TOKEN" >/dev/null 2>&1 &
FIRE_PID=$!
"$CLI" disarm >/dev/null 2>&1 &
DISARM_PID=$!
wait "$FIRE_PID" "$DISARM_PID" 2>/dev/null
# Whichever won the lock, the outcome must be consistent: either fully off
# (disarm first) or fully active with phase active (fire first) — never
# enabled=true with phase=off, and never a leftover pending file.
check "B-09 no pending left after race" '[ ! -f "$AGENT_READY_STATE_DIR/pending.json" ]'
check "B-09 consistent state after race" \
  '[ "$(state .enabled)" = "false" ] || { [ "$(state .enabled)" = "true" ] && [ "$(state .phase)" = "active" ]; }'
"$CLI" off >/dev/null 2>&1
# double arm-fire enters exactly once
"$CLI" arm 30 >/dev/null
TOKEN=$(jq -r .token "$AGENT_READY_STATE_DIR/pending.json")
: > "$STUB_LOG"
"$CLI" _arm-fire "$TOKEN" >/dev/null 2>&1 &
P1=$!
"$CLI" _arm-fire "$TOKEN" >/dev/null 2>&1 &
P2=$!
wait "$P1" "$P2" 2>/dev/null
check "B-09 double arm-fire locks screen at most once" '[ "$(stub_count omarchy-system-lock)" -le 1 ]'
check "B-09 double arm-fire ends active" '[ "$(state .enabled)" = "true" ]'
"$CLI" off >/dev/null
# auto-arm dedupe: second auto-arm while pending is a no-op (same token)
"$CLI" auto-arm >/dev/null
T1=$(jq -r .token "$AGENT_READY_STATE_DIR/pending.json")
"$CLI" auto-arm >/dev/null
T2=$(jq -r .token "$AGENT_READY_STATE_DIR/pending.json")
check "I-01 auto-arm dedupe keeps same pending token" '[ "$T1" = "$T2" ]'
"$CLI" disarm >/dev/null

# B-02 / B-03: Widget face-state static contract. A full QML harness would
# need the live Omarchy shell; these assertions verify the exact state-machine
# properties that make the blank-card and cancel-countdown bugs impossible.
QML="$ROOT/Widget.qml"
check_qml() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$QML"; then ok "$label"; else bad "$label (missing: $needle)"; fi
}
check_qml "B-03 single face enum exists" 'readonly property string face: root.popupOpen ? "settings"'
check_qml "B-03 showArming derives from face only" 'readonly property bool showArming: root.face === "arming"'
check_qml "B-03 showSettings derives from face only" 'readonly property bool showSettings: root.face === "settings"'
check_qml "B-03 cardOpen derives from face only" 'readonly property bool cardOpen: root.face !== "closed"'
check_qml "B-03 arming closes stale digest" 'if (root.arming && root.digestOpen) root.digestOpen = false'
check_qml "B-02 monitor stays enabled during auto countdown" 'root.arming && root.autoTriggered && root.disarmOnInput'
check_qml "B-02 isIdle-false cancels auto countdown" 'else if (!isIdle) root.disarmAutoCountdown()'
check_qml "B-02 duplicate trigger guarded" 'if (root.arming || root.activeState || root.phase !== "off" || !root.stateLoaded) return'

printf '\nTRANSITION RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
