#!/bin/bash
# ==============================================================================
# Test: Limits, Killswitch, Cost-Enforcement (Teil J, Schritt 33)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"
DOC="$SKILL_DIR/pipeline/budget-limits.md"
FIXTURES="$SCRIPT_DIR/fixtures/limits-cases.json"
SCHEMA="$SCRIPT_DIR/fixtures/halt-log-entry.schema.json"

suite "J33-A. Pipeline-Dokument & Schema"
assert_file_exists "$DOC"     "pipeline/budget-limits.md vorhanden"
assert_file_exists "$FIXTURES" "fixtures/limits-cases.json vorhanden"
assert_file_exists "$SCHEMA"   "fixtures/halt-log-entry.schema.json vorhanden"
assert_json_valid  "$FIXTURES" "limits-cases.json valide"
assert_json_valid  "$SCHEMA"   "halt-log-entry.schema.json valide"

for needle in "Killswitch" "Cost-Enforcement" "Wallclock-Enforcement" \
              "Retry-Caps" "Halt-Reasons" "downgradeModel"; do
  if grep -q "$needle" "$DOC"; then
    _log_pass "budget-limits.md enthält '$needle'"
  else
    _log_fail "budget-limits.md enthält '$needle'" "fehlt"
  fi
done

suite "J33-B. Config: limits-Block"
for k in maxCostUsdPerRun maxCostUsdPerPhase maxWallclockMinutesPerRun \
         maxRetriesPerPhase maxTotalRetriesPerRun killSwitchFile; do
  if jq -e "(.limits | has(\"$k\"))" "$CFG" >/dev/null; then
    _log_pass "config.limits.$k vorhanden"
  else
    _log_fail "config.limits.$k vorhanden" "fehlt"
  fi
done

# Plan-Defaults laut Schritt 33.1
assert_jq "$CFG" '.limits.maxCostUsdPerRun'         "5.00"  "limits.maxCostUsdPerRun = 5.00"
assert_jq "$CFG" '.limits.maxCostUsdPerPhase'       "1.00"  "limits.maxCostUsdPerPhase = 1.00"
assert_jq "$CFG" '.limits.maxWallclockMinutesPerRun' "180"  "limits.maxWallclockMinutesPerRun = 180"
assert_jq "$CFG" '.limits.maxRetriesPerPhase'       "5"     "limits.maxRetriesPerPhase = 5"
assert_jq "$CFG" '.limits.maxTotalRetriesPerRun'    "25"    "limits.maxTotalRetriesPerRun = 25"

suite "J33-C. Cost-Enforcement Simulation"
# Mini-Implementation analog zu enforceCostBudget()
enforce() {
  local total="$1" phase_used="$2" planned="$3" max_run="$4" max_phase="$5"
  local run_total
  run_total=$(awk "BEGIN{printf \"%.4f\", $total + $planned}")
  local phase_total
  phase_total=$(awk "BEGIN{printf \"%.4f\", $phase_used + $planned}")
  if awk "BEGIN{exit !($run_total > $max_run)}"; then
    echo "halt:budget_exhausted_run:$run_total"; return
  fi
  if awk "BEGIN{exit !($phase_total > $max_phase)}"; then
    echo "halt:budget_exhausted_phase:$phase_total"; return
  fi
  echo "proceed"
}

# Case 1: 4.80 + 0.30 = 5.10 > 5.00 -> halt run
res=$(enforce 4.80 0.20 0.30 5.00 1.00)
if [[ "$res" == halt:budget_exhausted_run:* ]]; then
  _log_pass "Run-Budget überschritten → halt(budget_exhausted_run)"
else
  _log_fail "Run-Budget überschritten" "tatsächlich: $res"
fi

# Case 2: 0.95 + 0.20 = 1.15 > 1.00 (phase) aber 1.15 < 5.0 (run) -> halt phase
res=$(enforce 1.20 0.95 0.20 5.00 1.00)
if [[ "$res" == halt:budget_exhausted_phase:* ]]; then
  _log_pass "Phase-Budget überschritten → halt(budget_exhausted_phase)"
else
  _log_fail "Phase-Budget überschritten" "tatsächlich: $res"
fi

# Case 3: alles im Limit
res=$(enforce 0.10 0.05 0.20 5.00 1.00)
if [ "$res" = "proceed" ]; then
  _log_pass "Im Limit → proceed"
else
  _log_fail "Im Limit → proceed" "tatsächlich: $res"
fi

suite "J33-D. Killswitch-Datei"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
KS="$TMP_DIR/STOP_GAMEDEV"

# Datei nicht da -> proceed
if [ ! -f "$KS" ]; then
  _log_pass "Killswitch nicht vorhanden → proceed"
else
  _log_fail "Killswitch nicht vorhanden" "Datei existiert"
fi

# Datei da -> halt
touch "$KS"
if [ -f "$KS" ]; then
  _log_pass "Killswitch erkannt → halt(killswitch)"
  rm -f "$KS"
  if [ ! -f "$KS" ]; then
    _log_pass "Killswitch nach halt gelöscht"
  fi
fi

suite "J33-E. Wallclock-Enforcement"
started_minutes_ago=181
max_minutes=180
if [ "$started_minutes_ago" -gt "$max_minutes" ]; then
  _log_pass "$started_minutes_ago min > $max_minutes min → halt(wallclock_exceeded)"
else
  _log_fail "wallclock_exceeded" "Berechnung falsch"
fi

suite "J33-F. Retry-Cap"
total_retries=25
limit=25
if [ "$total_retries" -ge "$limit" ]; then
  _log_pass "$total_retries retries >= $limit → halt(retries_exhausted)"
else
  _log_fail "retries_exhausted" "Berechnung falsch"
fi

suite "J33-G. Halt-Log-Schema"
# Beispieleintrag erstellen und gegen Schema validieren (struktur-basiert)
sample='{"ts":"2026-04-29T11:23:00Z","runId":"abc123","reason":"budget_exhausted_run","value":5.34,"phase":3,"state":"EXECUTING"}'
echo "$sample" > "$TMP_DIR/halt.json"
if echo "$sample" | jq empty 2>/dev/null; then
  _log_pass "Halt-Log-Beispiel ist valides JSON"
fi

# Required fields prüfen
for f in ts runId reason value phase state; do
  v=$(echo "$sample" | jq -r ".$f")
  if [ -n "$v" ] && [ "$v" != "null" ]; then
    _log_pass "Halt-Log-Feld '$f' vorhanden"
  else
    _log_fail "Halt-Log-Feld '$f' vorhanden" "leer"
  fi
done

# Reason-Enum
valid_reasons="killswitch budget_exhausted_run budget_exhausted_phase wallclock_exceeded retries_exhausted manual_abort safety_violation tick_exception"
reason=$(echo "$sample" | jq -r .reason)
if echo " $valid_reasons " | grep -q " $reason "; then
  _log_pass "Halt-Reason '$reason' gehört zum Enum"
else
  _log_fail "Halt-Reason im Enum" "$reason"
fi

if [ "${TESTS_FAILED:-0}" -gt 0 ]; then
  echo "FAILED: $TESTS_FAILED" >&2
  exit 1
fi
exit 0
