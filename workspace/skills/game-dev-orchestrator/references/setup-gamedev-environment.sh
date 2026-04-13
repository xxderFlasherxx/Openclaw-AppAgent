#!/bin/bash
# ==============================================================================
# AUTONOMES GAMEDEV SYSTEM - Entwicklungsumgebung einrichten
# Zielsystem: Linux (VirtualBox, /home/vboxuser/)
# ==============================================================================

set -e

echo "============================================"
echo " Autonomes GameDev System - Setup"
echo "============================================"
echo ""

HOME_DIR="${HOME:-/home/vboxuser}"
PROJECTS_DIR="$HOME_DIR/GameDev-Projekte"
WORKSPACE_DIR="$HOME_DIR/workspace"
SKILL_DIR="$WORKSPACE_DIR/skills/game-dev-orchestrator"

# --- 1. Projektordner erstellen ---
echo "[1/6] Erstelle Projektordner..."
mkdir -p "$PROJECTS_DIR"
mkdir -p "$PROJECTS_DIR/_templates"
echo "  ✔ $PROJECTS_DIR"

# --- 2. VS Code Extensions installieren ---
echo "[2/6] Installiere VS Code Extensions..."
if command -v code &> /dev/null; then
    code --install-extension github.copilot 2>/dev/null || echo "  ⚠ github.copilot bereits installiert oder Fehler"
    code --install-extension github.copilot-chat 2>/dev/null || echo "  ⚠ github.copilot-chat bereits installiert oder Fehler"
    code --install-extension ms-dotnettools.csdevkit 2>/dev/null || echo "  ⚠ csdevkit bereits installiert oder Fehler"
    echo "  ✔ Extensions installiert"
else
    echo "  ⚠ VS Code CLI nicht gefunden, Extensions manuell installieren"
fi

# --- 3. .editorconfig für Unity-Projekte ---
echo "[3/6] Erstelle .editorconfig Template..."
cat > "$PROJECTS_DIR/_templates/.editorconfig" << 'EDITORCONFIG'
# EditorConfig - Unity C# Projekte
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.cs]
indent_size = 4

[*.json]
indent_size = 2

[*.{yaml,yml}]
indent_size = 2

[*.md]
trim_trailing_whitespace = false

[*.meta]
indent_size = 2
EDITORCONFIG
echo "  ✔ .editorconfig erstellt"

# --- 4. .gitignore Template für Unity ---
echo "[4/6] Erstelle .gitignore Template..."
cat > "$PROJECTS_DIR/_templates/.gitignore" << 'GITIGNORE'
# Unity generated
/[Ll]ibrary/
/[Tt]emp/
/[Oo]bj/
/[Bb]uild/
/[Bb]uilds/
/[Ll]ogs/
/[Uu]ser[Ss]ettings/

# Visual Studio / Rider
.vs/
.vscode/settings.json
*.csproj
*.sln
*.suo
*.user
*.pidb
*.booproj
*.svd
*.pdb
*.mdb
*.opendb
*.VC.db

# OS
.DS_Store
Thumbs.db
*.swp
*~

# Unity Asset Store / Packages Cache
/Assets/AssetStoreTools/

# Crashlytics
crashlytics-build.properties

# .plan Ordner wird NICHT ignoriert (Hans braucht Zugriff)
GITIGNORE
echo "  ✔ .gitignore erstellt"

# --- 5. Memory-Ordner im Workspace ---
echo "[5/6] Erstelle Memory-Ordner..."
mkdir -p "$WORKSPACE_DIR/memory"
echo "  ✔ $WORKSPACE_DIR/memory"

# --- 6. Skill-Ordnerstruktur ---
echo "[6/6] Erstelle Skill-Ordnerstruktur..."
mkdir -p "$SKILL_DIR/prompts/game-genres"
mkdir -p "$SKILL_DIR/references"
mkdir -p "$SKILL_DIR/templates"
echo "  ✔ Skill-Ordner erstellt"

echo ""
echo "============================================"
echo " Setup abgeschlossen!"
echo "============================================"
echo ""
echo "Erstellte Struktur:"
echo "  $PROJECTS_DIR/"
echo "  ├── _templates/"
echo "  │   ├── .editorconfig"
echo "  │   └── .gitignore"
echo "  $WORKSPACE_DIR/"
echo "  ├── memory/"
echo "  └── skills/game-dev-orchestrator/"
echo "      ├── prompts/game-genres/"
echo "      ├── references/"
echo "      └── templates/"
echo ""
echo "Nächster Schritt: Führe check-prerequisites.sh aus"
echo "  bash $SKILL_DIR/references/check-prerequisites.sh"
