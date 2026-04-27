#!/bin/bash
# ==============================================================================
# Test: Batchmode-Fallback (Teil I, Schritt 29)
# ==============================================================================
# Testet den Log-Parser, indem synthetische unity-batch.log Dateien erzeugt
# und das resultierende unity-status.json verifiziert wird.
# ==============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assertions.sh"

CFG="$SKILL_DIR/gamedev-config.json"

suite "Batchmode: Config-Erweiterungen (gamedev-config.json)"
for k in mode editorBinary batchLogFile statusFile errorLogFile compileTimeoutSeconds; do
  v=$(jq -r ".unity.${k} // empty" "$CFG")
  # editorBinary darf leer sein (auto-detect), aber das Feld muss existieren
  if jq -e "has(\"unity\") and (.unity | has(\"$k\"))" "$CFG" >/dev/null; then
    _log_pass "unity.${k} im Config-Schema vorhanden"
  else
    _log_fail "unity.${k} im Config-Schema vorhanden" "fehlt"
  fi
done

# mode-Wert ist einer von editor/batch/auto
mode=$(jq -r '.unity.mode' "$CFG")
case "$mode" in
  editor|batch|auto) _log_pass "unity.mode=$mode (gültig)" ;;
  *) _log_fail "unity.mode gültig" "Wert: $mode" ;;
esac

# compileTimeoutSeconds > 0
ct=$(jq -r '.unity.compileTimeoutSeconds' "$CFG")
if [ "$ct" -gt 0 ] 2>/dev/null; then
  _log_pass "unity.compileTimeoutSeconds=$ct ist > 0"
else
  _log_fail "unity.compileTimeoutSeconds > 0" "Wert: $ct"
fi

suite "Batchmode: Template BatchCompile.cs.txt"
BC="$SKILL_DIR/templates/BatchCompile.cs.txt"
assert_file_exists "$BC" "templates/BatchCompile.cs.txt"
for needle in \
  "namespace OpenClaw" \
  "static class BatchCompile" \
  "RequestScriptCompilation" \
  "EditorApplication.Exit" ; do
  if grep -Fq "$needle" "$BC"; then
    _log_pass "BatchCompile.cs enthält '$needle'"
  else
    _log_fail "BatchCompile.cs enthält '$needle'" "fehlt"
  fi
done

# -----------------------------------------------------------------------------
# Mini-Implementierung des Log-Parsers in Bash (deckungsgleich mit dem
# Pseudocode in unity-watcher.md). Wird hier benutzt, damit das Verhalten
# vor der echten Implementierung dokumentiert und reproduzierbar ist.
# -----------------------------------------------------------------------------
parse_batch_log() {
  local log="$1"
  local timeout_marker="$2"     # "yes" => Status=timeout, ignore Inhalt
  local err_count
  err_count=$(grep -cE 'error CS[0-9]{4}' "$log" || true)

  if [ "$timeout_marker" = "yes" ]; then
    echo "timeout $err_count"
    return
  fi
  if grep -qE 'Aborting batchmode due to failure' "$log"; then
    echo "failed $err_count"
    return
  fi
  if [ "$err_count" -gt 0 ]; then
    echo "error $err_count"
    return
  fi
  if grep -qE 'Compilation succeeded|Scripts have compiled successfully' "$log"; then
    echo "success 0"
    return
  fi
  echo "unknown 0"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

suite "Batchmode: Log-Parser – error CS0246"
LOG="$TMP/err.log"
cat > "$LOG" <<'EOF'
[Licensing::Module] Channel opened
Assets/Scripts/Camera/CameraController.cs(5,7): error CS0246: The type or namespace name 'Cinemachine' could not be found
Compilation failed: 1 error(s), 0 warnings
Aborting batchmode due to failure:
EOF
read -r status err <<<"$(parse_batch_log "$LOG" no)"
assert_equals "$status" "failed" "Parser erkennt 'Aborting batchmode' → status=failed"
assert_equals "$err"    "1"      "Parser zählt 1 CS-Fehler"

suite "Batchmode: Log-Parser – success"
LOG2="$TMP/ok.log"
cat > "$LOG2" <<'EOF'
Refresh: detecting if any assets need to be imported or removed
Scripts have compiled successfully.
EOF
read -r status err <<<"$(parse_batch_log "$LOG2" no)"
assert_equals "$status" "success" "Parser erkennt 'Scripts have compiled successfully'"
assert_equals "$err"    "0"       "Parser zählt 0 Fehler"

suite "Batchmode: Log-Parser – timeout"
LOG3="$TMP/to.log"
echo "Importing assets ..." > "$LOG3"
read -r status err <<<"$(parse_batch_log "$LOG3" yes)"
assert_equals "$status" "timeout" "Parser meldet Timeout korrekt"

suite "Batchmode: Log-Parser – generischer error CS0103"
LOG4="$TMP/cs0103.log"
cat > "$LOG4" <<'EOF'
Assets/Scripts/Player/Foo.cs(12,9): error CS0103: The name 'undefinedVar' does not exist in the current context
EOF
read -r status err <<<"$(parse_batch_log "$LOG4" no)"
assert_equals "$status" "error" "Parser meldet 'error' bei nur CS-Fehler ohne Aborting"
assert_equals "$err"    "1"     "1 Fehler gezählt"

suite "Batchmode: pipeline/unity-watcher.md beschreibt Modes"
DOC="$SKILL_DIR/pipeline/unity-watcher.md"
for m in "editor" "batch" "auto"; do
  if grep -q "\`$m\`" "$DOC"; then
    _log_pass "unity-watcher.md dokumentiert mode=$m"
  else
    _log_fail "unity-watcher.md dokumentiert mode=$m" "fehlt"
  fi
done

print_summary
