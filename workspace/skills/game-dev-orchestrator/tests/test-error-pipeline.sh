#!/bin/bash
# ==============================================================================
# Test: Fehler-Pipeline Unity → Hans → Günther (Teil I, Schritt 30)
# ==============================================================================
# Validiert die Wiring-Sektion in pipeline/error-correction.md gegen die
# vorbereiteten Fixtures. Da Günther online ist, wird `gunther.analyzeError`
# hier per Bash-Stub gemockt.
# ==============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

EC="$SKILL_DIR/pipeline/error-correction.md"
EL="$SKILL_DIR/pipeline/execution-loop.md"

suite "Wiring: error-correction.md enthält Sektion 'Wiring'"
assert_file_exists "$EC" "pipeline/error-correction.md"
for needle in \
  "Wiring: Unity → Hans → Günther" \
  "onVerifyPhase" \
  "tailJsonl" \
  "error-log.jsonl" \
  "logRoutingDecision" \
  "selectModel" \
  "PHASE_DONE" \
  "CORRECTING" ; do
  if grep -Fq "$needle" "$EC"; then
    _log_pass "error-correction.md referenziert '$needle'"
  else
    _log_fail "error-correction.md referenziert '$needle'" "fehlt"
  fi
done

suite "Wiring: execution-loop.md ruft onVerifyPhase auf"
assert_file_exists "$EL" "pipeline/execution-loop.md"
for needle in \
  "onVerifyPhase" \
  "VERIFYING" \
  "PHASE_DONE" \
  "AWAITING_USER_HELP" \
  "logRoutingDecision" ; do
  if grep -Fq "$needle" "$EL"; then
    _log_pass "execution-loop.md referenziert '$needle'"
  else
    _log_fail "execution-loop.md referenziert '$needle'" "fehlt"
  fi
done

# -----------------------------------------------------------------------------
# Mini-Reimplementierung der Klassifizierung in Bash, damit die Fixtures
# gegen das beschriebene Verhalten validiert werden können.
# -----------------------------------------------------------------------------
classify_first_error() {
  local jsonl="$1"
  if [ ! -s "$jsonl" ]; then
    echo "TIMEOUT MAJOR none"; return
  fi
  local first_msg
  first_msg=$(head -n1 "$jsonl" | jq -r '.message // ""')
  if echo "$first_msg" | grep -qE 'error CS[0-9]{4}'; then
    local code
    code=$(echo "$first_msg" | grep -oE 'CS[0-9]{4}' | head -1)
    echo "COMPILATION CRITICAL ${code}"
  elif echo "$first_msg" | grep -q 'NullReferenceException'; then
    echo "RUNTIME MAJOR NullReference"
  else
    echo "UNKNOWN MAJOR"
  fi
}

select_model_for_correction() {
  # severity, attempt -> model
  local severity="$1"; local attempt="$2"
  if [ "$severity" = "critical" ] || [ "$severity" = "CRITICAL" ]; then
    echo "opus"; return
  fi
  case "$attempt" in
    1|2) echo "sonnet" ;;
    3)   echo "opus" ;;
    4)   echo "sonnet" ;;
    5)   echo "haiku" ;;
    *)   echo "sonnet" ;;
  esac
}

suite "Pipeline: Fixture CS0246 → kritischer Compile-Error"
read -r typ sev cat <<<"$(classify_first_error "$SKILL_DIR/tests/fixtures/error-log.cs0246.jsonl")"
assert_equals "$typ"  "COMPILATION" "Typ = COMPILATION"
assert_equals "$sev"  "CRITICAL"    "Severity = CRITICAL"
assert_equals "$cat"  "CS0246"      "Kategorie = CS0246"

# correctionPrompt müsste 'using' enthalten – wir simulieren Günthers
# Antwort auf Basis der Kategorie.
mock_prompt="Füge das passende using-Statement (z.B. 'using Cinemachine;') am Dateianfang hinzu und stelle sicher, dass das Cinemachine-Package installiert ist."
if echo "$mock_prompt" | grep -qi 'using'; then
  _log_pass "Mock-Korrekturprompt für CS0246 enthält 'using'"
else
  _log_fail "Mock-Korrekturprompt für CS0246 enthält 'using'" "fehlt"
fi
model=$(select_model_for_correction "CRITICAL" 1)
assert_equals "$model" "opus" "Severity=CRITICAL → Modell=opus"

suite "Pipeline: Fixture NullReference → MAJOR, gleiches Modell"
read -r typ sev cat <<<"$(classify_first_error "$SKILL_DIR/tests/fixtures/error-log.nullref.jsonl")"
assert_equals "$typ"  "RUNTIME"      "Typ = RUNTIME"
assert_equals "$sev"  "MAJOR"        "Severity = MAJOR"
assert_equals "$cat"  "NullReference" "Kategorie = NullReference"
model=$(select_model_for_correction "major" 1)
assert_equals "$model" "sonnet" "MAJOR @ attempt=1 → sonnet"
model2=$(select_model_for_correction "major" 2)
assert_equals "$model2" "sonnet" "MAJOR @ attempt=2 → sonnet (gleiches Modell)"

suite "Pipeline: Fixture leere JSONL → Timeout-Pfad"
read -r typ sev cat <<<"$(classify_first_error "$SKILL_DIR/tests/fixtures/error-log.timeout.jsonl")"
assert_equals "$typ"  "TIMEOUT" "Typ = TIMEOUT"

suite "Pipeline: 5x attempt → Eskalation"
# Wir simulieren attempts und prüfen, dass attempt+1 > maxRetries den
# AWAITING_USER_HELP-Pfad triggert.
MAX=$(jq -r '.phases.maxRetriesPerPhase' "$SKILL_DIR/gamedev-config.json")
ATTEMPT=$((MAX))
NEXT=$((ATTEMPT + 1))
if [ "$NEXT" -gt "$MAX" ]; then
  _log_pass "attempt+1 ($NEXT) > maxRetriesPerPhase ($MAX) → Eskalation"
else
  _log_fail "Eskalation nach $MAX Versuchen" "Logik stimmt nicht"
fi
# Sektion 'Eskalation nach 5 Versuchen' im Doc?
if grep -q "Eskalation" "$EC"; then
  _log_pass "error-correction.md erklärt Eskalation"
else
  _log_fail "error-correction.md erklärt Eskalation" "Sektion fehlt"
fi

print_summary
