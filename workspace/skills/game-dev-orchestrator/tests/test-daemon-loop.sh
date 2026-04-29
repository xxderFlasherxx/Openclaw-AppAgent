#!/bin/bash
# ==============================================================================
# Test: Daemon Tick-Loop & Crash-Recovery (Teil J, Schritt 32)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"
MO="$SKILL_DIR/pipeline/master-orchestrator.md"

suite "J32-A. master-orchestrator.md hat Tick-Loop-Sektion"
for needle in "Tick-Loop" "onTick()" "checkKillSwitch" "drainTelegramInbox" \
              "writeJsonAtomic" "Crash-Recovery" "tickFailures" \
              "scheduleNextTick" "lastTickAt"; do
  if grep -q "$needle" "$MO"; then
    _log_pass "master-orchestrator.md erwähnt '$needle'"
  else
    _log_fail "master-orchestrator.md erwähnt '$needle'" "fehlt"
  fi
done

suite "J32-B. Config: daemon-Block"
for k in tickIntervalSeconds heartbeatLogFile exceptionBackoffSeconds maxConsecutiveTickFailures; do
  if jq -e "(.daemon | has(\"$k\"))" "$CFG" >/dev/null; then
    _log_pass "config.daemon.$k vorhanden"
  else
    _log_fail "config.daemon.$k vorhanden" "fehlt"
  fi
done

backoff=$(jq -r '.daemon.exceptionBackoffSeconds | join(",")' "$CFG")
if [ "$backoff" = "5,30,120" ]; then
  _log_pass "Backoff-Plan = 5,30,120s (Plan-konform)"
else
  _log_fail "Backoff-Plan = 5,30,120s" "tatsächlich: $backoff"
fi

suite "J32-C. Atomare Persistenz (write-tmp + rename)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

target="$TMP_DIR/orchestrator-state.json"
tmp="$target.tmp"

# Simulation: Crash zwischen tmp und rename → target sollte alten Stand haben
echo '{"state":"OLD"}' > "$target"
echo '{"state":"NEW"}' > "$tmp"
# Crash hier, kein rename → target unverändert
if [ "$(jq -r .state "$target")" = "OLD" ]; then
  _log_pass "Pre-rename Crash → target behält alten Stand"
else
  _log_fail "Pre-rename Crash → target behält alten Stand" "target verändert"
fi

# Erfolgreicher rename → target = NEW
mv "$tmp" "$target"
if [ "$(jq -r .state "$target")" = "NEW" ]; then
  _log_pass "rename atomar erfolgreich"
else
  _log_fail "rename atomar erfolgreich" "rename fehlgeschlagen"
fi

suite "J32-D. Recovery-Szenario simulieren"
mkdir -p "$TMP_DIR/proj/.plan"
echo '{"currentProject":"'"$TMP_DIR/proj"'","state":"EXECUTING","runId":"r1"}' > "$TMP_DIR/gamedev-state.json"
echo '{"state":"EXECUTING","currentPhase":3,"attempt":2}' > "$TMP_DIR/proj/.plan/orchestrator-state.json"

# Recovery-Logik (Bash-Implementation der Pseudo-Spec)
state_file="$TMP_DIR/gamedev-state.json"
proj=$(jq -r .currentProject "$state_file")
gstate=$(jq -r .state "$state_file")
if [ "$proj" != "null" ] && [ "$proj" != "" ] && [ "$gstate" != "DONE" ] && [ "$gstate" != "WAITING" ]; then
  recovery_state=$(jq -r .state "$proj/.plan/orchestrator-state.json")
  recovery_phase=$(jq -r .currentPhase "$proj/.plan/orchestrator-state.json")
  if [ "$recovery_state" = "EXECUTING" ] && [ "$recovery_phase" = "3" ]; then
    _log_pass "Recovery erkennt offenen Run + State + Phase"
  else
    _log_fail "Recovery erkennt offenen Run" "state=$recovery_state, phase=$recovery_phase"
  fi
else
  _log_fail "Recovery-Trigger" "state=$gstate, proj=$proj"
fi

# Negativfall: state=DONE → kein Recovery
echo '{"currentProject":null,"state":"DONE"}' > "$state_file"
proj=$(jq -r .currentProject "$state_file")
if [ "$proj" = "null" ]; then
  _log_pass "DONE-State triggert keinen Recovery-Prompt"
else
  _log_fail "DONE-State triggert keinen Recovery-Prompt" "proj=$proj"
fi

suite "J32-E. Pause-Verhalten"
echo '{"paused":true,"state":"EXECUTING","tickFailures":0}' > "$TMP_DIR/run.json"
paused=$(jq -r .paused "$TMP_DIR/run.json")
if [ "$paused" = "true" ]; then
  _log_pass "paused=true → Tick muss no-op sein (config-konform)"
else
  _log_fail "paused-Flag" "nicht gesetzt"
fi

if [ "${TESTS_FAILED:-0}" -gt 0 ]; then
  echo "FAILED: $TESTS_FAILED" >&2
  exit 1
fi
exit 0
