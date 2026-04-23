#!/bin/bash
# ==============================================================================
# Assertions & Test-Helper für das GameDev-Orchestrator Testframework (Teil F)
# Wird von allen Test-Scripts via `source` eingebunden.
# ==============================================================================

# Farb-Codes
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# Globale Zähler (werden vom Runner genutzt)
: "${TESTS_PASSED:=0}"
: "${TESTS_FAILED:=0}"
: "${TESTS_SKIPPED:=0}"
: "${CURRENT_SUITE:=unnamed}"
: "${FAILED_TESTS:=}"

_log_pass() {
  printf "  ${GREEN}✔${NC} %s\n" "$1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

_log_fail() {
  printf "  ${RED}✘${NC} %s\n" "$1"
  if [ -n "$2" ]; then
    printf "      ${RED}→ %s${NC}\n" "$2"
  fi
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_TESTS="${FAILED_TESTS}\n  [${CURRENT_SUITE}] $1"
}

_log_skip() {
  printf "  ${YELLOW}⊘${NC} %s ${YELLOW}(skipped: %s)${NC}\n" "$1" "$2"
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

suite() {
  CURRENT_SUITE="$1"
  printf "\n${BOLD}${BLUE}▶ Suite: %s${NC}\n" "$1"
}

assert_file_exists() {
  local file="$1"; local msg="${2:-Datei existiert: $file}"
  if [ -f "$file" ]; then _log_pass "$msg"
  else _log_fail "$msg" "Datei fehlt: $file"; fi
}

assert_dir_exists() {
  local dir="$1"; local msg="${2:-Verzeichnis existiert: $dir}"
  if [ -d "$dir" ]; then _log_pass "$msg"
  else _log_fail "$msg" "Verzeichnis fehlt: $dir"; fi
}

assert_json_valid() {
  local file="$1"; local msg="${2:-JSON valide: $(basename "$file")}"
  if [ ! -f "$file" ]; then _log_fail "$msg" "Datei fehlt"; return; fi
  if jq empty "$file" >/dev/null 2>&1; then _log_pass "$msg"
  else _log_fail "$msg" "JSON-Parse-Fehler in $file"; fi
}

assert_jq() {
  local file="$1"; local query="$2"; local expected="$3"; local msg="$4"
  if [ ! -f "$file" ]; then _log_fail "$msg" "Datei fehlt: $file"; return; fi
  local actual
  actual=$(jq -r "$query" "$file" 2>&1)
  if [ "$actual" = "$expected" ]; then _log_pass "$msg"
  else _log_fail "$msg" "erwartet '$expected', erhalten '$actual'"; fi
}

assert_jq_nonempty() {
  local file="$1"; local query="$2"; local msg="$3"
  if [ ! -f "$file" ]; then _log_fail "$msg" "Datei fehlt: $file"; return; fi
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null)
  if [ -n "$actual" ] && [ "$actual" != "null" ] && [ "$actual" != "[]" ] && [ "$actual" != "{}" ]; then
    _log_pass "$msg"
  else _log_fail "$msg" "Ergebnis war leer/null für '$query'"; fi
}

assert_equals() {
  local actual="$1"; local expected="$2"; local msg="$3"
  if [ "$actual" = "$expected" ]; then _log_pass "$msg"
  else _log_fail "$msg" "erwartet '$expected', erhalten '$actual'"; fi
}

assert_contains() {
  local haystack="$1"; local needle="$2"; local msg="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then _log_pass "$msg"
  else _log_fail "$msg" "'$needle' nicht gefunden"; fi
}

print_summary() {
  local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
  printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${BOLD}Ergebnis:${NC} %d Tests total\n" "$total"
  printf "  ${GREEN}✔ Bestanden: %d${NC}\n" "$TESTS_PASSED"
  [ "$TESTS_SKIPPED" -gt 0 ] && printf "  ${YELLOW}⊘ Übersprungen: %d${NC}\n" "$TESTS_SKIPPED"
  printf "  ${RED}✘ Fehlgeschlagen: %d${NC}\n" "$TESTS_FAILED"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    printf "\n${RED}${BOLD}Fehlgeschlagene Tests:${NC}"
    printf "${FAILED_TESTS}\n"
    printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    return 1
  fi
  printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  return 0
}
