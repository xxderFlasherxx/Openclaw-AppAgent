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

### Referenzen
- `references/ollama-api.txt` → API-Dokumentation
- `references/vscode-cli.txt` → VS Code CLI Referenz
- `references/copilot-modes.txt` → Copilot-Steuerungsmethoden
- `references/ui-automation.txt` → xdotool/Linux-Automation
- `references/approach-decision.txt` → Entscheidungsmatrix Ansätze
- `references/unity-project-structure.txt` → Unity-Ordnerstruktur
- `references/csharp-patterns.txt` → C#-Patterns für Unity
- `references/common-unity-errors.txt` → Häufige Unity-Fehler

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

### Test-Daten (Dry-Run)
- `test-data/mock-master-plan.json` → Mock 3-Phasen-Plan (JumpingCube)
- `test-data/mock-unity-status.json` → Mock Unity-Status Szenarien
- `test-data/mock-guenther-responses.json` → Mock Günther-Antworten
