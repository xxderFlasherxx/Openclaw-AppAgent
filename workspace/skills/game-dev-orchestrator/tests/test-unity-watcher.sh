#!/bin/bash
# ==============================================================================
# Test: Unity Watcher (Teil I, Schritt 28)
# ==============================================================================
# Prüft:
#   - templates/AutoCompileWatcher.cs.txt existiert und enthält die in
#     Schritt 28.1 geforderten Erweiterungen (jsonl, atomic, phaseId, project).
#   - tests/fixtures/error-log-entry.schema.json + Sample-Fixtures.
#   - pipeline/unity-watcher.md beschreibt beide Schemas.
#   - pipeline/project-init.md enthält Schritte h-k inkl. Watcher-Deployment.
# ==============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

suite "Unity-Watcher: Template AutoCompileWatcher.cs.txt"
WATCHER="$SKILL_DIR/templates/AutoCompileWatcher.cs.txt"
assert_file_exists "$WATCHER" "AutoCompileWatcher.cs.txt vorhanden"

# Pflichtinhalte aus Schritt 28.1
for needle in \
  "error-log.jsonl" \
  "FileMode.Append" \
  "File.Replace" \
  "current-phase.json" \
  "phaseId" \
  "compileCount" \
  "errorCount" \
  "CompilationPipeline" ; do
  if grep -Fq "$needle" "$WATCHER"; then
    _log_pass "AutoCompileWatcher enthält '$needle'"
  else
    _log_fail "AutoCompileWatcher enthält '$needle'" "fehlt"
  fi
done

# Append-Modus, kein Overwrite des error-logs (nur Init mit "" erlaubt)
overwrite_count=$(grep -c 'File.WriteAllText(errorLogFile' "$WATCHER" || true)
if grep -q "FileMode.Append" "$WATCHER" && [ "${overwrite_count:-0}" -le 1 ]; then
  _log_pass "error-log wird ausschließlich appendiert (Init-WriteAll '' erlaubt)"
else
  _log_fail "error-log wird ausschließlich appendiert" "Overwrite-Count=$overwrite_count, FileMode.Append fehlt evtl."
fi

# Atomarer Status-Write
if grep -q '\.tmp' "$WATCHER" && grep -q 'File.Replace' "$WATCHER"; then
  _log_pass "Status-Write ist atomar (.tmp + File.Replace)"
else
  _log_fail "Status-Write ist atomar (.tmp + File.Replace)" "Pattern fehlt"
fi

suite "Unity-Watcher: Schemas & Fixtures"
SCHEMA1="$SKILL_DIR/tests/fixtures/unity-status.schema.json"
SCHEMA2="$SKILL_DIR/tests/fixtures/error-log-entry.schema.json"
assert_file_exists "$SCHEMA1" "unity-status.schema.json"
assert_file_exists "$SCHEMA2" "error-log-entry.schema.json"
assert_json_valid  "$SCHEMA1" "unity-status.schema.json valide"
assert_json_valid  "$SCHEMA2" "error-log-entry.schema.json valide"

# Schema enthält neue Felder
for f in phaseId project compileCount errorCount; do
  if jq -e ".properties | has(\"$f\")" "$SCHEMA1" >/dev/null; then
    _log_pass "unity-status.schema enthält Feld '$f'"
  else
    _log_fail "unity-status.schema enthält Feld '$f'" "fehlt"
  fi
done

# Fixtures sind valide NDJSON
for fix in error-log.cs0246.jsonl error-log.nullref.jsonl; do
  fp="$SKILL_DIR/tests/fixtures/$fix"
  assert_file_exists "$fp" "fixtures/$fix"
  if [ -s "$fp" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if echo "$line" | jq empty >/dev/null 2>&1; then
        :
      else
        _log_fail "fixtures/$fix Zeile ist valides JSON" "Zeile: $line"
        continue 2
      fi
    done < "$fp"
    _log_pass "fixtures/$fix: alle Zeilen sind valides JSON"
  fi
done

# Timeout-Fixture darf leer sein
TIMEOUT_FIX="$SKILL_DIR/tests/fixtures/error-log.timeout.jsonl"
if [ -f "$TIMEOUT_FIX" ] && [ ! -s "$TIMEOUT_FIX" ]; then
  _log_pass "fixtures/error-log.timeout.jsonl ist (gewollt) leer"
else
  _log_fail "fixtures/error-log.timeout.jsonl ist (gewollt) leer" "Datei fehlt oder nicht leer"
fi

suite "Unity-Watcher: pipeline/unity-watcher.md"
DOC="$SKILL_DIR/pipeline/unity-watcher.md"
assert_file_exists "$DOC" "pipeline/unity-watcher.md"
for needle in "unity-status.json" "error-log.jsonl" "atomar" "phaseId" \
              "compileCount" "errorCount" "Batchmode" "compileOnce"; do
  if grep -qi "$needle" "$DOC"; then
    _log_pass "unity-watcher.md dokumentiert '$needle'"
  else
    _log_fail "unity-watcher.md dokumentiert '$needle'" "fehlt"
  fi
done

suite "Unity-Watcher: pipeline/project-init.md (Schritte h–k)"
PI="$SKILL_DIR/pipeline/project-init.md"
assert_file_exists "$PI" "pipeline/project-init.md"

# Step h) Watcher kopieren
if grep -q "AutoCompileWatcher.cs.txt" "$PI" && grep -q "Assets/Editor" "$PI"; then
  _log_pass "Schritt h) AutoCompileWatcher → Assets/Editor"
else
  _log_fail "Schritt h) AutoCompileWatcher → Assets/Editor" "Anweisung fehlt"
fi

# Step i) unity-status.json + error-log.jsonl
if grep -q "unity-status.json" "$PI" && grep -q "error-log.jsonl" "$PI"; then
  _log_pass "Schritt i) Watcher-Artefakte initialisieren"
else
  _log_fail "Schritt i) Watcher-Artefakte initialisieren" "fehlt"
fi

# Step k) Erst-Kompilierung im Batchmode
if grep -q "BatchCompile.Run" "$PI" && grep -q "batchmode" "$PI"; then
  _log_pass "Schritt k) Batchmode-Erstkompilierung"
else
  _log_fail "Schritt k) Batchmode-Erstkompilierung" "fehlt"
fi

print_summary
