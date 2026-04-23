#!/bin/bash
# ==============================================================================
# Genre-Detection Unit-Test
# ------------------------------------------------------------------------------
# Implementiert den in pipeline/planning-phase.md beschriebenen
# Keyword-Algorithmus (1 Punkt pro Keyword, 3 Punkte pro Referenz-Spiel)
# und vergleicht das Ergebnis gegen die Ground-Truth-Tabelle.
#
# Ausgabe: erzeugt bei Aufruf "passed/failed/ambiguous"-Zählung.
# Exit: 0 = alle klar erkannten Fälle korrekt, 1 = Abweichung.
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULES="$SCRIPT_DIR/fixtures/genre-rules.json"
CASES="$SCRIPT_DIR/fixtures/genre-detection-cases.json"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

if [ ! -f "$RULES" ] || [ ! -f "$CASES" ]; then
  echo "Fixtures fehlen." >&2; exit 2
fi

# detect_genre <prompt> → schreibt "genre score" auf stdout.
# Score-Konvention: Keyword = 1 Punkt, Referenz-Spiel = 3 Punkte.
detect_genre() {
  local prompt_lc
  prompt_lc=$(echo "$1" | tr '[:upper:]' '[:lower:]')

  local best_genre=""
  local best_score=0
  local second_score=0

  local num_rules
  num_rules=$(jq -r '.rules | length' "$RULES")

  for ((i=0; i<num_rules; i++)); do
    local genre score=0
    genre=$(jq -r ".rules[$i].genre" "$RULES")

    # Keywords: +1
    while IFS= read -r kw; do
      [ -z "$kw" ] && continue
      local kw_lc
      kw_lc=$(echo "$kw" | tr '[:upper:]' '[:lower:]')
      if [[ "$prompt_lc" == *"$kw_lc"* ]]; then
        score=$((score + 1))
      fi
    done < <(jq -r ".rules[$i].keywords_de[], .rules[$i].keywords_en[]" "$RULES")

    # Referenzspiele: +3
    while IFS= read -r rg; do
      [ -z "$rg" ] && continue
      local rg_lc
      rg_lc=$(echo "$rg" | tr '[:upper:]' '[:lower:]')
      if [[ "$prompt_lc" == *"$rg_lc"* ]]; then
        score=$((score + 3))
      fi
    done < <(jq -r ".rules[$i].referenceGames[]" "$RULES")

    if [ "$score" -gt "$best_score" ]; then
      second_score=$best_score
      best_score=$score
      best_genre=$genre
    elif [ "$score" -gt "$second_score" ]; then
      second_score=$score
    fi
  done

  echo "$best_genre $best_score $second_score"
}

suite "Genre-Detection – eindeutige Fälle"

num_cases=$(jq -r '.cases | length' "$CASES")
for ((i=0; i<num_cases; i++)); do
  prompt=$(jq -r ".cases[$i].prompt"   "$CASES")
  expected=$(jq -r ".cases[$i].expected" "$CASES")
  read -r got score second < <(detect_genre "$prompt")
  assert_equals "$got" "$expected" "[$((i+1))/$num_cases] '$prompt' → $expected (score=$score)"
done

suite "Genre-Detection – mehrdeutige Fälle (Fallback erwartet)"
num_amb=$(jq -r '.ambiguous | length' "$CASES")
for ((i=0; i<num_amb; i++)); do
  prompt=$(jq -r ".ambiguous[$i].prompt" "$CASES")
  read -r got score second < <(detect_genre "$prompt")
  # In diesen Fällen ist der Score 0 oder < 2 → Günther-Fallback nötig
  if [ "$score" -lt 2 ]; then
    _log_pass "Ambiguous '$prompt' triggert Fallback (score=$score)"
  else
    _log_fail "Ambiguous '$prompt' triggert Fallback" "score=$score, genre=$got (hätte unter 2 bleiben müssen)"
  fi
done

print_summary
