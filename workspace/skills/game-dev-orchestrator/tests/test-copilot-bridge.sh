#!/bin/bash
# ==============================================================================
# Test: Copilot-Bridge (Teil H, Schritt 25)
# ==============================================================================
# Validiert:
#   - copilotBridge-Block in gamedev-config.json wohlgeformt
#   - Fallback-Kette referenziert nur gültige Adapter-Namen
#   - pipeline/copilot-bridge.md referenziert alle drei Adapter
#   - execution-loop.md ruft callCopilotBridge() auf
#   - tests/fixtures/copilot-bridge-cases.json hat ≥6 valide Cases
# ==============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"
BRIDGE_MD="$SKILL_DIR/pipeline/copilot-bridge.md"
EXEC_LOOP="$SKILL_DIR/pipeline/execution-loop.md"
FIX="$SKILL_DIR/tests/fixtures/copilot-bridge-cases.json"

printf "${BOLD}════════════════════════════════════════════════════${NC}\n"
printf "${BOLD} Copilot-Bridge Tests (Teil H – Schritt 25)${NC}\n"
printf "${BOLD}════════════════════════════════════════════════════${NC}\n"

suite "1. Konfigurationsblock copilotBridge"
assert_file_exists "$CFG" "gamedev-config.json existiert"
assert_jq_nonempty "$CFG" '.copilotBridge'                       "copilotBridge-Block vorhanden"
assert_jq_nonempty "$CFG" '.copilotBridge.preferredAdapter'      "preferredAdapter gesetzt"
assert_jq_nonempty "$CFG" '.copilotBridge.fallbackChain'         "fallbackChain vorhanden"
assert_jq          "$CFG" '.copilotBridge.fallbackChain | length' "3" "fallbackChain hat 3 Adapter"
assert_jq_nonempty "$CFG" '.copilotBridge.taskName'              "taskName gesetzt"
assert_jq_nonempty "$CFG" '.copilotBridge.timeoutSeconds'        "timeoutSeconds gesetzt"
assert_jq_nonempty "$CFG" '.copilotBridge.pollIntervalSeconds'   "pollIntervalSeconds gesetzt"
assert_jq_nonempty "$CFG" '.copilotBridge.uiAutomation.tool'     "uiAutomation.tool gesetzt"

suite "2. fallbackChain Adapter-Namen wohlgeformt"
VALID_ADAPTERS="file-injection gh-copilot-cli ui-automation"
while IFS= read -r adapter; do
  if [[ " $VALID_ADAPTERS " == *" $adapter "* ]]; then
    _log_pass "Adapter-Name gültig: $adapter"
  else
    _log_fail "Adapter-Name gültig: $adapter" "unbekannt: $adapter"
  fi
done < <(jq -r '.copilotBridge.fallbackChain[]' "$CFG")

# preferredAdapter muss in fallbackChain stehen
PREF=$(jq -r '.copilotBridge.preferredAdapter' "$CFG")
IN_CHAIN=$(jq -r --arg p "$PREF" '[.copilotBridge.fallbackChain[] | select(.==$p)] | length' "$CFG")
if [ "$IN_CHAIN" -gt 0 ]; then
  _log_pass "preferredAdapter '$PREF' ist Teil von fallbackChain"
else
  _log_fail "preferredAdapter in fallbackChain" "$PREF nicht in fallbackChain"
fi

suite "3. pipeline/copilot-bridge.md"
assert_file_exists "$BRIDGE_MD" "copilot-bridge.md existiert"
for adapter in "Adapter A" "Adapter B" "Adapter C" "file-injection" "gh-copilot-cli" "ui-automation"; do
  if grep -q "$adapter" "$BRIDGE_MD"; then
    _log_pass "copilot-bridge.md erwähnt: $adapter"
  else
    _log_fail "copilot-bridge.md erwähnt: $adapter" "fehlt"
  fi
done
for needle in "xdotool" "ydotool" "extractCleanCode" "Accept-Policy" "Rejection"; do
  if grep -qi "$needle" "$BRIDGE_MD"; then
    _log_pass "copilot-bridge.md dokumentiert: $needle"
  else
    _log_fail "copilot-bridge.md dokumentiert: $needle" "fehlt"
  fi
done

suite "4. execution-loop.md ruft callCopilotBridge() auf"
assert_file_exists "$EXEC_LOOP" "execution-loop.md existiert"
if grep -q "callCopilotBridge" "$EXEC_LOOP"; then
  _log_pass "execution-loop.md enthält callCopilotBridge()"
else
  _log_fail "execution-loop.md enthält callCopilotBridge()" "Aufruf fehlt"
fi
if grep -q "copilot-bridge.md" "$EXEC_LOOP"; then
  _log_pass "execution-loop.md verlinkt copilot-bridge.md"
else
  _log_fail "execution-loop.md verlinkt copilot-bridge.md" "Cross-Link fehlt"
fi

suite "5. Test-Fixtures"
assert_file_exists "$FIX" "copilot-bridge-cases.json existiert"
assert_json_valid  "$FIX" "Fixture-Datei valide JSON"
NUM=$(jq -r '.cases | length' "$FIX")
if [ "$NUM" -ge 6 ]; then
  _log_pass "Fixtures enthalten ≥6 Cases (gefunden: $NUM)"
else
  _log_fail "Fixtures enthalten ≥6 Cases" "nur $NUM Cases"
fi
# Pflichtfälle vorhanden?
for cid in A1_file_injection_ok A2_file_injection_timeout B_falls_back_to_gh_cli \
           C_falls_back_to_ui_automation D_unknown_adapter_name E_missing_workspace_path; do
  found=$(jq -r --arg id "$cid" '[.cases[] | select(.id==$id)] | length' "$FIX")
  if [ "$found" = "1" ]; then
    _log_pass "Pflicht-Case vorhanden: $cid"
  else
    _log_fail "Pflicht-Case vorhanden: $cid" "fehlt"
  fi
done
# Jeder Case hat input + expected
miss=$(jq -r '[.cases[] | select((.input==null) or (.expected==null))] | length' "$FIX")
assert_equals "$miss" "0" "Alle Cases haben input + expected"

print_summary
