---
name: game-dev-orchestrator
description: >
  Autonomes Spielentwicklungssystem. Triggert wenn der User ein Spiel
  entwickelt haben möchte. Koordiniert die Planung (via Ollama Cloud),
  die Code-Generierung (via VS Code Copilot) und das Testing (via Unity).
  Arbeitet in einem 10-Phasen-System vollständig autonom.
---

# Game Development Orchestrator

Dieses Skill-System ermöglicht die vollautonome Entwicklung von Spielen
in Unity. Es nutzt ein 3-Agenten-System:

## Architektur

1. **Hans (OpenClaw/Gizmo)**: Orchestrator
   - Steuert den Gesamtablauf
   - Erstellt/bearbeitet Dateien
   - Führt Terminal-Befehle aus
   - Kommuniziert mit User via Telegram

2. **Günther (Ollama Cloud / Kimi K2.5)**: Architekt
   - Erstellt 10-Phasen-Pläne
   - Formuliert Prompts für den Copilot
   - Analysiert Fehler
   - Entscheidet über Phase-Übergänge

3. **VS Code Copilot (Claude Sonnet 4.6)**: Programmierer
   - Schreibt den eigentlichen C#-Code
   - Erstellt Unity-Scripts
   - Implementiert Game-Mechaniken

## Aktivierung

Der Skill wird aktiviert wenn der User Nachrichten sendet wie:
- "Bau mir ein Spiel..."
- "Erstelle ein Game..."
- "Entwickle ein Spiel wie..."
- "Mach ein Game im Stil von..."
- "Neues Spielprojekt..."

## Konfiguration

Alle Einstellungen in: `gamedev-config.json` (im Skill-Ordner)

Wichtige Pfade:
- Projekte: ~/GameDev-Projekte/
- Templates: ~/GameDev-Projekte/_templates/
- Config: workspace/skills/game-dev-orchestrator/gamedev-config.json

## Workflow

### Phase 0: Initialisierung
1. User-Prompt empfangen und verstehen
2. Genre erkennen (Driving, Platformer, RPG, Sandbox, etc.)
3. Genre-spezifischen Kontext laden (aus prompts/game-genres/)
4. An Günther senden für Planungserstellung

### Phase 1-9: Entwicklung
Für jede Phase:
1. Günther nach Phase-Prompt fragen
2. Unity-Projektordner vorbereiten
3. Prompt an VS Code Copilot injizieren
4. Auf Code-Generierung warten
5. Unity-Kompilierung prüfen
6. Bei Fehler: Fehler-Korrektur-Schleife (max 5 Versuche)
7. Bei Erfolg: Phase als abgeschlossen markieren
8. Weiter zur nächsten Phase

### Phase 10: Finalisierung
1. Unity Build erstellen
2. Build testen (kompiliert er?)
3. Build-Ordner bereinigen
4. User benachrichtigen mit Ergebnis

## Zustandsverwaltung

Alle Zustände werden in `.plan/` Ordner im Projektverzeichnis gespeichert:
- `master-plan.json`      → Der 10-Phasen-Plan von Günther
- `current-phase.json`    → Aktuelle Phase + Status
- `phase-history.json`    → Alle bisherigen Phasen + Ergebnisse
- `error-log.json`        → Alle aufgetretenen Fehler + Lösungen
- `copilot-prompts.json`  → Alle an den Copilot gesendeten Prompts
- `unity-status.json`     → Echtzeit-Unity-Status (vom AutoCompileWatcher)

## Sub-Skills / Funktionen

### 1. Project Initializer (Schritt 6)
Erstellt ein neues Unity-Projekt:
- Projektnamen generieren oder vom User übernehmen
- Verzeichnis erstellen unter ~/GameDev-Projekte/[Name]
- Unity-Projekt erstellen via CLI (batchmode)
- Ordnerstruktur anlegen (Assets/Scripts/Core, Player, Camera, UI, etc.)
- Templates kopieren (.gitignore, .editorconfig, GameManager.cs)
- .plan/ Ordner mit initialen JSON-Dateien anlegen
- Git initialisieren
- VS Code öffnen

### 2. Prompt Architect (Schritt 7)
Kommunikation mit Günther (Ollama Cloud):
- **createMasterPlan**: Spielidee → 10-Phasen-Plan
  - Sendet System-Prompt + Genre-Kontext + User-Wunsch an Günther
  - Empfängt JSON mit 10 Phasen inkl. Copilot-Prompts
  - Validiert und speichert als master-plan.json
- **createPhasePrompt**: Phase N → detaillierten Copilot-Prompt
  - Inkludiert aktuellen Codestand und bisherige Fehler
  - Günther erstellt optimierten Prompt
- **analyzeError**: Fehler → Korrektur-Prompt
  - Günther analysiert und erstellt Fix-Prompt
- **selectModel**: Aufgabe → passendes Copilot-Modell
  - Einfach → Haiku, Standard → Sonnet, Komplex → Opus

API-Aufruf an Günther:
```
POST https://ollama.com/v1/chat/completions
Headers: Authorization: Bearer [API_KEY], Content-Type: application/json
Body: { "model": "qwen3-coder-next:cloud", "messages": [...], "temperature": 0.3,
        "response_format": {"type": "json_object"} }
```

### 3. VS Code Bridge (Schritt 8)
Brücke zwischen Hans und VS Code Copilot:
- **Methode 1 (bevorzugt)**: Datei-basierte Injection
  - Hans erstellt Dateien mit Prompt-Kommentaren
  - Copilot vervollständigt automatisch
- **Methode 2**: Terminal-basierte Generierung (gh copilot)
- **Methode 3 (Fallback)**: xdotool UI-Automation (Linux)
- **Smart Wait**: Überwacht Dateigrösse/Timestamp statt blind zu warten
- **Code Extraction**: Bereinigt generierte Dateien (Markdown-Blöcke, Duplikate)

### 4. Unity Watcher (Schritt 9)
Überwacht Unity-Kompilierung und Runtime:
- AutoCompileWatcher.cs (Editor-Script in Assets/Editor/)
- Schreibt Status nach .plan/unity-status.json
- Status: idle | compiling | success | error | runtime-error
- Polling alle 3 Sekunden, Timeout nach 120 Sekunden
- Fallback: Unity Editor.log direkt lesen

### 5. Error Handler (Schritt 10)
Self-Healing Fehler-Korrektur-System:
- **Retry-Strategie:**
  - Versuch 1: Gleicher Prompt, gleiches Modell
  - Versuch 2: Geänderter Prompt (Fehler-Kontext)
  - Versuch 3: Modell-Upgrade (Sonnet → Opus)
  - Versuch 4: Vereinfachter Ansatz
  - Versuch 5: Minimaler Code + User-Hilfe
- **Fehler-Klassifizierung**: CRITICAL (kompiliert nicht) | MAJOR (Logik) | MINOR (Warning)
- **Error-Log**: Alle Fehler in .plan/error-log.json protokolliert

### 6. Phase Manager (Schritt 11)
Verwaltet den 10-Phasen-Fortschritt:
- current-phase.json: Aktive Phase, Status, Versuchszähler
- phase-history.json: Archiv aller abgeschlossenen Phasen
- **advanceToNextPhase()**: Archiviert aktuelle Phase, lädt nächste
- **Fortschritts-Benachrichtigung** via Telegram:
  - Phase-Start: "📋 Phase 3/10: Kamera-System..."
  - Phase-Erfolg: "✅ Phase 3/10 abgeschlossen!"
  - Fehler: "🔧 Phase 3/10: Fehler gefunden, korrigiere..."
  - Hilfe nötig: "🆘 Phase 3/10: Brauche deine Hilfe..."

## Fehlerbehandlung

- Max 5 Korrektur-Versuche pro Phase
- Nach 5 Fehlschlägen: User benachrichtigen und um Input bitten
- Fehler werden in error-log.json protokolliert
- Günther analysiert Fehler und formuliert Korrektur-Prompts

## Sicherheit

- Keine externen Aktionen ohne User-Bestätigung
- Nur im vorgesehenen Projektordner arbeiten
- Unity Build nur lokal, kein Upload
- Alle Aktionen werden geloggt

## Referenz-Dateien

- `prompts/architect-system.txt` → System-Prompt für Günther
- `prompts/error-analysis.txt` → Error-Analyse-Prompt
- `prompts/phase-transition.txt` → Phase-Übergangs-Prompt
- `prompts/copilot-system-prompt.txt` → Copilot-Injection-Format
- `prompts/game-genres/*.txt` → Genre-spezifische Kontexte
- `references/ollama-api.txt` → API-Dokumentation
- `references/vscode-cli.txt` → VS Code CLI Referenz
- `references/copilot-modes.txt` → Copilot-Steuerungsmethoden
- `references/ui-automation.txt` → xdotool/Linux-Automation
- `references/approach-decision.txt` → Entscheidungsmatrix Ansätze
- `references/unity-project-structure.txt` → Unity-Ordnerstruktur
- `references/csharp-patterns.txt` → C#-Patterns für Unity
- `references/common-unity-errors.txt` → Häufige Unity-Fehler
- `templates/*` → Template-Dateien für neue Projekte
