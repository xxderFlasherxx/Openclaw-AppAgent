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

## Die Autonome Pipeline (Teil D)

Die Pipeline ist das Herzstück des Systems. Sie verbindet alle Sub-Skills
zu einer durchgängigen, selbststeuernden Zustandsmaschine.

### Zustandsmaschine (State Machine)

Detailliert in: `pipeline/master-orchestrator.md`

**Zustände:**
```
WAITING → ANALYZING → PLANNING → INITIALIZING → EXECUTING
→ VERIFYING → (CORRECTING ↔ VERIFYING) → PHASE_DONE
→ NEXT_PHASE → EXECUTING ... → BUILDING → COMPLETE
```

**Zustands-Übergänge:**
| Von           | Nach         | Trigger                         |
|---------------|--------------|----------------------------------|
| WAITING       | ANALYZING    | User sendet Spielwunsch          |
| ANALYZING     | PLANNING     | Genre erkannt                    |
| PLANNING      | INITIALIZING | 10-Phasen-Plan validiert         |
| INITIALIZING  | EXECUTING    | Projekt erstellt, VS Code offen  |
| EXECUTING     | VERIFYING    | Copilot hat Code geschrieben     |
| VERIFYING     | PHASE_DONE   | Unity: "success"                 |
| VERIFYING     | CORRECTING   | Unity: "error"/"runtime-error"   |
| CORRECTING    | VERIFYING    | Korrektur angewendet             |
| PHASE_DONE    | NEXT_PHASE   | Phase < 10                       |
| PHASE_DONE    | BUILDING     | Phase == 10                      |
| BUILDING      | COMPLETE     | Build erfolgreich                |

**Recovery bei Unterbrechung:**
Hans kann bei Neustart den letzten Zustand aus `orchestrator-state.json` laden
und am letzten bekannten Punkt fortsetzen.

### Genre-Erkennung & Planungsphase

Detailliert in: `pipeline/planning-phase.md`

**Genre-Erkennung:**
- Keyword-basiert (deutsch + englisch) mit Score-System
- Referenz-Spiele als starke Indikatoren (3x Gewicht)
- Fallback: Günther als Genre-Experte befragen
- Unterstützte Genres: driving-game, platformer, rpg, sandbox

**Planungs-Workflow:**
1. Genre erkennen → Genre-Kontext laden
2. Günther System-Prompt + Genre-Kontext + User-Wunsch senden
3. 10-Phasen-Plan als JSON empfangen
4. Plan validieren (10 Phasen, alle Pflichtfelder, logische Abhängigkeiten)
5. User informieren (Phasen-Übersicht per Telegram)
6. Auf Bestätigung warten (wenn `autoStart = false`)

### Ausführungsschleife (Execution Loop)

Detailliert in: `pipeline/execution-loop.md`

**Pro Phase:**
1. Kontext sammeln (Project Scanner)
2. Günther nach finalisiertem Phase-Prompt fragen
3. Copilot-Modell wählen (Haiku/Sonnet/Opus)
4. Prompt-Header in Zieldatei(en) schreiben
5. Smart Wait: Auf Dateiänderung warten
6. Code bereinigen (Markdown-Blöcke, Duplikate, Klammern)
7. Unity-Status prüfen → VERIFYING
8. Bei Erfolg: Phase archivieren, Git Commit, weiter
9. Bei Fehler: Error-Correction-Loop

**Timing pro Phase:** ~2-3 min (Ideal), ~5-10 min (mit Fehlern)
**Timing Gesamtprojekt:** ~25-45 min (realistisch)

### Fehler-Korrektur-System

Detailliert in: `pipeline/error-correction.md`

**5-Stufen Retry-Strategie:**
1. Gleicher Prompt, gleiches Modell (Sonnet)
2. Erweiterter Prompt mit Günther-Analyse (Sonnet)
3. Modell-Upgrade (→ Opus) + Fehlerhistorie
4. Vereinfachter Ansatz (Günther schlägt simplere Lösung vor)
5. Minimaler Stub (Haiku) + User-Einbeziehung

**Fehler-Klassifizierung:**
- CRITICAL: Kompilierungsfehler (CS0246, CS1061, etc.)
- MAJOR: Runtime-Fehler (NullRef, MissingComponent, IndexOutOfRange)
- MINOR: Warnungen (werden nur geloggt, nicht behoben)

**Incident Report:** Nach 5 Fehlversuchen → User per Telegram benachrichtigen
mit Optionen: /skip, /reset-phase, /manual, oder konkreter Hinweis.

### Kontext-Management

Detailliert in: `pipeline/context-management.md`

**Project Scanner:** Analysiert alle C#-Scripts, Szenen, Prefabs, Materials
- Extrahiert Klassen, Public Methods, Properties, Dependencies
- Baut Dependency Graph

**Context Compressor (nach Phase):**
- Phase 1-3: FULL → Alle Dateien komplett
- Phase 4-6: RELEVANT → Relevante komplett, Rest Summary
- Phase 7-9: FOCUSED → Nur aktuelle Datei + Interface-Summaries
- Phase 10: MINIMAL → Nur Build-Konfiguration

**Memory Writer:**
- Speichert Learnings pro Phase (Fehler → Fix → Erkenntnis)
- Tracking von Modell-Preferences (welches Modell für welche Aufgabe)
- Timing-Daten (für zukünftige Schätzungen)
- Prompt-Qualitätsbewertung (gut/mittel/schlecht)
- Globale Learnings nach Projektabschluss aktualisieren

## Fehlerbehandlung

- Max 5 Korrektur-Versuche pro Phase (konfigurierbar)
- 5-Stufen Eskalation: Simple Retry → Analyse → Modell-Upgrade → Vereinfachung → User
- Fehler werden in `.plan/error-log.json` protokolliert (mit Severity, Kategorie, Resolution)
- Günther analysiert Fehler und formuliert Korrektur-Prompts
- Learnings werden gespeichert um gleiche Fehler zukünftig zu vermeiden

## Sicherheit

- Keine externen Aktionen ohne User-Bestätigung
- Nur im vorgesehenen Projektordner arbeiten
- Unity Build nur lokal, kein Upload
- Alle Aktionen werden geloggt
- Recovery bei Unterbrechung (kein Datenverlust)

## User-Befehle (während Pipeline)

| Befehl         | Aktion                                    |
|----------------|-------------------------------------------|
| "Pause"        | Pipeline anhalten, State speichern        |
| "Weiter"       | Pipeline an letzter Stelle fortsetzen     |
| "Stopp"        | Pipeline komplett abbrechen               |
| "Projektstand" | Aktuelle Phase, Status, Statistiken       |
| "/skip"        | Aktuelle Phase überspringen               |
| "/reset-phase" | Aktuelle Phase komplett neu starten       |
| "/manual"      | User übernimmt aktuelle Phase             |
| "Code zeigen"  | Aktuellen Code der Phase senden           |

## Referenz-Dateien

### Prompts
- `prompts/architect-system.txt` → System-Prompt für Günther
- `prompts/error-analysis.txt` → Error-Analyse-Prompt
- `prompts/phase-transition.txt` → Phase-Übergangs-Prompt
- `prompts/copilot-system-prompt.txt` → Copilot-Injection-Format
- `prompts/game-genres/*.txt` → Genre-spezifische Kontexte (driving, platformer, rpg, sandbox)

### Pipeline (Teil D)
- `pipeline/master-orchestrator.md` → Komplette Zustandsmaschine + Pseudocode
- `pipeline/planning-phase.md` → Genre-Erkennung + Planungs-Workflow
- `pipeline/execution-loop.md` → Ausführungsschleife + Smart Wait + Code-Bereinigung
- `pipeline/error-correction.md` → 5-Stufen Fehlerkorrektur + Klassifizierung
- `pipeline/context-management.md` → Project Scanner + Kompression + Memory

### Pipeline (Teil G – Erweiterungen)
- `pipeline/model-routing.md` → Haiku/Sonnet/Opus-Routing + Kosten-Tracking
- `pipeline/memory-system.md` → Drei-Ebenen-Memory + Pattern-Library
- `pipeline/user-feedback.md` → Telegram-Rating-Flow + Prompt-Hints

### Referenzen
- `references/ollama-api.txt` → API-Dokumentation
- `references/vscode-cli.txt` → VS Code CLI Referenz
- `references/copilot-modes.txt` → Copilot-Steuerungsmethoden
- `references/ui-automation.txt` → xdotool/Linux-Automation
- `references/approach-decision.txt` → Entscheidungsmatrix Ansätze
- `references/unity-project-structure.txt` → Unity-Ordnerstruktur
- `references/csharp-patterns.txt` → C#-Patterns für Unity
- `references/common-unity-errors.txt` → Häufige Unity-Fehler

### Referenzen (Teil E - Unity-Integration)
- `references/unity-cli-commands.txt` → Unity CLI Referenz (Befehle, Flags, Return-Codes)
- `references/build-workflow.txt` → Build-Workflow-Dokumentation (Prä-Build, Build, Post-Build)

### Templates (für `.plan/` Ordner)
- `templates/orchestrator-state.json` → Initiale Zustandsmaschine
- `templates/current-phase.json` → Initiale aktuelle Phase
- `templates/phase-history.json` → Initiale Phase-Historie
- `templates/error-log.json` → Initiales Error-Log
- `templates/master-plan.json` → Leerer Master-Plan (10 Phasen)
- `templates/learnings.json` → Initiale Learnings
- `templates/copilot-prompts.json` → Initiales Prompt-Log
- `templates/unity-status.json` → Initialer Unity-Status
- `templates/unity-gitignore.txt` → .gitignore Template
- `templates/unity-editorconfig.txt` → .editorconfig Template
- `templates/base-game-manager.cs.txt` → GameManager Template
- `templates/base-player-controller.cs.txt` → PlayerController Template
- `templates/AutoCompileWatcher.cs.txt` → Unity Compile Watcher

### Basis-Templates (Teil E - Schritt 17)
- `templates/Singleton.cs.txt` → Generisches Singleton-Pattern
- `templates/SceneLoader.cs.txt` → Async Szenen-Lader mit Loading-Screen
- `templates/InputManager.cs.txt` → Input-System (**Legacy Input Manager, Zero-Config**, kein Asset-Setup nötig)
- `templates/AudioManager.cs.txt` → Audio-Manager (Musik, SFX, Volume)
- `templates/SharedInventory.cs.txt` → **Shared Inventar-Typen** (ItemData, InventorySlot, InventorySystem, ItemType) — für RPG und Sandbox

### Editor-Scripts (Teil E - Schritt 18)
- `templates/editor/AutoBuilder.cs.txt` → Automatisierter Build (Windows/Linux/WebGL/Dev)
- `templates/editor/SceneBootstrapper.cs.txt` → Szene automatisch einrichten (Kamera, Licht, etc.)
- `templates/editor/AutoComponentAssigner.cs.txt` → Komponenten nach Namenskonvention zuweisen

### Genre-spezifische Templates (Teil E - Schritt 17.2)

**Driving:**
- `templates/genres/driving/VehicleController.cs.txt` → Fahrzeug mit WheelColliders
- `templates/genres/driving/SpeedometerUI.cs.txt` → Tachometer UI
- `templates/genres/driving/FuelSystem.cs.txt` → Treibstoff-System

**Platformer:**
- `templates/genres/platformer/PlatformerController.cs.txt` → 2D Controller mit Coyote-Time, Wandsprung
- `templates/genres/platformer/GroundCheck.cs.txt` → Bodenerkennung
- `templates/genres/platformer/CoinCollector.cs.txt` → Collectible-System

**RPG:**
- `templates/genres/rpg/RPGCharacterController.cs.txt` → Third-Person Controller
- `templates/genres/rpg/DialogueSystem.cs.txt` → Dialog-System mit Typing-Effekt
- `templates/genres/rpg/InventorySystem.cs.txt` → ⚠️ **DEPRECATED** — ersetzt durch `templates/SharedInventory.cs.txt`

**Sandbox:**
- `templates/genres/sandbox/FPSController.cs.txt` → First-Person Controller mit Crouch, HeadBob
- `templates/genres/sandbox/BlockPlacer.cs.txt` → Block-Platzierungs-System
- `templates/genres/sandbox/CraftingSystem.cs.txt` → Crafting mit ScriptableObject-Rezepten

### Template-Deployment-Regeln (Teil E)

| Genre        | Required Templates                                             |
|--------------|----------------------------------------------------------------|
| Driving      | Singleton, SceneLoader, InputManager, AudioManager + Driving-Set |
| Platformer   | Singleton, SceneLoader, InputManager, AudioManager + Platformer-Set |
| RPG          | Singleton, SceneLoader, InputManager, AudioManager, **SharedInventory** + RPG-Set |
| Sandbox      | Singleton, SceneLoader, InputManager, AudioManager, **SharedInventory** + Sandbox-Set |
| RPG + Sandbox| Singleton, SceneLoader, InputManager, AudioManager, **SharedInventory EINMAL** + beide Sets |

**Wichtige Regeln:**
- `SharedInventory.cs.txt` IMMER vor `CraftingSystem.cs.txt` deployen
- `InventorySystem.cs.txt` (RPG/deprecated) NICHT zusammen mit `SharedInventory.cs.txt` deployen  
  → Doppelte Klassen-Definitionen = Compiler-Fehler
- `InputManager.cs.txt` funktioniert **ohne jedes Setup** (Legacy Input Manager)

### Test-Daten (Dry-Run)
- `test-data/mock-master-plan.json` → Mock 3-Phasen-Plan (JumpingCube)
- `test-data/mock-unity-status.json` → Mock Unity-Status Szenarien
- `test-data/mock-guenther-responses.json` → Mock Günther-Antworten

### Tests (Teil F – Schritt 20 & 21)
- `tests/run-tests.sh` → Haupt-Runner (200+ automatische Checks, `--online` für Ollama-Ping)
- `tests/simulate-dry-run.sh` → Dry-Run-Simulator pro Szenario (`MOCK_PLAN=...` für 10-Phasen-Plan)
- `tests/test-genre-detection.sh` → Unit-Test für Keyword-basierte Genre-Erkennung
- `tests/lib/assertions.sh` → Assertion-Helper (Bash)
- `tests/test-scenarios.md` → 5 Testszenarien dokumentiert
- `tests/e2e-jumping-cube.md` → End-to-End Runbook für JumpingCube
- `tests/KNOWN-ISSUES.md` → Bekannte Abweichungen vom Plan & Design-Entscheidungen
- `tests/fixtures/` → Genre-Rules, Genre-Cases, Unity-Status-Schema
- `tests/README.md` → Kurzanleitung

**Verwendung:**
```bash
bash workspace/skills/game-dev-orchestrator/tests/run-tests.sh           # offline
bash workspace/skills/game-dev-orchestrator/tests/run-tests.sh --online  # +API-Ping
```

Die Tests decken ab (31 Suiten inkl. Teil G):
- Skill-Grundstruktur, Pipeline-Dokumente, Prompts, Templates
- JSON-Validität aller Config/Mock/Template-Dateien
- `gamedev-config.json`-Schema (Pflichtfelder)
- Mock-Master-Plans (3- und 10-Phasen-Varianten)
- Unity-Status-Sequenzen + JSON-Schema-Contract
- Günther-Mock-Antworten (JSON-in-JSON)
- 4 Dry-Run-Szenarien: happy_path, single_error, multiple_errors, max_retries
- Genre-Erkennung (16 eindeutige + 2 mehrdeutige Ground-Truth-Cases)
- Template-Content-Smoke-Tests (verhindert versehentlich leere Dateien)
- Deprecated-Kennzeichnung (`InventorySystem.cs.txt`)
- dryRun-Sanity-Check (warnt vor Prod mit dryRun=true)
- VS-Code/Copilot-Umgebung (nicht-blockierend)
- Workspace-Integration (AGENTS/SOUL/USER/TOOLS/IDENTITY, openclaw.json-Tools)
- Bash-Syntax aller Shell-Scripts
- Opt-in: Ollama-Cloud-Erreichbarkeit (`--online`)

**Dry-Run-Modus aktivieren** (über `gamedev-config.json`):
```json
{ "dryRun": true }
```
Wenn `dryRun = true`, werden im echten Orchestrator statt Günther, VS Code
und Unity die Mocks aus `test-data/` verwendet. Der Test-Runner warnt,
wenn `dryRun=true` in der Config steht (Sanity-Check gegen vergessene
Test-Flags im Produktionseinsatz).

**Bekannte Abweichungen vom Plan** (siehe `tests/KNOWN-ISSUES.md`):
- Pfad: `gamedev-config.json` nutzt Linux-Pfad `/home/vboxuser/GameDev-Projekte`,
  Plan war für macOS geschrieben. Config ist Single Source of Truth.
- Modell: Config nutzt `qwen3-coder-next:cloud`, Plan erwähnt `kimi-k2.5`.
  Beide via Ollama Cloud erreichbar.
- Orchestrator ist **skill-basiert** (Hans interpretiert Markdown-Specs zur
  Laufzeit), nicht als eigenständiger Code-Prozess implementiert.

## Erweiterungen & Optimierungen (Teil G)

### 1. Modell-Routing (Schritt 22)

Detailliert in: `pipeline/model-routing.md`

Nicht jede Aufgabe braucht Opus. Das Routing wählt pro Phase automatisch
das passende Copilot-Modell:
- **Haiku**: Struktur, Config, Editor-Scripts, Build (billig + schnell)
- **Sonnet 4.6**: UI, Standard-Gamelogik, einfache Bug-Fixes (Default)
- **Opus**: Physik, Prozedural, AI, Shader, Retry ≥ 3 (Eskalation)

Entscheidungs-Reihenfolge:
1. Config-Override (`modelRouting.overrides[phaseId]`)
2. Retry-Eskalation (`retryCount >= escalateAtRetry` → Opus)
3. Phase-Kategorie (`phase.category` → `modelRouting.categoryMap`)
4. Keyword-Scoring auf Name + Prompt
5. Fallback: `defaultModel` (Sonnet)

Modell-Nutzung wird pro Projekt in `.plan/model-usage.json` geloggt
(Template: `templates/model-usage.json`). Kosten werden on-the-fly aus
`modelRouting.pricing` berechnet.

### 2. Mehrstufiges Memory-System (Schritt 23)

Detailliert in: `pipeline/memory-system.md`

Drei Ebenen:
- **Kurzzeit** (Per-Phase): `.plan/learnings.json`, `error-log.json`
- **Mittelfristig** (Per-Projekt): `workspace/memory/gamedev-projects.json`
  — Archiv aller Projekte mit Dauer, Fehlern, Kosten, Rating
- **Langfristig** (Cross-Project): `workspace/memory/gamedev-patterns.json`
  — Pattern-Library mit `successRate` und `timesUsed`

Nach jedem abgeschlossenen Projekt:
1. `archiveProject()` → Eintrag in `gamedev-projects.json`
2. `updatePattern(key, success)` für jeden genutzten Pattern
3. Bei `projects.length > 100`: FIFO-Archivierung in
   `gamedev-projects-archive.json`

Bei neuem Projekt (Planning-Phase) wird Günthers Kontext um Top-Patterns
und Recent-Learnings des gleichen Genres angereichert
(`buildPlannerContext(genre)`).

### 3. User-Feedback-Integration (Schritt 24)

Detailliert in: `pipeline/user-feedback.md`

Nach Fertigstellung fragt Hans via Telegram um Bewertung (1–5 Sterne).
- Rating ≤ 3 → Detail-Follow-up ("Was war schlecht?")
- Rating ≥ 4 → Detail-Follow-up ("Was war besonders gut?")
- Timeout: 24h (konfigurierbar in `feedback.timeoutHours`)

Feedback fließt zurück:
- In `gamedev-projects.json` als `qualityRating` + `feedback`
- In die Pattern-Library als Success/Failure pro genutztem Pattern
- In zukünftige Günther-Prompts als Prompt-Hints
  (`templates/feedback-prompt-hints.json`)
- In Timing-Budgets: Rating ≤ 2 → `timeoutPerPhaseSeconds × 1.5`,
  `maxRetriesPerPhase + 2` für nächstes gleiches Genre

### Neue Pipeline-Dokumente (Teil G)

- `pipeline/model-routing.md` → Routing-Algorithmus, Keyword-Tabellen,
  Kostenberechnung
- `pipeline/memory-system.md` → Drei Memory-Ebenen, Archivierung,
  Pattern-Updates
- `pipeline/user-feedback.md` → Telegram-Flow, Rating-Speicherung,
  Prompt-Hint-Generierung

### Neue Templates (Teil G)

- `templates/model-usage.json` → Initialer Per-Projekt-Usage-Tracker
- `templates/gamedev-projects.json` → Leere Project-Archive-Struktur
- `templates/gamedev-patterns.json` → Pattern-Library-Seed (3 Einträge)
- `templates/feedback-prompt-hints.json` → Mapping Feedback-Kategorie
  → Prompt-Hinweis

### Neue Memory-Dateien (Workspace)

- `workspace/memory/gamedev-projects.json` → Produktives Projekt-Archiv
- `workspace/memory/gamedev-patterns.json` → Produktive Pattern-Library

### Erweiterte Config (`gamedev-config.json`)

Drei neue Top-Level-Blöcke:
- `modelRouting` — Routing-Regeln, Keywords, Pricing
- `memory` — Datei-Pfade, FIFO-Limits, Pattern-Schwellen
- `feedback` — Timeout, Rating-Schwellen, Hints-Pfad


## Copilot-Bridge & Sicherheit (Teil H)

Mit Teil H wird aus dem "Architekt ohne Hände" ein vollwertiger Code-Generator.
Drei neue Bausteine sorgen dafür, dass Hans den VS Code Copilot tatsächlich
ansteuern, das Ergebnis bereinigen und unkontrollierte Schreibvorgänge
verhindern kann.

### 1. Prompt-Injection-Adapter (Schritt 25)

Detailliert in: `pipeline/copilot-bridge.md`

Drei Adapter mit fester Fallback-Reihenfolge:
- **Adapter A — `file-injection`** (Standard): Schreibt einen Prompt-Header
  in jede Zieldatei, legt `.plan/copilot-task.md` an und triggert den
  VS Code Task `copilot-run-phase` (Agent Mode).
- **Adapter B — `gh-copilot-cli`** (Fallback): Nutzt
  `gh copilot suggest` / `gh models run` für Utility-Files ohne
  Workspace-Kontext.
- **Adapter C — `ui-automation`** (Notfall): `xdotool` (X11) oder
  `ydotool`/`wtype` (Wayland) — nur wenn A+B explizit fehlschlagen.

Konfiguriert in `gamedev-config.json → copilotBridge`.
Aufgerufen in `pipeline/execution-loop.md` über `callCopilotBridge()`.

### 2. Code-Extraktion & Accept-Policy (Schritt 26)

`extractCleanCode(rawFile, expectedFile)` (in `copilot-bridge.md`)
- Strippt Markdown-Fences und Preambles
- Prüft Klammer-Balance, max. Datei-Größe, einzige Klassen-Definition
- Lehnt verbotene Tokens ab (`TODO-COPILOT`, `PLACEHOLDER`, …)
- Schreibt atomar und loggt Diff nach `.plan/copilot-diffs/phaseN-*.diff`

Eine Phase gilt nur dann als erledigt, wenn ALLE Zieldateien existieren,
verändert wurden, alle `extractCleanCode`-Checks bestehen und keine
verbotenen Tokens vorkommen.

Bei `accepted=false` geht der Master-Orchestrator in den Zustand
`CORRECTING` und übergibt den Reason
(`extraction_failed | timeout | unchanged | forbidden_token | unbalanced_syntax | oversized`)
an die Fehler-Korrektur (Schritt 15).

### 3. Approval-Gates & Sicherheitsmodus (Schritt 27)

Detailliert in: `pipeline/safety-gates.md`

- `safety.writeScope` / `safety.denyScope`: Glob-Pattern für erlaubte/
  verbotene Schreib-Pfade
- `safety.approvalMode`:
  `manual` | `auto-with-telegram-veto` | `fully-autonomous`
- `safety.vetoWindowSeconds`: 20 s Veto-Fenster bei Auto-Modus
- `safety.maxFilesChangedPerPhase`, `safety.maxBytesPerFile`: harte Limits
- `safety.dryRunFirstRun=true`: Erster Lauf eines Users ist immer Dry-Run.
  Prompts werden in `.plan/dry-run/phaseN-prompt.md` geschrieben, nichts
  wird ausgeführt. Freigabe via Telegram-Befehl `/realrun`.

Alle Gate-Entscheidungen werden append-only nach
`.plan/safety-audit.jsonl` geschrieben.

### Neue Pipeline-Dokumente (Teil H)

- `pipeline/copilot-bridge.md` → Adapter-Kette, Extraktion, Accept-Policy
- `pipeline/safety-gates.md`   → State-Übergänge, Scopes, Dry-Run

### Neue Tests (Teil H)

- `tests/test-copilot-bridge.sh`   → 38 Checks, Adapter-Auswahl
- `tests/test-code-extraction.sh`  → 27 Checks, 4 reject + 1 accept
- `tests/test-safety-gates.sh`     → 34 Checks, Scope/Limits/DryRun
- `tests/fixtures/copilot-bridge-cases.json` → 6 Adapter-Szenarien
- `tests/fixtures/extraction/*.cs.txt`       → 5 Extraktions-Fixtures

### Erweiterte Config (`gamedev-config.json`)

Drei neue Top-Level-Blöcke (Teil H):
- `copilotBridge` — Adapter-Reihenfolge, VS Code Task, Timeout
- `codeExtraction` — Fence/Preamble-Stripping, verbotene Tokens, Diff-Dir
- `safety` — writeScope/denyScope, Approval-Modus, Limits, Dry-Run
