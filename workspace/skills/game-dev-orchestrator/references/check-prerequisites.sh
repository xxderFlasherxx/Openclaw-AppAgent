#!/bin/bash
# ==============================================================================
# AUTONOMES GAMEDEV SYSTEM - Voraussetzungen prüfen
# Zielsystem: Linux (VirtualBox, /home/vboxuser/)
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

check() {
    local label="$1"
    local result="$2"
    local required="$3" # "required" oder "optional"

    if [ "$result" = "ok" ]; then
        echo -e "  ${GREEN}✔${NC} $label"
        PASS=$((PASS + 1))
    elif [ "$required" = "optional" ]; then
        echo -e "  ${YELLOW}⚠${NC} $label (optional)"
        WARN=$((WARN + 1))
    else
        echo -e "  ${RED}✘${NC} $label"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo " Autonomes GameDev System - Voraussetzungen"
echo "============================================"
echo ""

# --- 1. Node.js ---
echo "[1/8] Node.js..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 22 ]; then
        check "Node.js $NODE_VERSION (>= 22 erforderlich)" "ok"
    else
        check "Node.js $NODE_VERSION (>= 22 erforderlich, zu alt!)" "fail" "required"
    fi
else
    check "Node.js nicht installiert" "fail" "required"
fi

# --- 2. OpenClaw ---
echo "[2/8] OpenClaw..."
if command -v openclaw &> /dev/null; then
    OC_VERSION=$(openclaw --version 2>/dev/null || echo "unbekannt")
    check "OpenClaw installiert ($OC_VERSION)" "ok"
else
    check "OpenClaw nicht installiert (npm install -g openclaw@latest)" "fail" "required"
fi

# Prüfe ob OpenClaw Daemon/Prozess läuft
if pgrep -f "openclaw" > /dev/null 2>&1; then
    check "OpenClaw Prozess läuft" "ok"
else
    check "OpenClaw Prozess läuft NICHT (openclaw start)" "fail" "required"
fi

# --- 3. OpenClaw Workspace ---
echo "[3/8] OpenClaw Workspace..."
WORKSPACE="/home/vboxuser/workspace"
if [ -d "$WORKSPACE" ]; then
    check "Workspace existiert: $WORKSPACE" "ok"
else
    check "Workspace nicht gefunden: $WORKSPACE" "fail" "required"
fi

if [ -f "$WORKSPACE/SOUL.md" ]; then
    check "SOUL.md vorhanden (OpenClaw initialisiert)" "ok"
else
    check "SOUL.md fehlt (openclaw onboard ausführen)" "fail" "required"
fi

# --- 4. Ollama Cloud Erreichbarkeit ---
echo "[4/8] Ollama Cloud (Günther)..."
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer 4c18dad4048c4e52b84b9c613e63101b.dnsdNPbmk60VlY5pkTzqheY4" \
        "https://ollama.com/v1/models" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "404" ]; then
        check "Ollama Cloud erreichbar (HTTP $HTTP_CODE)" "ok"
    else
        check "Ollama Cloud NICHT erreichbar (HTTP $HTTP_CODE)" "fail" "required"
    fi
else
    check "curl nicht installiert" "fail" "required"
fi

# --- 5. VS Code ---
echo "[5/8] VS Code..."
if command -v code &> /dev/null; then
    VSCODE_VERSION=$(code --version 2>/dev/null | head -1)
    check "VS Code installiert ($VSCODE_VERSION)" "ok"
else
    check "VS Code nicht installiert" "fail" "required"
fi

# Prüfe Copilot Extension
if command -v code &> /dev/null; then
    if code --list-extensions 2>/dev/null | grep -qi "github.copilot"; then
        check "GitHub Copilot Extension installiert" "ok"
    else
        check "GitHub Copilot Extension FEHLT (code --install-extension github.copilot)" "fail" "required"
    fi

    if code --list-extensions 2>/dev/null | grep -qi "github.copilot-chat"; then
        check "GitHub Copilot Chat Extension installiert" "ok"
    else
        check "GitHub Copilot Chat Extension FEHLT" "fail" "required"
    fi
fi

# --- 6. Unity ---
echo "[6/8] Unity..."
# Linux: Unity Hub ist unter verschiedenen Pfaden möglich
UNITY_HUB=""
for path in "/usr/bin/unityhub" "$HOME/Unity/Hub/Editor" "$HOME/.local/share/Unity/Hub/Editor"; do
    if [ -e "$path" ]; then
        UNITY_HUB="$path"
        break
    fi
done

if [ -n "$UNITY_HUB" ]; then
    check "Unity Hub/Editor gefunden: $UNITY_HUB" "ok"
else
    check "Unity nicht gefunden (Unity Hub installieren)" "fail" "required"
fi

# Suche nach Unity Editor Binary
UNITY_EDITOR=""
for dir in "$HOME/Unity/Hub/Editor"/*/Editor/Unity "$HOME/.local/share/Unity/Hub/Editor"/*/Editor/Unity /opt/unity/Editor/Unity; do
    if [ -x "$dir" ] 2>/dev/null; then
        UNITY_EDITOR="$dir"
        break
    fi
done

if [ -n "$UNITY_EDITOR" ]; then
    check "Unity Editor Binary: $UNITY_EDITOR" "ok"
else
    check "Unity Editor Binary nicht gefunden" "fail" "required"
fi

# --- 7. Git ---
echo "[7/8] Git..."
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version)
    check "$GIT_VERSION" "ok"
else
    check "Git nicht installiert (sudo apt install git)" "fail" "required"
fi

# --- 8. GameDev Projektordner ---
echo "[8/8] Projektordner..."
PROJECTS_DIR="$HOME/GameDev-Projekte"
if [ -d "$PROJECTS_DIR" ]; then
    check "Projektordner existiert: $PROJECTS_DIR" "ok"
else
    check "Projektordner fehlt: $PROJECTS_DIR (wird von setup erstellt)" "fail" "optional"
fi

# --- Zusammenfassung ---
echo ""
echo "============================================"
echo " Ergebnis"
echo "============================================"
echo -e "  ${GREEN}Bestanden:${NC}  $PASS"
echo -e "  ${RED}Fehlend:${NC}    $FAIL"
echo -e "  ${YELLOW}Warnungen:${NC} $WARN"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}Es fehlen $FAIL Voraussetzungen! Bitte installiere die fehlenden Komponenten.${NC}"
    echo ""
    echo "Schnellinstallation (Ubuntu/Debian):"
    echo "  sudo apt update"
    echo "  sudo apt install -y curl git"
    echo "  # Node.js 22+: https://nodejs.org/en/download/"
    echo "  # Unity Hub: https://unity.com/download"
    echo "  # VS Code: https://code.visualstudio.com/download"
    echo "  # OpenClaw: npm install -g openclaw@latest"
    echo "  # Copilot: code --install-extension github.copilot github.copilot-chat"
    exit 1
else
    echo -e "${GREEN}Alle Voraussetzungen erfüllt! System bereit.${NC}"
    exit 0
fi
