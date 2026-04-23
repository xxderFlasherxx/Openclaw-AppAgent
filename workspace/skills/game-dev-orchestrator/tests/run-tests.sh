#!/bin/bash
# ==============================================================================
# GameDev-Orchestrator Testframework – Haupt-Runner (Teil F, Schritt 20)
# ==============================================================================
# Führt alle automatischen Tests des Skills aus:
#   - Strukturtests (Dateien/Ordner vorhanden)
#   - JSON-Validität (Mocks, Templates, Config)
#   - Config-Schema
#   - Dry-Run-Szenarien (Happy Path, Single Error, Multiple Errors, Max Retries)
#
# Flags:
#   --online    zusätzlich echte Ollama-Cloud-Erreichbarkeit prüfen (opt-in)
#
# Exit-Code: 0 bei Erfolg, 1 bei Fehlschlägen.
# ==============================================================================

set -u

ONLINE=0
for arg in "$@"; do
  case "$arg" in
    --online) ONLINE=1 ;;
    *) echo "Unbekannte Option: $arg" >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

TMP_ROOT="$(mktemp -d -t gamedev-tests-XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

printf "${BOLD}════════════════════════════════════════════════════${NC}\n"
printf "${BOLD} GameDev-Orchestrator Tests (Teil F – Schritt 20)${NC}\n"
printf "${BOLD}════════════════════════════════════════════════════${NC}\n"
printf "Skill-Root: %s\n" "$SKILL_DIR"
printf "Temp-Root:  %s\n" "$TMP_ROOT"

# =============================================================================
suite "1. Skill-Grundstruktur"
# =============================================================================
assert_file_exists "$SKILL_DIR/SKILL.md"                                  "SKILL.md vorhanden"
assert_file_exists "$SKILL_DIR/gamedev-config.json"                       "gamedev-config.json vorhanden"
assert_dir_exists  "$SKILL_DIR/pipeline"                                  "pipeline/ vorhanden"
assert_dir_exists  "$SKILL_DIR/prompts"                                   "prompts/ vorhanden"
assert_dir_exists  "$SKILL_DIR/references"                                "references/ vorhanden"
assert_dir_exists  "$SKILL_DIR/templates"                                 "templates/ vorhanden"
assert_dir_exists  "$SKILL_DIR/test-data"                                 "test-data/ vorhanden"
assert_dir_exists  "$SKILL_DIR/tests"                                     "tests/ vorhanden"

# =============================================================================
suite "2. Pipeline-Dokumente (Teil D)"
# =============================================================================
for md in master-orchestrator planning-phase execution-loop error-correction context-management; do
  assert_file_exists "$SKILL_DIR/pipeline/${md}.md" "pipeline/${md}.md"
done

# =============================================================================
suite "3. Prompts & Genre-Kontexte"
# =============================================================================
for p in architect-system copilot-system-prompt error-analysis phase-transition; do
  assert_file_exists "$SKILL_DIR/prompts/${p}.txt" "prompts/${p}.txt"
done
assert_dir_exists "$SKILL_DIR/prompts/game-genres" "prompts/game-genres/"

# =============================================================================
suite "4. Templates (Teil E)"
# =============================================================================
for tpl in Singleton.cs.txt SceneLoader.cs.txt InputManager.cs.txt AudioManager.cs.txt \
           SharedInventory.cs.txt AutoCompileWatcher.cs.txt \
           base-game-manager.cs.txt base-player-controller.cs.txt \
           unity-gitignore.txt unity-editorconfig.txt \
           orchestrator-state.json current-phase.json phase-history.json \
           error-log.json master-plan.json learnings.json \
           copilot-prompts.json unity-status.json; do
  assert_file_exists "$SKILL_DIR/templates/$tpl" "templates/$tpl"
done
assert_dir_exists "$SKILL_DIR/templates/editor"  "templates/editor/"
assert_dir_exists "$SKILL_DIR/templates/genres"  "templates/genres/"

for g in driving platformer rpg sandbox; do
  assert_dir_exists "$SKILL_DIR/templates/genres/$g" "templates/genres/$g/"
done

# =============================================================================
suite "5. JSON-Validität (alle Config/Template/Mock JSONs)"
# =============================================================================
while IFS= read -r -d '' jsonfile; do
  rel="${jsonfile#$SKILL_DIR/}"
  assert_json_valid "$jsonfile" "JSON valide: $rel"
done < <(find "$SKILL_DIR" -type f -name "*.json" -not -path "*/tests/fixtures/*" -print0)

# =============================================================================
suite "6. gamedev-config.json Schema"
# =============================================================================
CFG="$SKILL_DIR/gamedev-config.json"
assert_jq_nonempty "$CFG" '.paths.projectsRoot'            "paths.projectsRoot gesetzt"
assert_jq_nonempty "$CFG" '.paths.vscode'                  "paths.vscode gesetzt"
assert_jq_nonempty "$CFG" '.unity.version'                 "unity.version gesetzt"
assert_jq_nonempty "$CFG" '.unity.buildTarget'             "unity.buildTarget gesetzt"
assert_jq_nonempty "$CFG" '.models.coderDefault'           "models.coderDefault gesetzt"
assert_jq_nonempty "$CFG" '.ollamaCloud.baseUrl'           "ollamaCloud.baseUrl gesetzt"
assert_jq_nonempty "$CFG" '.ollamaCloud.model'             "ollamaCloud.model gesetzt"
assert_jq_nonempty "$CFG" '.phases.maxPhases'              "phases.maxPhases gesetzt"
assert_jq_nonempty "$CFG" '.phases.maxRetriesPerPhase'     "phases.maxRetriesPerPhase gesetzt"
assert_jq          "$CFG" 'has("dryRun")'      "true"      "dryRun-Feld vorhanden"

# =============================================================================
suite "7. Mock-Master-Plan (test-data/mock-master-plan.json)"
# =============================================================================
MP="$SKILL_DIR/test-data/mock-master-plan.json"
assert_jq_nonempty "$MP" '.gameName'               "mock-master-plan.gameName"
assert_jq_nonempty "$MP" '.totalPhases'            "mock-master-plan.totalPhases"
assert_jq_nonempty "$MP" '.phases'                 "mock-master-plan.phases"
# totalPhases == length(phases)
tp=$(jq -r '.totalPhases'   "$MP")
pl=$(jq -r '.phases | length' "$MP")
assert_equals "$tp" "$pl" "totalPhases==length(phases) ($tp == $pl)"

# Alle Phasen haben Pflichtfelder
missing=$(jq -r '[.phases[] | select((.id==null) or (.name==null) or (.copilotPrompt==null) or (.expectedFiles==null) or (.validationCriteria==null))] | length' "$MP")
assert_equals "$missing" "0" "Alle Mock-Phasen haben Pflichtfelder"

# =============================================================================
suite "8. Mock Unity-Status Sequenzen"
# =============================================================================
US="$SKILL_DIR/test-data/mock-unity-status.json"
for seq in sequence_happy_path sequence_single_error sequence_multiple_errors sequence_max_retries; do
  assert_jq_nonempty "$US" ".${seq}" "Sequenz vorhanden: $seq"
done
# Jeder Status in den Sequenzen muss ein definiertes Scenario sein
undef=$(jq -r '[.sequence_happy_path[], .sequence_single_error[], .sequence_multiple_errors[], .sequence_max_retries[]]
               | unique | map(select(. as $k | $k | in(input.scenarios) | not))' "$US" "$US" 2>/dev/null | head -1)
# Einfachere Variante: prüfe jede Sequenz einzeln
for seq in sequence_happy_path sequence_single_error sequence_multiple_errors sequence_max_retries; do
  unk=$(jq -r --arg k "$seq" '[.[$k][] | select(. as $s | ($s | in(.scenarios)) | not)] | length' "$US" 2>/dev/null || echo "?")
  # jq oben nutzt falschen Kontext, daher alternativ:
  unk=$(jq -r --arg k "$seq" '.scenarios as $sc | [.[$k][] | select(. as $s | ($sc | has($s)) | not)] | length' "$US")
  assert_equals "$unk" "0" "Alle Statusnamen in $seq sind definiert"
done

# =============================================================================
suite "9. Mock-Günther-Antworten sind valides JSON-in-JSON"
# =============================================================================
GR="$SKILL_DIR/test-data/mock-guenther-responses.json"
# Jeder scenario.response.choices[0].message.content muss selbst gültiges JSON sein
for scen in plan_request_success error_analysis_success genre_detection_success; do
  inner=$(jq -r ".scenarios.${scen}.response.choices[0].message.content" "$GR")
  if echo "$inner" | jq empty >/dev/null 2>&1; then
    _log_pass "Innerer JSON-Content gültig: $scen"
  else
    _log_fail "Innerer JSON-Content gültig: $scen" "content ist kein JSON"
  fi
done

# =============================================================================
suite "10. Dry-Run: Happy Path (alle Phasen ok)"
# =============================================================================
HP_DIR="$TMP_ROOT/hp"
if "$SCRIPT_DIR/simulate-dry-run.sh" happy_path "$HP_DIR" > "$TMP_ROOT/hp.log" 2>&1; then
  _log_pass "Simulator läuft durch (exit 0)"
else
  _log_fail "Simulator läuft durch (exit 0)" "Siehe $TMP_ROOT/hp.log"
fi
assert_file_exists "$HP_DIR/.plan/master-plan.json"      "master-plan.json im Projekt"
assert_file_exists "$HP_DIR/.plan/phase-history.json"    "phase-history.json angelegt"
assert_file_exists "$HP_DIR/.plan/dry-run-summary.json"  "dry-run-summary.json angelegt"
assert_dir_exists  "$HP_DIR/Assets/Scripts/Core"         "Assets/Scripts/Core angelegt"
assert_jq "$HP_DIR/.plan/dry-run-summary.json" '.status' "success" "Happy-Path Status = success"
# Alle 3 Phasen abgeschlossen
completed=$(jq -r '[.phases[]? | select(.status=="completed")] | length' "$HP_DIR/.plan/phase-history.json")
assert_equals "$completed" "3" "3 Phasen completed"
# Erwartete Dateien existieren
for ef in Assets/Scripts/Core/GameManager.cs Assets/Scripts/Player/CubeController.cs \
          Assets/Scripts/Core/ScoreManager.cs; do
  assert_file_exists "$HP_DIR/$ef" "Erwartete Datei: $ef"
done

# =============================================================================
suite "11. Dry-Run: Single Error (1 Retry)"
# =============================================================================
SE_DIR="$TMP_ROOT/se"
"$SCRIPT_DIR/simulate-dry-run.sh" single_error "$SE_DIR" > "$TMP_ROOT/se.log" 2>&1
se_rc=$?
assert_equals "$se_rc" "0" "Exit-Code 0 (Fehler wird behoben)"
err_count=$(jq -r '(.errors // []) | length' "$SE_DIR/.plan/error-log.json")
assert_equals "$err_count" "1" "error-log enthält 1 Fehler"
total_err=$(jq -r '.totalErrors' "$SE_DIR/.plan/dry-run-summary.json")
assert_equals "$total_err" "1" "dry-run-summary.totalErrors == 1"
se_status=$(jq -r '.status' "$SE_DIR/.plan/dry-run-summary.json")
assert_equals "$se_status" "success" "Gesamtstatus nach Retry = success"

# =============================================================================
suite "12. Dry-Run: Multiple Errors (3 Retries)"
# =============================================================================
ME_DIR="$TMP_ROOT/me"
"$SCRIPT_DIR/simulate-dry-run.sh" multiple_errors "$ME_DIR" > "$TMP_ROOT/me.log" 2>&1
me_rc=$?
assert_equals "$me_rc" "0" "Exit-Code 0 (alle Fehler behoben)"
me_err=$(jq -r '(.errors // []) | length' "$ME_DIR/.plan/error-log.json")
assert_equals "$me_err" "3" "error-log enthält 3 Fehler"
me_status=$(jq -r '.status' "$ME_DIR/.plan/dry-run-summary.json")
assert_equals "$me_status" "success" "Gesamtstatus nach 3 Retries = success"

# =============================================================================
suite "13. Dry-Run: Max Retries (Eskalation)"
# =============================================================================
MR_DIR="$TMP_ROOT/mr"
"$SCRIPT_DIR/simulate-dry-run.sh" max_retries "$MR_DIR" > "$TMP_ROOT/mr.log" 2>&1
mr_rc=$?
assert_equals "$mr_rc" "1" "Exit-Code 1 (Eskalation)"
mr_status=$(jq -r '.status' "$MR_DIR/.plan/dry-run-summary.json")
assert_equals "$mr_status" "escalated" "Gesamtstatus = escalated"
escalated=$(jq -r '[.phases[]? | select(.status=="escalated")] | length' "$MR_DIR/.plan/phase-history.json")
assert_equals "$escalated" "1" "Genau 1 eskalierte Phase in History"

# =============================================================================
suite "14. Referenz-Skripte (Teil B)"
# =============================================================================
assert_file_exists "$SKILL_DIR/references/check-prerequisites.sh"       "check-prerequisites.sh"
assert_file_exists "$SKILL_DIR/references/setup-gamedev-environment.sh" "setup-gamedev-environment.sh"
# Bash-Syntax-Check (ohne Ausführung)
for sh in "$SKILL_DIR/references/check-prerequisites.sh" \
          "$SKILL_DIR/references/setup-gamedev-environment.sh" \
          "$SCRIPT_DIR/simulate-dry-run.sh" \
          "$SCRIPT_DIR/run-tests.sh"; do
  if bash -n "$sh" 2>/dev/null; then
    _log_pass "Bash-Syntax OK: ${sh##$SKILL_DIR/}"
  else
    _log_fail "Bash-Syntax OK: ${sh##$SKILL_DIR/}" "Syntaxfehler"
  fi
done

# =============================================================================
suite "15. Workspace-Integration (Teil B, Schritt 2)"
# =============================================================================
WS="/home/vboxuser/.openclaw/workspace"
OC_CFG="/home/vboxuser/.openclaw/openclaw.json"
for f in AGENTS.md SOUL.md USER.md TOOLS.md IDENTITY.md; do
  assert_file_exists "$WS/$f" "Workspace/$f vorhanden"
done
assert_file_exists "$WS/memory/gamedev-state.json" "memory/gamedev-state.json (Schritt 2.4)"
assert_json_valid  "$WS/memory/gamedev-state.json" "gamedev-state.json valide JSON"
assert_jq_nonempty "$WS/memory/gamedev-state.json" '.' "gamedev-state.json nicht leer"

# openclaw.json Tool-Berechtigungen (Schritt 2.1)
if [ -f "$OC_CFG" ]; then
  _log_pass "openclaw.json vorhanden"
  for tool in exec read write edit apply_patch web_fetch message cron; do
    present=$(jq --arg t "$tool" '[.agents.list[0].tools.alsoAllow[]? | select(.==$t)] | length' "$OC_CFG")
    if [ "$present" -gt 0 ]; then
      _log_pass "openclaw.json tools.alsoAllow enthält '$tool'"
    else
      _log_fail "openclaw.json tools.alsoAllow enthält '$tool'" "'$tool' fehlt in alsoAllow"
    fi
  done
else
  _log_fail "openclaw.json vorhanden" "Datei fehlt"
fi

# =============================================================================
suite "16. Teil C – Prompts & Genre-Kontexte (Schritt 3 & 5)"
# =============================================================================
for p in architect-system error-analysis phase-transition copilot-system-prompt; do
  pfile="$SKILL_DIR/prompts/${p}.txt"
  assert_file_exists "$pfile" "prompts/${p}.txt"
  if [ -f "$pfile" ] && [ -s "$pfile" ]; then
    _log_pass "prompts/${p}.txt nicht leer"
  else
    _log_fail "prompts/${p}.txt nicht leer" "Datei leer oder fehlt"
  fi
done
for g in driving-game platformer rpg sandbox; do
  assert_file_exists "$SKILL_DIR/prompts/game-genres/${g}.txt" "game-genres/${g}.txt"
done

# =============================================================================
suite "17. Teil C – Referenz-Dokumente (Schritt 4)"
# =============================================================================
for r in ollama-api vscode-cli copilot-modes ui-automation approach-decision \
         unity-project-structure csharp-patterns common-unity-errors; do
  assert_file_exists "$SKILL_DIR/references/${r}.txt" "references/${r}.txt"
done

# =============================================================================
suite "18. Teil E – Schritt 17 (Basis + Genre-Templates)"
# =============================================================================
# Basis
for tpl in Singleton SceneLoader InputManager AudioManager SharedInventory; do
  assert_file_exists "$SKILL_DIR/templates/${tpl}.cs.txt" "templates/${tpl}.cs.txt"
done
# Genre-Sets
for f in VehicleController SpeedometerUI FuelSystem; do
  assert_file_exists "$SKILL_DIR/templates/genres/driving/${f}.cs.txt" "driving/${f}.cs.txt"
done
for f in PlatformerController GroundCheck CoinCollector; do
  assert_file_exists "$SKILL_DIR/templates/genres/platformer/${f}.cs.txt" "platformer/${f}.cs.txt"
done
for f in RPGCharacterController DialogueSystem; do
  assert_file_exists "$SKILL_DIR/templates/genres/rpg/${f}.cs.txt" "rpg/${f}.cs.txt"
done
for f in FPSController BlockPlacer CraftingSystem; do
  assert_file_exists "$SKILL_DIR/templates/genres/sandbox/${f}.cs.txt" "sandbox/${f}.cs.txt"
done

# =============================================================================
suite "19. Teil E – Schritt 18 (Editor-Scripts)"
# =============================================================================
for f in AutoBuilder SceneBootstrapper AutoComponentAssigner; do
  assert_file_exists "$SKILL_DIR/templates/editor/${f}.cs.txt" "editor/${f}.cs.txt"
done
assert_file_exists "$SKILL_DIR/templates/AutoCompileWatcher.cs.txt" "AutoCompileWatcher.cs.txt (Schritt 9)"

# =============================================================================
suite "20. Teil E – Schritt 19 (Unity Build-Pipeline)"
# =============================================================================
assert_file_exists "$SKILL_DIR/references/unity-cli-commands.txt" "references/unity-cli-commands.txt"
assert_file_exists "$SKILL_DIR/references/build-workflow.txt"     "references/build-workflow.txt"
# Inhaltliche Stichproben
grep -q "executeMethod" "$SKILL_DIR/references/unity-cli-commands.txt" \
  && _log_pass "unity-cli-commands.txt dokumentiert '-executeMethod'" \
  || _log_fail "unity-cli-commands.txt dokumentiert '-executeMethod'" "fehlt"
grep -q "batchmode" "$SKILL_DIR/references/unity-cli-commands.txt" \
  && _log_pass "unity-cli-commands.txt dokumentiert '-batchmode'" \
  || _log_fail "unity-cli-commands.txt dokumentiert '-batchmode'" "fehlt"
grep -q "AutoBuilder.Build" "$SKILL_DIR/templates/editor/AutoBuilder.cs.txt" \
  && _log_pass "AutoBuilder.cs Template enthält Build-Methode" \
  || _log_fail "AutoBuilder.cs Template enthält Build-Methode" "fehlt"

# =============================================================================
suite "21. 10-Phasen-Mock-Plan (Skalierungs-Test, Schwachstelle #3)"
# =============================================================================
MP10="$SKILL_DIR/test-data/mock-master-plan-10phases.json"
assert_file_exists "$MP10"                                         "10-Phasen-Mock vorhanden"
assert_json_valid  "$MP10"                                         "10-Phasen-Mock valide JSON"
assert_jq          "$MP10" '.totalPhases'         "10"             "totalPhases == 10"
assert_jq          "$MP10" '.phases | length'     "10"             "phases hat 10 Elemente"
# Plan 1 muss mit Struktur/Setup starten, Plan 10 mit Build/Final
assert_jq_nonempty "$MP10" '.phases[0].name | test("Struktur|Setup|Basis"; "i") | tostring | select(.=="true")' \
                   "Phase 1 ist Projektstruktur/Setup/Basis"
assert_jq_nonempty "$MP10" '.phases[9].name | test("Build|Final"; "i") | tostring | select(.=="true")' \
                   "Phase 10 ist Build/Final"
# Keine doppelten IDs
dup=$(jq -r '[.phases[].id] | (length - (unique | length))' "$MP10")
assert_equals "$dup" "0" "Keine doppelten phase.id"

# Simulator kann den großen Plan fahren
HP10_DIR="$TMP_ROOT/hp10"
MOCK_PLAN="$MP10" "$SCRIPT_DIR/simulate-dry-run.sh" happy_path "$HP10_DIR" > "$TMP_ROOT/hp10.log" 2>&1
hp10_rc=$?
assert_equals "$hp10_rc" "0" "Simulator bewältigt 10-Phasen-Plan"
completed10=$(jq -r '[.phases[]? | select(.status=="completed")] | length' "$HP10_DIR/.plan/phase-history.json")
assert_equals "$completed10" "10" "Alle 10 Phasen completed"

# =============================================================================
suite "22. Unity-Status Schema-Contract (Schwachstelle #6)"
# =============================================================================
SCHEMA="$SCRIPT_DIR/fixtures/unity-status.schema.json"
assert_file_exists "$SCHEMA" "unity-status.schema.json vorhanden"
assert_json_valid  "$SCHEMA" "Schema-Datei ist valide JSON"

# Jedes Mock-Status-Scenario erfüllt das Schema (manuell, ohne externes jsonschema-Tool):
# required: status, message, timestamp; status-enum
valid_status='idle compiling success error runtime-error failed'
while IFS= read -r scen_key; do
  scen=$(jq --arg k "$scen_key" '.scenarios[$k]' "$SKILL_DIR/test-data/mock-unity-status.json")
  has_status=$(jq -r '.status // empty' <<<"$scen")
  has_message=$(jq -r '.message // empty' <<<"$scen")
  has_ts=$(jq -r '.timestamp // empty' <<<"$scen")
  if [ -n "$has_status" ] && [ -n "$has_message" ] && [ -n "$has_ts" ] \
     && [[ " $valid_status " == *" $has_status "* ]]; then
    _log_pass "Scenario erfüllt Schema: $scen_key"
  else
    _log_fail "Scenario erfüllt Schema: $scen_key" "status=$has_status, msg leer=$( [ -z "$has_message" ]&&echo ja||echo nein)"
  fi
done < <(jq -r '.scenarios | keys[]' "$SKILL_DIR/test-data/mock-unity-status.json")

# AutoCompileWatcher.cs schreibt korrekte Felder
WATCHER="$SKILL_DIR/templates/AutoCompileWatcher.cs.txt"
for field in status message timestamp; do
  # Das Template nutzt C#-escapten JSON-Output: \"status\":\"...
  if grep -Fq "\\\"${field}\\\":" "$WATCHER"; then
    _log_pass "AutoCompileWatcher emittiert Feld \"$field\""
  else
    _log_fail "AutoCompileWatcher emittiert Feld \"$field\"" "fehlt"
  fi
done
# Atomic-Write Fix (Schwachstelle #12)
if grep -q "File.Replace\|\.tmp" "$WATCHER"; then
  _log_pass "AutoCompileWatcher nutzt atomares Schreiben (.tmp + Replace)"
else
  _log_fail "AutoCompileWatcher nutzt atomares Schreiben" "kein .tmp/File.Replace gefunden"
fi

# =============================================================================
suite "23. Template-Content Smoke-Tests (Schwachstelle #10)"
# =============================================================================
# Stellt sicher, dass Templates nicht versehentlich geleert wurden und
# Schlüssel-Symbole enthalten.
declare -A CONTENT_CHECKS=(
  ["templates/Singleton.cs.txt"]="class Singleton"
  ["templates/SceneLoader.cs.txt"]="LoadSceneAsync|SceneManager"
  ["templates/InputManager.cs.txt"]="Input\\."
  ["templates/AudioManager.cs.txt"]="AudioSource|PlaySFX|PlayMusic|musicSource|sfxSource"
  ["templates/SharedInventory.cs.txt"]="InventorySlot|ItemData|InventorySystem"
  ["templates/base-game-manager.cs.txt"]="public static GameManager Instance"
  ["templates/editor/AutoBuilder.cs.txt"]="BuildPipeline.BuildPlayer"
  ["templates/editor/SceneBootstrapper.cs.txt"]="EventSystem|GameManager"
  ["templates/AutoCompileWatcher.cs.txt"]="CompilationPipeline"
)
for path in "${!CONTENT_CHECKS[@]}"; do
  needle="${CONTENT_CHECKS[$path]}"
  if [ ! -f "$SKILL_DIR/$path" ]; then
    _log_fail "Content-Check $path" "Datei fehlt"
  elif grep -Eq "$needle" "$SKILL_DIR/$path"; then
    _log_pass "Content-Check $path enthält Muster"
  else
    _log_fail "Content-Check $path" "Muster '$needle' nicht gefunden"
  fi
done

# =============================================================================
suite "24. Deprecated-Kennzeichnung (Schwachstelle #9)"
# =============================================================================
DEP="$SKILL_DIR/templates/genres/rpg/InventorySystem.cs.txt"
assert_file_exists "$DEP" "Deprecated-Template existiert noch"
if grep -qi "DEPRECATED" "$DEP"; then
  _log_pass "InventorySystem.cs.txt ist als DEPRECATED gekennzeichnet"
else
  _log_fail "InventorySystem.cs.txt ist als DEPRECATED gekennzeichnet" \
            "kein 'DEPRECATED'-Hinweis im Header gefunden"
fi
# SKILL.md warnt vor Doppel-Deployment
if grep -q "InventorySystem.cs.txt.*NICHT\|DEPRECATED" "$SKILL_DIR/SKILL.md"; then
  _log_pass "SKILL.md dokumentiert Deprecation"
else
  _log_fail "SKILL.md dokumentiert Deprecation" "fehlt"
fi

# =============================================================================
suite "25. dryRun-Sanity-Check (Schwachstelle #11)"
# =============================================================================
DR=$(jq -r '.dryRun' "$SKILL_DIR/gamedev-config.json")
case "$DR" in
  false)
    _log_pass "gamedev-config.json: dryRun=false (Produktionsmodus)"
    ;;
  true)
    # Nicht fehlschlagen – das kann bewusst sein. Aber Warnung ausgeben.
    printf "  ${YELLOW}⚠${NC} gamedev-config.json: dryRun=true ${YELLOW}(Simulationsmodus aktiv!)${NC}\n"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    ;;
  *)
    _log_fail "gamedev-config.json: dryRun-Wert" "ungültiger Wert: $DR"
    ;;
esac

# =============================================================================
suite "26. VS-Code-/Copilot-Umgebung (Schwachstelle #8, nicht-blockierend)"
# =============================================================================
if command -v code >/dev/null 2>&1; then
  _log_pass "VS Code im PATH ($(code --version 2>/dev/null | head -1))"
else
  _log_skip "VS Code im PATH" "code-CLI nicht gefunden"
fi
if command -v code >/dev/null 2>&1; then
  EXTS=$(code --list-extensions 2>/dev/null || true)
  for ext in github.copilot github.copilot-chat ms-dotnettools.csdevkit visualstudiotoolsforunity.vstuc; do
    if echo "$EXTS" | grep -qx "$ext"; then
      _log_pass "VS-Code-Extension installiert: $ext"
    else
      _log_skip "VS-Code-Extension installiert: $ext" "fehlt (setup-gamedev-environment.sh installiert sie)"
    fi
  done
else
  _log_skip "VS-Code-Extension Prüfung" "code-CLI fehlt"
fi

# =============================================================================
suite "27. Genre-Detection (Schwachstelle #2)"
# =============================================================================
if [ -x "$SCRIPT_DIR/test-genre-detection.sh" ]; then
  if "$SCRIPT_DIR/test-genre-detection.sh" > "$TMP_ROOT/genre.log" 2>&1; then
    _log_pass "test-genre-detection.sh läuft fehlerfrei durch"
    # Die Sub-Tests werden vom Unter-Script ausgewertet, hier nur Exit-Code
  else
    _log_fail "test-genre-detection.sh läuft fehlerfrei durch" "Siehe $TMP_ROOT/genre.log"
  fi
else
  _log_fail "test-genre-detection.sh ausführbar" "Skript fehlt oder nicht executable"
fi

# =============================================================================
suite "28. Teil G – Schritt 22: Modell-Routing"
# =============================================================================
assert_file_exists "$SKILL_DIR/pipeline/model-routing.md"                 "pipeline/model-routing.md"
assert_file_exists "$SKILL_DIR/templates/model-usage.json"                "templates/model-usage.json"
assert_file_exists "$SCRIPT_DIR/fixtures/model-routing-cases.json"        "fixtures/model-routing-cases.json"
assert_file_exists "$SCRIPT_DIR/test-model-routing.sh"                    "test-model-routing.sh"
assert_json_valid  "$SKILL_DIR/templates/model-usage.json"                "model-usage.json valide JSON"
assert_json_valid  "$SCRIPT_DIR/fixtures/model-routing-cases.json"        "model-routing-cases.json valide JSON"
# Config-Schema
assert_jq          "$CFG" '.modelRouting.enabled'                 "true"  "modelRouting.enabled=true"
assert_jq_nonempty "$CFG" '.modelRouting.defaultModel'                    "modelRouting.defaultModel"
assert_jq_nonempty "$CFG" '.modelRouting.escalateAtRetry'                 "modelRouting.escalateAtRetry"
assert_jq_nonempty "$CFG" '.modelRouting.categoryMap.physics'             "categoryMap.physics"
assert_jq_nonempty "$CFG" '.modelRouting.keywords.opus'                   "keywords.opus"
assert_jq_nonempty "$CFG" '.modelRouting.pricing.haiku.inputPer1K'        "pricing.haiku.inputPer1K"
assert_jq_nonempty "$CFG" '.modelRouting.pricing.sonnet.outputPer1K'      "pricing.sonnet.outputPer1K"
assert_jq_nonempty "$CFG" '.modelRouting.pricing.opus.inputPer1K'         "pricing.opus.inputPer1K"
# Preis-Sanity: Haiku < Sonnet < Opus (Input-Preis)
h=$(jq -r '.modelRouting.pricing.haiku.inputPer1K'  "$CFG")
s=$(jq -r '.modelRouting.pricing.sonnet.inputPer1K' "$CFG")
o=$(jq -r '.modelRouting.pricing.opus.inputPer1K'   "$CFG")
if awk "BEGIN{exit !($h < $s && $s < $o)}"; then
  _log_pass "Pricing monoton (haiku<sonnet<opus): $h < $s < $o"
else
  _log_fail "Pricing monoton (haiku<sonnet<opus)" "h=$h s=$s o=$o"
fi
# model-usage.json Schema
MU="$SKILL_DIR/templates/model-usage.json"
for f in haiku sonnet opus; do
  assert_jq_nonempty "$MU" ".models.${f}"            "model-usage.models.$f vorhanden"
  assert_jq          "$MU" ".models.${f}.calls"  "0" "model-usage.$f.calls initial 0"
done
assert_jq          "$MU" '.totalCostUsd == 0' "true" "model-usage.totalCostUsd initial 0"
# Routing-Unit-Test ausführen
if [ -x "$SCRIPT_DIR/test-model-routing.sh" ]; then
  if "$SCRIPT_DIR/test-model-routing.sh" > "$TMP_ROOT/routing.log" 2>&1; then
    _log_pass "test-model-routing.sh läuft fehlerfrei durch"
  else
    _log_fail "test-model-routing.sh läuft fehlerfrei durch" "Siehe $TMP_ROOT/routing.log"
  fi
else
  _log_fail "test-model-routing.sh ausführbar" "Skript fehlt oder nicht executable"
fi

# =============================================================================
suite "29. Teil G – Schritt 23: Memory-System"
# =============================================================================
assert_file_exists "$SKILL_DIR/pipeline/memory-system.md"                       "pipeline/memory-system.md"
assert_file_exists "$SKILL_DIR/templates/gamedev-projects.json"                 "templates/gamedev-projects.json"
assert_file_exists "$SKILL_DIR/templates/gamedev-patterns.json"                 "templates/gamedev-patterns.json"
assert_json_valid  "$SKILL_DIR/templates/gamedev-projects.json"                 "gamedev-projects.json template valide"
assert_json_valid  "$SKILL_DIR/templates/gamedev-patterns.json"                 "gamedev-patterns.json template valide"

WSMEM="/home/vboxuser/.openclaw/workspace/memory"
assert_file_exists "$WSMEM/gamedev-projects.json"  "workspace/memory/gamedev-projects.json"
assert_file_exists "$WSMEM/gamedev-patterns.json"  "workspace/memory/gamedev-patterns.json"
assert_json_valid  "$WSMEM/gamedev-projects.json"  "gamedev-projects.json (workspace) valide"
assert_json_valid  "$WSMEM/gamedev-patterns.json"  "gamedev-patterns.json (workspace) valide"

# Projects-Schema
assert_jq_nonempty "$WSMEM/gamedev-projects.json" '.schemaVersion'           "projects.schemaVersion"
assert_jq          "$WSMEM/gamedev-projects.json" '.projects | type' 'array' "projects.projects Array"
assert_jq_nonempty "$WSMEM/gamedev-projects.json" '.aggregate'               "projects.aggregate"
assert_jq          "$WSMEM/gamedev-projects.json" '.aggregate.totalProjects' "0" "aggregate.totalProjects=0 initial"

# Patterns-Schema
assert_jq_nonempty "$WSMEM/gamedev-patterns.json" '.schemaVersion'           "patterns.schemaVersion"
assert_jq_nonempty "$WSMEM/gamedev-patterns.json" '.patterns'                "patterns.patterns vorhanden"
# Mindestens ein Pattern mit erwarteten Feldern
pat_count=$(jq -r '.patterns | length' "$WSMEM/gamedev-patterns.json")
if [ "$pat_count" -ge 1 ]; then
  _log_pass "Pattern-Library hat Seed-Patterns ($pat_count)"
else
  _log_fail "Pattern-Library hat Seed-Patterns" "0 Patterns"
fi
# Jedes Pattern hat Pflichtfelder
missing_pat=$(jq -r '[.patterns | to_entries[] | select((.value.category==null) or (.value.description==null) or (.value.prompt==null) or (.value.successRate==null) or (.value.timesUsed==null) or (.value.appliesToGenres==null))] | length' "$WSMEM/gamedev-patterns.json")
assert_equals "$missing_pat" "0" "Alle Patterns haben Pflichtfelder"

# Config-Schema Memory
assert_jq          "$CFG" '.memory.enabled' "true"                "memory.enabled=true"
assert_jq_nonempty "$CFG" '.memory.projectsFile'                  "memory.projectsFile"
assert_jq_nonempty "$CFG" '.memory.patternsFile'                  "memory.patternsFile"
assert_jq_nonempty "$CFG" '.memory.maxProjectsInMemory'           "memory.maxProjectsInMemory"

# =============================================================================
suite "30. Teil G – Schritt 24: User-Feedback"
# =============================================================================
assert_file_exists "$SKILL_DIR/pipeline/user-feedback.md"                    "pipeline/user-feedback.md"
assert_file_exists "$SKILL_DIR/templates/feedback-prompt-hints.json"         "templates/feedback-prompt-hints.json"
assert_json_valid  "$SKILL_DIR/templates/feedback-prompt-hints.json"         "feedback-prompt-hints.json valide"

# Hints-Schema: Erwartete Kategorien
HINTS="$SKILL_DIR/templates/feedback-prompt-hints.json"
for cat in bugs missing performance controls graphics code; do
  assert_jq_nonempty "$HINTS" ".hints.${cat}" "Hint-Kategorie '${cat}' vorhanden"
done
assert_jq_nonempty "$HINTS" '.maxHintsPerGenre'                              "maxHintsPerGenre gesetzt"

# Config-Schema Feedback
assert_jq          "$CFG" '.feedback.enabled'        "true"                  "feedback.enabled=true"
assert_jq_nonempty "$CFG" '.feedback.timeoutHours'                           "feedback.timeoutHours"
assert_jq_nonempty "$CFG" '.feedback.askDetailsBelowRating'                  "feedback.askDetailsBelowRating"
assert_jq_nonempty "$CFG" '.feedback.askDetailsAboveRating'                  "feedback.askDetailsAboveRating"

# SKILL.md erwähnt Teil G
for tag in "Teil G" "Modell-Routing" "Memory-System" "User-Feedback"; do
  if grep -q "$tag" "$SKILL_DIR/SKILL.md"; then
    _log_pass "SKILL.md enthält '$tag'"
  else
    _log_fail "SKILL.md enthält '$tag'" "Abschnitt fehlt"
  fi
done

# Bash-Syntax der neuen Test-Scripts
for sh in "$SCRIPT_DIR/test-model-routing.sh"; do
  if bash -n "$sh" 2>/dev/null; then
    _log_pass "Bash-Syntax OK: ${sh##$SKILL_DIR/}"
  else
    _log_fail "Bash-Syntax OK: ${sh##$SKILL_DIR/}" "Syntaxfehler"
  fi
done

# =============================================================================
suite "30b. Teil G – Integrations-Fixes (Cross-Linking)"
# =============================================================================
# execution-loop.md muss selectModel() und usedPatterns aus Teil G referenzieren
EXEC_LOOP="$SKILL_DIR/pipeline/execution-loop.md"
for needle in "selectModel(phase" "model-routing.md" "detectUsedPatterns" \
              "used-patterns.json" "logRoutingDecision"; do
  if grep -q "$needle" "$EXEC_LOOP"; then
    _log_pass "execution-loop.md referenziert '$needle'"
  else
    _log_fail "execution-loop.md referenziert '$needle'" "Cross-Link fehlt"
  fi
done

# master-orchestrator.md muss die neuen Teil-G-States enthalten
MO="$SKILL_DIR/pipeline/master-orchestrator.md"
for state in "ARCHIVING" "AWAITING_FEEDBACK" "DONE"; do
  if grep -q "$state" "$MO"; then
    _log_pass "master-orchestrator.md kennt Zustand '$state'"
  else
    _log_fail "master-orchestrator.md kennt Zustand '$state'" "State fehlt"
  fi
done
# State-Transition-Tabelle enthält die neuen Übergänge
for trans in "COMPLETE.*ARCHIVING" "ARCHIVING.*AWAITING_FEEDBACK" "AWAITING_FEEDBACK.*DONE"; do
  if grep -qE "$trans" "$MO"; then
    _log_pass "Transition-Tabelle: $trans"
  else
    _log_fail "Transition-Tabelle: $trans" "fehlt"
  fi
done

# Memory-Config muss absolute Pfade haben (beginnen mit '/')
for key in projectsFile patternsFile archiveFile lockFile; do
  val=$(jq -r ".memory.${key}" "$CFG")
  if [[ "$val" == /* ]]; then
    _log_pass "memory.${key} ist absoluter Pfad"
  else
    _log_fail "memory.${key} ist absoluter Pfad" "relativ: $val"
  fi
done

# schemaVersion in Memory-Config
assert_jq_nonempty "$CFG" '.memory.schemaVersion' "memory.schemaVersion gesetzt"

# used-patterns Template existiert
assert_file_exists "$SKILL_DIR/templates/used-patterns.json" "templates/used-patterns.json"
assert_json_valid  "$SKILL_DIR/templates/used-patterns.json" "used-patterns.json valide"

# Memory-Robustheit-Block in memory-system.md
MS="$SKILL_DIR/pipeline/memory-system.md"
for needle in "Lockfile" "schemaVersion" "Atomic Writes" "Size-Limit"; do
  if grep -qE "$needle" "$MS"; then
    _log_pass "memory-system.md dokumentiert: $needle"
  else
    _log_fail "memory-system.md dokumentiert: $needle" "fehlt"
  fi
done

# =============================================================================
# Opt-in: Online-Checks (nur mit --online)
# =============================================================================
if [ "$ONLINE" -eq 1 ]; then
  suite "31. Online-Check: Ollama Cloud (Schwachstelle #7)"
  BASE=$(jq -r '.ollamaCloud.baseUrl' "$SKILL_DIR/gamedev-config.json")
  # Host-Erreichbarkeit
  host=$(echo "$BASE" | sed -E 's#^https?://##;s#/.*$##')
  if command -v curl >/dev/null 2>&1; then
    http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BASE/models" 2>/dev/null || echo "000")
    # 200, 401, 403 bedeuten der Endpunkt antwortet; 000 = nicht erreichbar
    case "$http" in
      200|401|403|404|405)
        _log_pass "Ollama-Cloud erreichbar (HTTP $http, host=$host)"
        ;;
      *)
        _log_fail "Ollama-Cloud erreichbar" "HTTP $http für $BASE/models"
        ;;
    esac
  else
    _log_skip "Ollama-Cloud-Check" "curl nicht installiert"
  fi
fi

# =============================================================================
print_summary
