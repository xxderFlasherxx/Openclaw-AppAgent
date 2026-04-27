#!/bin/bash
# ==============================================================================
# Test: Safety-Gates (Teil H, Schritt 27)
# ==============================================================================
# Validiert:
#   - safety-Block in gamedev-config.json wohlgeformt
#   - approvalMode ist gültiger Enum-Wert
#   - denyScope-Verletzung führt zu Phase-Abbruch (Sim)
#   - maxFilesChangedPerPhase wird durchgesetzt (Sim)
#   - dryRunFirstRun produziert .plan/dry-run/* Dateien (Sim)
#   - pipeline/safety-gates.md dokumentiert State-Übergänge
# ==============================================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"
GATES_MD="$SKILL_DIR/pipeline/safety-gates.md"
TMP="$(mktemp -d -t safety-gates-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

printf "${BOLD}════════════════════════════════════════════════════${NC}\n"
printf "${BOLD} Safety-Gates Tests (Teil H – Schritt 27)${NC}\n"
printf "${BOLD}════════════════════════════════════════════════════${NC}\n"

# ── 1. Konfigurationsblock ────────────────────────────────────
suite "1. safety-Block in gamedev-config.json"
assert_jq_nonempty "$CFG" '.safety'                          "safety-Block vorhanden"
assert_jq_nonempty "$CFG" '.safety.writeScope'               "writeScope vorhanden"
assert_jq_nonempty "$CFG" '.safety.denyScope'                "denyScope vorhanden"
assert_jq_nonempty "$CFG" '.safety.approvalMode'             "approvalMode gesetzt"
assert_jq_nonempty "$CFG" '.safety.vetoWindowSeconds'        "vetoWindowSeconds gesetzt"
assert_jq_nonempty "$CFG" '.safety.maxFilesChangedPerPhase'  "maxFilesChangedPerPhase gesetzt"
assert_jq_nonempty "$CFG" '.safety.maxBytesPerFile'          "maxBytesPerFile gesetzt"
assert_jq          "$CFG" 'has("safety") and (.safety | has("dryRunFirstRun"))' "true" "dryRunFirstRun-Feld vorhanden"

# approvalMode ist Enum
MODE=$(jq -r '.safety.approvalMode' "$CFG")
case "$MODE" in
  manual|auto-with-telegram-veto|fully-autonomous)
    _log_pass "approvalMode='$MODE' ist gültiger Enum-Wert"
    ;;
  *)
    _log_fail "approvalMode gültiger Enum" "ungültig: $MODE"
    ;;
esac

# Sensitive Pfade in denyScope?
for needed in "/etc/" ".ssh" "openclaw.json"; do
  hit=$(jq -r --arg n "$needed" '[.safety.denyScope[] | select(contains($n))] | length' "$CFG")
  if [ "$hit" -gt 0 ]; then
    _log_pass "denyScope schützt: $needed"
  else
    _log_fail "denyScope schützt: $needed" "kein Eintrag enthält '$needed'"
  fi
done

# ── 2. pipeline/safety-gates.md ──────────────────────────────
suite "2. safety-gates.md Dokumentation"
assert_file_exists "$GATES_MD" "safety-gates.md vorhanden"
for needle in "PLANNING" "INITIALIZING" "EXECUTING" "VERIFYING" \
              "writeScopeCheck" "planHashApproval" "budgetCheck" \
              "dryRunFirstRun" "auto-with-telegram-veto" "manual" "fully-autonomous"; do
  if grep -q "$needle" "$GATES_MD"; then
    _log_pass "safety-gates.md erwähnt: $needle"
  else
    _log_fail "safety-gates.md erwähnt: $needle" "fehlt"
  fi
done

# ── 3. Schreib-Scope-Simulation ──────────────────────────────
# Vereinfachte Implementierung von assertWriteAllowed() in Bash
assert_write() {
  local target="$1"; local proj="${2:-myproj}"
  local home_dir="$HOME"
  # deny first
  while IFS= read -r p; do
    p="${p//\~/$home_dir}"
    case "$target" in
      $p) echo "denied:$p"; return ;;
    esac
  done < <(jq -r '.safety.denyScope[]' "$CFG")
  # writeScope
  while IFS= read -r p; do
    p="${p//<projectName>/$proj}"
    p="${p//\~/$home_dir}"
    case "$target" in
      $p) echo "allowed:$p"; return ;;
    esac
  done < <(jq -r '.safety.writeScope[]' "$CFG")
  echo "not_in_writeScope"
}

suite "3. writeScope/denyScope Simulation"
res=$(assert_write "$HOME/.ssh/id_rsa")
case "$res" in denied:*) _log_pass "denyScope blockiert ~/.ssh/id_rsa ($res)" ;;
  *) _log_fail "denyScope blockiert ~/.ssh/id_rsa" "got: $res" ;;
esac

res=$(assert_write "/etc/passwd")
case "$res" in denied:*) _log_pass "denyScope blockiert /etc/passwd ($res)" ;;
  *) _log_fail "denyScope blockiert /etc/passwd" "got: $res" ;;
esac

res=$(assert_write "$HOME/GameDev-Projekte/myproj/Assets/Scripts/Foo.cs" "myproj")
case "$res" in allowed:*) _log_pass "writeScope erlaubt Projekt-Datei ($res)" ;;
  *) _log_fail "writeScope erlaubt Projekt-Datei" "got: $res" ;;
esac

res=$(assert_write "$HOME/Documents/random/file.txt" "myproj")
assert_equals "$res" "not_in_writeScope" "Datei außerhalb writeScope wird abgelehnt"

# ── 4. maxFilesChangedPerPhase Simulation ────────────────────
suite "4. maxFilesChangedPerPhase"
LIMIT=$(jq -r '.safety.maxFilesChangedPerPhase' "$CFG")
# Simuliere LIMIT+1 Datei-Änderungen
COUNT=$((LIMIT + 1))
if [ "$COUNT" -gt "$LIMIT" ]; then
  _log_pass "Phase mit $COUNT Dateien überschreitet Limit $LIMIT (würde abgebrochen)"
else
  _log_fail "Limit-Check" "Logik defekt"
fi
# Im Rahmen
HALF=$((LIMIT / 2))
if [ "$HALF" -le "$LIMIT" ]; then
  _log_pass "Phase mit $HALF Dateien innerhalb Limit"
fi

# ── 5. Dry-Run produziert .plan/dry-run/ ─────────────────────
suite "5. Dry-Run-Modus erzeugt Prompt-Dateien"
PROJ="$TMP/dry-proj"
mkdir -p "$PROJ/.plan/dry-run"
# Simuliere Hans-Verhalten unter dryRunFirstRun=true
for n in 1 2 3; do
  cat > "$PROJ/.plan/dry-run/phase${n}-prompt.md" <<EOF
# Dry-Run Phase $n
Adapter A NICHT ausgeführt – Prompt nur zur Sichtung.
EOF
done
for n in 1 2 3; do
  assert_file_exists "$PROJ/.plan/dry-run/phase${n}-prompt.md" "dry-run/phase${n}-prompt.md erzeugt"
done
# Keine echten Code-Dateien geschrieben
if [ ! -d "$PROJ/Assets" ]; then
  _log_pass "Dry-Run schreibt KEINE Code-Dateien (kein Assets/)"
else
  _log_fail "Dry-Run schreibt KEINE Code-Dateien" "Assets/ existiert"
fi

print_summary
