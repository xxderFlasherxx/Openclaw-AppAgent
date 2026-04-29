#!/bin/bash
# ==============================================================================
# Test: Telegram-Commands Parser & Erlaubnis-Matrix (Teil J, Schritt 31)
# ==============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"
DOC="$SKILL_DIR/pipeline/telegram-commands.md"
FIXTURES="$SCRIPT_DIR/fixtures/telegram-events.json"

suite "J31-A. Pipeline-Dokument vorhanden"
assert_file_exists "$DOC" "pipeline/telegram-commands.md vorhanden"
for needle in "/newgame" "/status" "/phases" "/pause" "/resume" "/abort" \
              "/approve" "/rating" "/realrun" "/dryrun" "/skip" "/reset-phase" "/manual"; do
  if grep -q "$needle" "$DOC"; then _log_pass "Doc enthält $needle"
  else _log_fail "Doc enthält $needle" "Kommando fehlt"; fi
done

suite "J31-B. State-Erlaubnis-Matrix (Doc enthält jeden State)"
for st in WAITING ANALYZING PLANNING INITIALIZING EXECUTING VERIFYING \
          CORRECTING PHASE_DONE BUILDING COMPLETE ARCHIVING \
          AWAITING_FEEDBACK DONE ABORTED; do
  if grep -q "\`$st\`" "$DOC"; then _log_pass "Doc nennt State $st"
  else _log_fail "Doc nennt State $st" "fehlt"; fi
done

suite "J31-C. Fixture & Parser-Logik"
assert_file_exists "$FIXTURES" "fixtures/telegram-events.json vorhanden"
assert_json_valid  "$FIXTURES" "telegram-events.json valide"

count=$(jq '.events | length' "$FIXTURES" 2>/dev/null || echo 0)
if [ "$count" -ge 10 ]; then _log_pass "Fixture hat >=10 Events ($count)"
else _log_fail "Fixture hat >=10 Events" "nur $count"; fi

# Parser-Implementation (für Tests; produktiv interpretiert Hans dieselben Regeln)
parse_command() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"  # ltrim
  if [[ "$raw" =~ ^/ ]]; then
    local first rest
    first="${raw%% *}"
    rest=""
    if [[ "$raw" == *" "* ]]; then rest="${raw#* }"; fi
    printf "%s|%s" "$(echo "$first" | tr '[:upper:]' '[:lower:]')" "$rest"
  else
    printf "%s|%s" "<freitext>" "$raw"
  fi
}

validate_args() {
  local cmd="$1"; local args="$2"
  case "$cmd" in
    /newgame)  [ "${#args}" -ge 3 ] && [ "${#args}" -le 1000 ] || return 1 ;;
    /approve)  [[ "$args" =~ ^[0-9a-f]{12}$ ]] || return 1 ;;
    /rating)   [[ "$args" =~ ^[1-5]( .*)?$ ]] || return 1 ;;
    "<freitext>") [ "${#args}" -ge 3 ] || return 1 ;;
    *) return 0 ;;
  esac
}

allowed_commands_in_state() {
  case "$1" in
    WAITING)           echo "/newgame /status /realrun /dryrun" ;;
    ANALYZING)         echo "/status /abort" ;;
    PLANNING)          echo "/status /phases /abort /approve" ;;
    INITIALIZING)      echo "/status /abort" ;;
    EXECUTING)         echo "/status /pause /abort /reset-phase /manual" ;;
    VERIFYING)         echo "/status /pause /abort" ;;
    CORRECTING)        echo "/status /pause /abort /skip /reset-phase /manual" ;;
    PHASE_DONE)        echo "/status /pause /abort" ;;
    BUILDING)          echo "/status /abort" ;;
    COMPLETE)          echo "/status /rating" ;;
    ARCHIVING)         echo "/status" ;;
    AWAITING_FEEDBACK) echo "/status /rating /abort" ;;
    DONE)              echo "/newgame /status" ;;
    ABORTED)           echo "/newgame /status" ;;
    *)                 echo "" ;;
  esac
}

events=$(jq -c '.events[]' "$FIXTURES")
i=0
while IFS= read -r event; do
  name=$(echo "$event" | jq -r '.name')
  input=$(echo "$event" | jq -r '.input')
  exp_cmd=$(echo "$event" | jq -r '.expectedCommand')
  exp_args=$(echo "$event" | jq -r '.expectedArgs // empty')
  valid=$(echo "$event" | jq -r '.valid')
  from_state=$(echo "$event" | jq -r '.fromState // empty')
  validation_err=$(echo "$event" | jq -r '.validationError // empty')

  parsed=$(parse_command "$input")
  cmd="${parsed%%|*}"
  args="${parsed#*|}"

  if [ "$cmd" = "$exp_cmd" ]; then
    _log_pass "[$name] Parser ok ($cmd)"
  else
    _log_fail "[$name] Parser ok" "erwartet $exp_cmd, erhalten $cmd"
  fi

  if [ -n "$exp_args" ] && [ "$exp_args" != "null" ]; then
    if [ "$args" = "$exp_args" ]; then
      _log_pass "[$name] Args ok"
    else
      _log_fail "[$name] Args ok" "erwartet '$exp_args', erhalten '$args'"
    fi
  fi

  # Validierung
  if validate_args "$cmd" "$args" 2>/dev/null; then
    args_ok=1
  else
    args_ok=0
  fi

  if [ "$validation_err" = "args_too_short" ] || [ "$validation_err" = "hash_format" ] || [ "$validation_err" = "rating_range" ]; then
    if [ "$args_ok" -eq 0 ]; then
      _log_pass "[$name] Validierung schlägt fehl wie erwartet ($validation_err)"
    else
      _log_fail "[$name] Validierung schlägt fehl" "Args wurden akzeptiert"
    fi
  fi

  # State-Erlaubnis
  if [ -n "$from_state" ] && [ "$valid" = "false" ] && [ "$validation_err" = "command_not_allowed_in_state" ]; then
    allowed=$(allowed_commands_in_state "$from_state")
    if echo " $allowed " | grep -q " $cmd "; then
      _log_fail "[$name] Kommando in $from_state verboten" "Doc-Matrix erlaubt es"
    else
      _log_pass "[$name] Kommando in $from_state korrekt verboten"
    fi
  fi

  i=$((i+1))
done <<< "$events"

suite "J31-D. Config: telegram-Block"
for k in enabled maxInboxDrainPerTick implicitNewGameOnFreeText commandPrefix; do
  if jq -e "(.telegram | has(\"$k\"))" "$CFG" >/dev/null; then
    _log_pass "config.telegram.$k vorhanden"
  else
    _log_fail "config.telegram.$k vorhanden" "fehlt"
  fi
done

if [ "${TESTS_FAILED:-0}" -gt 0 ]; then
  echo "FAILED: $TESTS_FAILED" >&2
  exit 1
fi
exit 0
