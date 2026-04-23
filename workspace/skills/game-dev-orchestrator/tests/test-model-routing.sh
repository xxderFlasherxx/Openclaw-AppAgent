#!/bin/bash
# ==============================================================================
# Model-Routing Unit-Test (Teil G, Schritt 22)
# ------------------------------------------------------------------------------
# Implementiert den in pipeline/model-routing.md beschriebenen Algorithmus
# und prüft ihn gegen die Testfälle in fixtures/model-routing-cases.json.
#
# Exit: 0 = alle Fälle korrekt, 1 = Abweichung, 2 = Konfig-Fehler.
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$SKILL_DIR/gamedev-config.json"
CASES="$SCRIPT_DIR/fixtures/model-routing-cases.json"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

if [ ! -f "$CONFIG" ] || [ ! -f "$CASES" ]; then
  echo "Config/Fixtures fehlen: $CONFIG oder $CASES" >&2
  exit 2
fi

CURRENT_SUITE="model-routing"

# select_model <phaseId> <category> <name> <prompt> <retryCount> → stdout: model
select_model() {
  local phase_id="$1" category="$2" name="$3" prompt="$4" retry_count="$5"

  # 1) Override
  local override
  override=$(jq -r --arg k "$phase_id" '.modelRouting.overrides[$k] // empty' "$CONFIG")
  if [ -n "$override" ]; then
    echo "$override"; return
  fi

  # 2) Retry-Eskalation
  local escalate_at
  escalate_at=$(jq -r '.modelRouting.escalateAtRetry' "$CONFIG")
  if [ "$retry_count" -ge "$escalate_at" ]; then
    echo "opus"; return
  fi

  # 3) Kategorie-Map
  if [ -n "$category" ] && [ "$category" != "null" ]; then
    local cat_model
    cat_model=$(jq -r --arg c "$category" '.modelRouting.categoryMap[$c] // empty' "$CONFIG")
    if [ -n "$cat_model" ]; then
      echo "$cat_model"; return
    fi
  fi

  # 4) Keyword-Scoring
  local text_lc
  text_lc=$(echo "$name $prompt" | tr '[:upper:]' '[:lower:]')

  local score_haiku=0 score_sonnet=0 score_opus=0
  local kw
  while IFS= read -r kw; do
    [ -z "$kw" ] && continue
    local kw_lc
    kw_lc=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
    [[ "$text_lc" == *"$kw_lc"* ]] && score_haiku=$((score_haiku + 1))
  done < <(jq -r '.modelRouting.keywords.haiku[]' "$CONFIG")

  while IFS= read -r kw; do
    [ -z "$kw" ] && continue
    local kw_lc
    kw_lc=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
    [[ "$text_lc" == *"$kw_lc"* ]] && score_sonnet=$((score_sonnet + 1))
  done < <(jq -r '.modelRouting.keywords.sonnet[]' "$CONFIG")

  while IFS= read -r kw; do
    [ -z "$kw" ] && continue
    local kw_lc
    kw_lc=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
    [[ "$text_lc" == *"$kw_lc"* ]] && score_opus=$((score_opus + 2))
  done < <(jq -r '.modelRouting.keywords.opus[]' "$CONFIG")

  # 5) Entscheidung
  if [ "$score_opus" -ge 2 ]; then
    echo "opus"; return
  fi
  if [ "$score_haiku" -gt "$score_sonnet" ] && [ "$score_opus" -eq 0 ]; then
    echo "haiku"; return
  fi

  jq -r '.modelRouting.defaultModel' "$CONFIG"
}

# ── Testfälle durchlaufen ────────────────────────────────────────────────────
num_cases=$(jq -r '.cases | length' "$CASES")
if [ "$num_cases" -eq 0 ]; then
  echo "Keine Testfälle in $CASES" >&2
  exit 2
fi

for ((i=0; i<num_cases; i++)); do
  name=$(jq -r ".cases[$i].name" "$CASES")
  phase_id=$(jq -r ".cases[$i].phaseId" "$CASES")
  category=$(jq -r ".cases[$i].category // \"\"" "$CASES")
  phase_name=$(jq -r ".cases[$i].phaseName // \"\"" "$CASES")
  prompt=$(jq -r ".cases[$i].prompt // \"\"" "$CASES")
  retry=$(jq -r ".cases[$i].retryCount // 0" "$CASES")
  expected=$(jq -r ".cases[$i].expected" "$CASES")

  actual=$(select_model "$phase_id" "$category" "$phase_name" "$prompt" "$retry")
  if [ "$actual" = "$expected" ]; then
    _log_pass "Routing: $name → $actual"
  else
    _log_fail "Routing: $name" "erwartet=$expected, tatsächlich=$actual"
  fi
done

printf "\n${BOLD}Summary:${NC} %d passed, %d failed\n" "$TESTS_PASSED" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
