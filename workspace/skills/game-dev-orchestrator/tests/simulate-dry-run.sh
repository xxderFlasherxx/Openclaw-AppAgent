#!/bin/bash
# ==============================================================================
# Dry-Run Simulator (Teil F, Schritt 20.1)
# ------------------------------------------------------------------------------
# Durchläuft den Master-Orchestrator-Workflow ohne echte API- oder
# Unity-Aufrufe. Nutzt Mock-Daten aus test-data/.
#
# Aufruf:
#   ./simulate-dry-run.sh <scenario> <project_dir>
#
# Scenarios:
#   happy_path        → alle Phasen erfolgreich
#   single_error      → Phase 2 hat einen Fehler, wird behoben
#   multiple_errors   → Phase 2 hat drei Fehler, wird behoben
#   max_retries       → alle 5 Versuche scheitern, User-Eskalation
#
# Umgebungsvariable:
#   MOCK_PLAN=<pfad>  → alternativen Mock-Master-Plan verwenden
#                      (default: test-data/mock-master-plan.json)
# ==============================================================================

set -u

SCENARIO="${1:-happy_path}"
PROJECT_DIR="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DATA="$SKILL_DIR/test-data"
TEMPLATES="$SKILL_DIR/templates"

MOCK_PLAN="${MOCK_PLAN:-$TEST_DATA/mock-master-plan.json}"

if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(mktemp -d -t gamedev-dryrun-XXXXXX)"
  echo "[sim] Kein Projektverzeichnis übergeben, nutze Temp: $PROJECT_DIR"
fi

mkdir -p "$PROJECT_DIR"

log()  { printf "[sim] %s\n" "$*"; }
warn() { printf "[sim] \033[33m%s\033[0m\n" "$*"; }
err()  { printf "[sim] \033[31m%s\033[0m\n" "$*" >&2; }

# -----------------------------------------------------------------------------
# 1. Validiere Voraussetzungen
# -----------------------------------------------------------------------------
for f in \
  "$MOCK_PLAN" \
  "$TEST_DATA/mock-unity-status.json" \
  "$TEST_DATA/mock-guenther-responses.json"
do
  if [ ! -f "$f" ]; then err "Mock-Datei fehlt: $f"; exit 2; fi
done

SEQUENCE_KEY=""
case "$SCENARIO" in
  happy_path)      SEQUENCE_KEY="sequence_happy_path" ;;
  single_error)    SEQUENCE_KEY="sequence_single_error" ;;
  multiple_errors) SEQUENCE_KEY="sequence_multiple_errors" ;;
  max_retries)     SEQUENCE_KEY="sequence_max_retries" ;;
  *)
    err "Unbekanntes Szenario: $SCENARIO"
    echo "Erlaubt: happy_path, single_error, multiple_errors, max_retries"
    exit 2
    ;;
esac

# -----------------------------------------------------------------------------
# 2. INITIALIZING: Projektstruktur anlegen (wie im echten Orchestrator)
# -----------------------------------------------------------------------------
log "Scenario: $SCENARIO"
log "Projektverzeichnis: $PROJECT_DIR"
log "INITIALIZING: Erstelle Projektstruktur…"

mkdir -p "$PROJECT_DIR"/Assets/{Scripts/Core,Scripts/Player,Scripts/Camera,Scripts/UI,Scripts/Managers,Editor,Scenes,Prefabs,Materials}
mkdir -p "$PROJECT_DIR"/{Builds,.plan,ProjectSettings,Packages}

# Initiale .plan/ Dateien (aus templates/ falls vorhanden, sonst leere Stubs)
for tpl in orchestrator-state.json current-phase.json phase-history.json \
           error-log.json copilot-prompts.json learnings.json unity-status.json; do
  if [ -f "$TEMPLATES/$tpl" ]; then
    cp "$TEMPLATES/$tpl" "$PROJECT_DIR/.plan/$tpl"
  else
    echo '{}' > "$PROJECT_DIR/.plan/$tpl"
  fi
done

# Master-Plan ist im Dry-Run der Mock
cp "$MOCK_PLAN" "$PROJECT_DIR/.plan/master-plan.json"

TOTAL_PHASES=$(jq -r '.totalPhases' "$PROJECT_DIR/.plan/master-plan.json")
log "Master-Plan geladen: $TOTAL_PHASES Phasen"

# -----------------------------------------------------------------------------
# 3. EXECUTING / VERIFYING / CORRECTING pro Phase
# -----------------------------------------------------------------------------

# Unity-Status-Sequenz als Array aufbereiten
mapfile -t UNITY_SEQ < <(jq -r ".${SEQUENCE_KEY}[]" "$TEST_DATA/mock-unity-status.json")
SEQ_IDX=0

MAX_RETRIES=5
OVERALL_STATUS="success"
FAILED_PHASE=""

# Hilfsfunktion: nächster Unity-Status aus Sequenz.
# Setzt NEXT_STATUS (kein Command-Substitution, weil sonst SEQ_IDX nicht persistiert wird).
next_unity_status() {
  NEXT_STATUS="success"
  if [ "$SEQ_IDX" -ge "${#UNITY_SEQ[@]}" ]; then return; fi
  local s="${UNITY_SEQ[$SEQ_IDX]}"
  SEQ_IDX=$((SEQ_IDX + 1))
  # "compiling" und "idle" überspringen (Übergangszustände in Simulation)
  while [ "$s" = "compiling" ] || [ "$s" = "idle" ]; do
    if [ "$SEQ_IDX" -ge "${#UNITY_SEQ[@]}" ]; then NEXT_STATUS="success"; return; fi
    s="${UNITY_SEQ[$SEQ_IDX]}"
    SEQ_IDX=$((SEQ_IDX + 1))
  done
  NEXT_STATUS="$s"
}

write_mock_code() {
  local target="$1" phase_id="$2" attempt="$3"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<EOF
// ============================================================
// MOCK CODE - Dry-Run Simulator
// Phase: $phase_id | Versuch: $attempt | Scenario: $SCENARIO
// Generiert: $(date -Iseconds)
// ============================================================
using UnityEngine;

public class MockPhase${phase_id}_Attempt${attempt} : MonoBehaviour
{
    void Start() { Debug.Log("Mock-Phase $phase_id ready"); }
}
EOF
}

append_error_log() {
  local phase_id="$1" attempt="$2" unity_status="$3" message="$4"
  local logfile="$PROJECT_DIR/.plan/error-log.json"
  local tmp
  tmp=$(mktemp)
  jq --argjson pid "$phase_id" --argjson a "$attempt" \
     --arg s "$unity_status" --arg m "$message" --arg ts "$(date -Iseconds)" \
     '. + {errors: ((.errors // []) + [{phaseId:$pid, attempt:$a, status:$s, message:$m, timestamp:$ts}])}' \
     "$logfile" > "$tmp" && mv "$tmp" "$logfile"
}

append_history() {
  local phase_id="$1" name="$2" status="$3" attempts="$4"
  local histfile="$PROJECT_DIR/.plan/phase-history.json"
  local tmp
  tmp=$(mktemp)
  jq --argjson pid "$phase_id" --arg n "$name" --arg s "$status" --argjson a "$attempts" --arg ts "$(date -Iseconds)" \
     '. + {phases: ((.phases // []) + [{id:$pid, name:$n, status:$s, attempts:$a, completedAt:$ts}])}' \
     "$histfile" > "$tmp" && mv "$tmp" "$histfile"
}

TOTAL_ATTEMPTS=0
TOTAL_ERRORS=0

for ((PHASE=1; PHASE<=TOTAL_PHASES; PHASE++)); do
  PHASE_NAME=$(jq -r ".phases[$((PHASE-1))].name"           "$PROJECT_DIR/.plan/master-plan.json")
  EXPECTED_FILE=$(jq -r ".phases[$((PHASE-1))].expectedFiles[0]" "$PROJECT_DIR/.plan/master-plan.json")
  log ""
  log "───── Phase $PHASE/$TOTAL_PHASES: $PHASE_NAME ─────"

  echo "{\"phaseId\":$PHASE,\"status\":\"in_progress\",\"attempt\":1,\"name\":\"$PHASE_NAME\"}" \
    > "$PROJECT_DIR/.plan/current-phase.json"

  attempt=1
  phase_done=false

  while [ "$attempt" -le "$MAX_RETRIES" ]; do
    TOTAL_ATTEMPTS=$((TOTAL_ATTEMPTS + 1))
    log "  EXECUTING (attempt $attempt): schreibe Mock-Code → $EXPECTED_FILE"
    write_mock_code "$PROJECT_DIR/$EXPECTED_FILE" "$PHASE" "$attempt"

    next_unity_status
    status="$NEXT_STATUS"
    log "  VERIFYING: Unity-Status = '$status'"

    case "$status" in
      success|build_success)
        log "  PHASE_DONE ✔"
        append_history "$PHASE" "$PHASE_NAME" "completed" "$attempt"
        phase_done=true
        break
        ;;
      error*|runtime-error|build_failed)
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        warn "  CORRECTING: Fehler erkannt ($status) → Günther-Analyse (mocked)"
        append_error_log "$PHASE" "$attempt" "$status" "Mock-Fehler ($status)"
        attempt=$((attempt + 1))
        ;;
      *)
        warn "  Unbekannter Status '$status' → treated as success"
        append_history "$PHASE" "$PHASE_NAME" "completed" "$attempt"
        phase_done=true
        break
        ;;
    esac
  done

  if [ "$phase_done" = false ]; then
    err "  MAX_RETRIES erreicht für Phase $PHASE → User-Eskalation (Incident Report)"
    append_history "$PHASE" "$PHASE_NAME" "escalated" "$MAX_RETRIES"
    OVERALL_STATUS="escalated"
    FAILED_PHASE="$PHASE"
    # Im echten Orchestrator würde der User nun gefragt. Simulation bricht hier ab.
    break
  fi
done

# -----------------------------------------------------------------------------
# 4. Zusammenfassung schreiben
# -----------------------------------------------------------------------------
SUMMARY="$PROJECT_DIR/.plan/dry-run-summary.json"
jq -n \
  --arg scenario "$SCENARIO" \
  --arg status "$OVERALL_STATUS" \
  --arg failedPhase "${FAILED_PHASE:-}" \
  --argjson phases "$TOTAL_PHASES" \
  --argjson attempts "$TOTAL_ATTEMPTS" \
  --argjson errors "$TOTAL_ERRORS" \
  --arg projectDir "$PROJECT_DIR" \
  --arg finishedAt "$(date -Iseconds)" \
  '{scenario:$scenario, status:$status, failedPhase:$failedPhase,
    totalPhases:$phases, totalAttempts:$attempts, totalErrors:$errors,
    projectDir:$projectDir, finishedAt:$finishedAt}' \
  > "$SUMMARY"

log ""
log "════════════════════════════════════════════════════════"
log "Dry-Run abgeschlossen: status=$OVERALL_STATUS"
log "  Phasen:  $TOTAL_PHASES"
log "  Versuche: $TOTAL_ATTEMPTS"
log "  Fehler:   $TOTAL_ERRORS"
log "  Summary:  $SUMMARY"
log "════════════════════════════════════════════════════════"

# Exit-Code: 0 wenn success/completed, 1 wenn escalated, 2 bei harten Fehlern
if [ "$OVERALL_STATUS" = "success" ]; then exit 0
elif [ "$OVERALL_STATUS" = "escalated" ]; then exit 1
else exit 2; fi
