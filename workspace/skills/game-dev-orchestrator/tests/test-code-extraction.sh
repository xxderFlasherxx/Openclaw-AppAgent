#!/bin/bash
# ==============================================================================
# Test: Code-Extraction & Accept-Policy (Teil H, Schritt 26)
# ==============================================================================
# Validiert die Accept-Policy aus pipeline/copilot-bridge.md gegen 5 Fixtures.
# Erwartung lt. Plan-Schritt 26.5:  4x reject, 1x accept.
#
# Implementiert eine schlanke Bash-Version von extractCleanCode():
#   - markiert Markdown-Fences  → reason=markdown_fence
#   - markiert Preambles        → reason=preamble
#   - prüft Klammer-Balance     → reason=unbalanced_syntax
#   - prüft verbotene Tokens    → reason=forbidden_token
# Strikte Variante: bereits eine dieser Markierungen → reject.
# ==============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"
FIX_DIR="$SCRIPT_DIR/fixtures/extraction"

printf "${BOLD}════════════════════════════════════════════════════${NC}\n"
printf "${BOLD} Code-Extraction Tests (Teil H – Schritt 26)${NC}\n"
printf "${BOLD}════════════════════════════════════════════════════${NC}\n"

# ── 1. Konfiguration vorhanden ───────────────────────────────
suite "1. codeExtraction-Konfiguration"
assert_jq_nonempty "$CFG" '.codeExtraction'                       "codeExtraction-Block vorhanden"
assert_jq_nonempty "$CFG" '.codeExtraction.forbiddenTokens'       "forbiddenTokens vorhanden"
assert_jq_nonempty "$CFG" '.codeExtraction.maxFileSizeKb'         "maxFileSizeKb gesetzt"
assert_jq_nonempty "$CFG" '.codeExtraction.diffDir'               "diffDir gesetzt"
assert_jq          "$CFG" '.codeExtraction.stripMarkdownFences'   "true" "stripMarkdownFences=true"
assert_jq          "$CFG" '.codeExtraction.stripPreambles'        "true" "stripPreambles=true"
assert_jq          "$CFG" '.codeExtraction.requireBalancedBraces' "true" "requireBalancedBraces=true"

# Pflicht-Tokens vorhanden
for tok in "TODO-COPILOT" "PLACEHOLDER" "<PROMPT>" "your code here" \
           "implementiere dies" "...existing code..."; do
  found=$(jq -r --arg t "$tok" '[.codeExtraction.forbiddenTokens[] | select(.==$t)] | length' "$CFG")
  if [ "$found" -ge 1 ]; then
    _log_pass "forbidden token konfiguriert: '$tok'"
  else
    _log_fail "forbidden token konfiguriert: '$tok'" "fehlt"
  fi
done

# ── 2. extractCleanCode-Validator ────────────────────────────
extract_check() {
  local file="$1"
  if [ ! -f "$file" ]; then echo "missing"; return; fi
  local content
  content=$(cat "$file")

  # Markdown-Fences ?
  if printf '%s\n' "$content" | grep -qE '^[[:space:]]*```'; then
    echo "markdown_fence"; return
  fi

  # Preamble ?
  if printf '%s\n' "$content" | head -n 3 | grep -qiE \
     '^(hier ist|here is|sure,|of course,|i.ll generate|let me write|below is|voici)'; then
    echo "preamble"; return
  fi

  # Verbotene Tokens
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    if printf '%s' "$content" | grep -Fq -- "$tok"; then
      echo "forbidden_token"; return
    fi
  done < <(jq -r '.codeExtraction.forbiddenTokens[]' "$CFG")

  # Klammer-Balance
  local opens closes
  opens=$(printf '%s' "$content" | tr -cd '{' | wc -c)
  closes=$(printf '%s' "$content" | tr -cd '}' | wc -c)
  if [ "$opens" != "$closes" ]; then
    echo "unbalanced_syntax"; return
  fi

  echo "accepted"
}

suite "2. Fixture-Auswertung (4 reject, 1 accept)"
declare -A EXPECTED=(
  [fence-wrapped.cs.txt]="markdown_fence"
  [with-preamble.cs.txt]="preamble"
  [unbalanced.cs.txt]="unbalanced_syntax"
  [forbidden-token.cs.txt]="forbidden_token"
  [clean.cs.txt]="accepted"
)

reject_count=0
accept_count=0
for fixture in fence-wrapped.cs.txt with-preamble.cs.txt unbalanced.cs.txt \
               forbidden-token.cs.txt clean.cs.txt; do
  exp="${EXPECTED[$fixture]}"
  got=$(extract_check "$FIX_DIR/$fixture")
  if [ "$got" = "$exp" ]; then
    _log_pass "Fixture $fixture → $got (erwartet $exp)"
  else
    _log_fail "Fixture $fixture → $exp" "erhalten: $got"
  fi
  if [ "$got" = "accepted" ]; then
    accept_count=$((accept_count + 1))
  else
    reject_count=$((reject_count + 1))
  fi
done
assert_equals "$reject_count" "4" "Genau 4 Fixtures rejected"
assert_equals "$accept_count" "1" "Genau 1 Fixture accepted"

# ── 3. Accept-Policy / Rejection-Reasons in copilot-bridge.md ────
suite "3. Accept-Policy in copilot-bridge.md"
BRIDGE_MD="$SKILL_DIR/pipeline/copilot-bridge.md"
for needle in "extraction_failed" "timeout" "unchanged" "forbidden_token" \
              "unbalanced_syntax" "Accept-Policy" "Rejection-Handling"; do
  if grep -q "$needle" "$BRIDGE_MD"; then
    _log_pass "copilot-bridge.md beschreibt: $needle"
  else
    _log_fail "copilot-bridge.md beschreibt: $needle" "fehlt"
  fi
done

print_summary
