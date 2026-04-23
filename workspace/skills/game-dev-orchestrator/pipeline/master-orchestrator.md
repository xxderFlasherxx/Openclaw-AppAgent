# Master-Orchestrator: Autonome Pipeline

## Übersicht

Der Master-Orchestrator ist die zentrale Steuerungslogik des autonomen
Game-Dev-Systems. Er verbindet alle Sub-Skills (Project Initializer,
Prompt Architect, VS Code Bridge, Unity Watcher, Error Handler, Phase Manager)
zu einer durchgängigen, selbststeuernden Pipeline.

## Dry-Run Modus

Gesteuert über `gamedev-config.json → dryRun: true/false`

Im Dry-Run-Modus durchläuft das System den gesamten Workflow, aber:
- **Günther wird NICHT angefragt** → Mock-Daten aus `test-data/mock-guenther-responses.json`
- **Der Copilot wird NICHT gesteuert** → Mock-Code wird in Dateien geschrieben
- **Unity wird NICHT kompiliert** → Mock-Status aus `test-data/mock-unity-status.json`
- **Der Master-Plan kommt aus** → `test-data/mock-master-plan.json`

Zweck: Testen ob die Zustandsmaschine, Datei-Erstellung und Phase-Übergänge
korrekt funktionieren, ohne echte API-Aufrufe oder UI-Automation.

```
IF config.dryRun:
  // Statt web_fetch an Günther → Lade Mock-Plan
  masterPlan = readJSON("test-data/mock-master-plan.json")

  // Statt VS Code Bridge → Schreibe Mock-Code
  writeFile(targetFile, "// Mock-Code für Phase " + phaseId)

  // Statt Unity-Watcher → Lade Mock-Status
  sequence = readJSON("test-data/mock-unity-status.json").sequence_happy_path
  unityStatus = sequence[currentStep]
END IF
```

## Zustandsmaschine (State Machine)

```
┌─────────────┐
│   WAITING    │ ←── Bereit für neuen Auftrag
└──────┬──────┘
       │ User: "Bau mir ein Spiel..."
       ▼
┌─────────────┐
│  ANALYZING   │ ←── Intent erkennen, Genre bestimmen
└──────┬──────┘
       │ Genre erkannt
       ▼
┌─────────────┐
│  PLANNING    │ ←── Günther erstellt 10-Phasen-Plan
└──────┬──────┘
       │ Plan empfangen & validiert
       ▼
┌─────────────┐
│ INITIALIZING │ ←── Unity-Projekt erstellen, Ordnerstruktur
└──────┬──────┘
       │ Projekt bereit
       ▼
┌─────────────┐
│  EXECUTING   │ ←── Copilot-Prompt injizieren, Code generieren
└──────┬──────┘
       │ Code geschrieben
       ▼
┌─────────────┐     ┌─────────────┐
│  VERIFYING   │────▶│  CORRECTING  │ ←── Bei Fehler
└──────┬──────┘     └──────┬──────┘
       │ OK                │ Fix anwenden
       ▼                   │
┌─────────────┐            │
│ PHASE_DONE   │◀──────────┘
└──────┬──────┘
       │
  ┌────┴────┐
  ▼         ▼
┌──────┐ ┌─────────┐
│NEXT_ │ │BUILDING │ ←── Phase 10 (letzte Phase)
│PHASE │ └────┬────┘
└──┬───┘      │ Build fertig
   │          ▼
   │   ┌─────────────┐
   │   │  COMPLETE    │ ←── Spiel fertig!
   │   └──────┬──────┘
   │          │ (Teil G)
   │          ▼
   │   ┌─────────────┐
   │   │  ARCHIVING   │ ←── Project → Memory, Patterns updaten
   │   └──────┬──────┘
   │          │
   │          ▼
   │   ┌───────────────────┐
   │   │ AWAITING_FEEDBACK │ ←── Telegram-Rating
   │   └──────┬────────────┘
   │          │
   │          ▼
   │   ┌─────────────┐
   │   │    DONE      │ ──→ zurück zu WAITING
   │   └─────────────┘
   │
   └──▶ (zurück zu EXECUTING mit nächster Phase)
```

## Zustands-Definitionen

### WAITING
- **Beschreibung**: System wartet auf User-Eingabe
- **Eingangs-Aktion**: Keine
- **Ausgangs-Bedingung**: User sendet Nachricht mit Spiel-Bezug
- **Nächster Zustand**: ANALYZING

### ANALYZING
- **Beschreibung**: Hans analysiert die User-Nachricht
- **Aktionen**:
  1. Nachricht auf Spiel-Keywords prüfen
  2. Genre erkennen (siehe `pipeline/genre-detection.md`)
  3. Spielname vorschlagen oder vom User übernehmen
  4. Genre-Kontext aus `prompts/game-genres/` laden
- **Ausgangs-Bedingung**: Genre erkannt, Kontext geladen
- **Nächster Zustand**: PLANNING
- **Fehlerfall**: Genre nicht erkennbar → Günther fragen

### PLANNING
- **Beschreibung**: Günther erstellt den 10-Phasen-Plan
- **Aktionen**:
  1. System-Prompt laden: `prompts/architect-system.txt`
  2. Genre-Kontext laden: `prompts/game-genres/[genre].txt`
  3. Anfrage an Günther senden (via `web_fetch`)
  4. JSON-Antwort parsen und validieren
  5. 10-Phasen-Plan speichern als `.plan/master-plan.json`
  6. User per Telegram informieren (Phasen-Übersicht)
- **Ausgangs-Bedingung**: Plan validiert und gespeichert
- **Nächster Zustand**: INITIALIZING (wenn autoStart=true) oder WAITING_FOR_APPROVAL
- **Fehlerfall**: Günther antwortet nicht / invalides JSON → Retry (max 3x)

### INITIALIZING
- **Beschreibung**: Unity-Projekt wird erstellt
- **Aktionen**:
  1. Projektnamen normalisieren (CamelCase, keine Sonderzeichen)
  2. Verzeichnis erstellen: `[projectsRoot]/[ProjektName]/`
  3. Unity-Projekt erstellen via CLI (batchmode)
  4. Ordnerstruktur anlegen (Assets/Scripts/Core, Player, Camera, UI, etc.)
  5. Templates kopieren (.gitignore, .editorconfig, GameManager.cs)
  6. `.plan/` Ordner erstellen mit initialen JSON-Dateien
  7. Git initialisieren
  8. VS Code öffnen
  9. `orchestrator-state.json` initialisieren
  10. `current-phase.json` auf Phase 1 setzen
- **Ausgangs-Bedingung**: Projekt erstellt, VS Code offen
- **Nächster Zustand**: EXECUTING

### EXECUTING
- **Beschreibung**: Code-Generierung für aktuelle Phase
- **Aktionen**:
  1. Phase-Daten aus `master-plan.json` laden
  2. Kontext sammeln (siehe `pipeline/context-management.md`)
  3. Günther nach finalisiertem Phase-Prompt fragen
  4. `current-phase.json` aktualisieren: status → "in_progress"
  5. VS Code Bridge nutzen:
     a) Zieldatei(en) erstellen/öffnen
     b) Prompt als Kommentar-Block injizieren
     c) Smart Wait aktivieren
  6. User informieren: "📋 Phase X/10: [Name] wird bearbeitet..."
- **Ausgangs-Bedingung**: Copilot hat Code geschrieben (Datei geändert)
- **Nächster Zustand**: VERIFYING
- **Timeout**: `copilotWaitSeconds` (Standard: 60s)

### VERIFYING
- **Beschreibung**: Hans prüft das Ergebnis
- **Aktionen**:
  1. Geänderte Dateien einlesen
  2. Grundlegende Syntax-Checks:
     - Keine leeren Dateien
     - Keine Markdown-Codeblöcke übrig
     - Klammern balanciert
  3. Unity-Status prüfen via `.plan/unity-status.json`
  4. Polling alle `pollingIntervalSeconds` Sekunden
  5. Timeout nach `compileWaitSeconds`
- **Ausgangs-Bedingung (Erfolg)**: Unity sagt "success"
- **Nächster Zustand (Erfolg)**: PHASE_DONE
- **Ausgangs-Bedingung (Fehler)**: Unity sagt "error" oder "runtime-error"
- **Nächster Zustand (Fehler)**: CORRECTING

### CORRECTING
- **Beschreibung**: Fehler-Korrektur-Schleife
- **Aktionen**:
  1. Fehler aus `unity-status.json` lesen
  2. Fehler klassifizieren (CRITICAL/MAJOR/MINOR)
  3. Fehler in `error-log.json` protokollieren
  4. Retry-Strategie anwenden (siehe `pipeline/error-correction.md`)
  5. Korrektur-Prompt an Copilot senden
  6. `current-phase.json`: attempt += 1
- **Ausgangs-Bedingung**: Korrektur angewendet
- **Nächster Zustand**: VERIFYING (erneut prüfen)
- **Abbruch-Bedingung**: attempt > maxRetriesPerPhase → User benachrichtigen

### PHASE_DONE
- **Beschreibung**: Phase erfolgreich abgeschlossen
- **Aktionen**:
  1. `current-phase.json`: status → "completed"
  2. Phase in `phase-history.json` archivieren
  3. `orchestrator-state.json` aktualisieren
  4. Learnings speichern (falls aus Fehlern gelernt)
  5. Git Commit: "Phase [N]: [Name] abgeschlossen"
  6. User informieren: "✅ Phase X/10 abgeschlossen!"
- **Ausgangs-Bedingung**: Phase archiviert
- **Nächster Zustand**:
  - Phase < 10 → NEXT_PHASE
  - Phase == 10 → BUILDING

### NEXT_PHASE
- **Beschreibung**: Übergang zur nächsten Phase
- **Aktionen**:
  1. PhaseId inkrementieren
  2. `current-phase.json` auf neue Phase setzen (status: "planning")
  3. Kontext aktualisieren (Project Scanner)
  4. Günther nach neuem Phase-Prompt fragen
  5. `current-phase.json`: status → "ready"
- **Ausgangs-Bedingung**: Neuer Prompt bereit
- **Nächster Zustand**: EXECUTING

### BUILDING
- **Beschreibung**: Unity Build erstellen (Phase 10)
- **Aktionen**:
  1. Prüfen ob alle Szenen in Build Settings sind
  2. Unity Build via CLI starten:
     ```
     Unity -batchmode -projectPath [pfad] \
       -executeMethod AutoBuilder.Build \
       -buildTarget StandaloneLinux64 \
       -quit -logFile .plan/build.log
     ```
  3. `.plan/build-status.json` überwachen
  4. Polling alle 5 Sekunden, Timeout: 10 Minuten
- **Ausgangs-Bedingung (Erfolg)**: Build-Status "success"
- **Nächster Zustand**: COMPLETE
- **Ausgangs-Bedingung (Fehler)**: Build fehlgeschlagen → CORRECTING

### COMPLETE
- **Beschreibung**: Spiel ist fertig!
- **Aktionen**:
  1. Build-Informationen sammeln (Größe, Pfad)
  2. Gesamt-Statistik erstellen:
     - Gesamtdauer
     - Phasen abgeschlossen
     - Fehler behoben
     - Modelle verwendet
  3. `orchestrator-state.json`: state → "COMPLETE"
  4. `gamedev-state.json` aktualisieren (totalGamesCreated++)
  5. User benachrichtigen:
     ```
     🎮 SPIEL FERTIG!
     Name: [Name]
     Phasen: 10/10 ✅
     Dauer: [Zeit]
     Build: [Pfad]
     ```
  6. Nächster Zustand: ARCHIVING (Teil G, Schritt 23)

### ARCHIVING (Teil G, Schritt 23)
- **Beschreibung**: Projekt in Cross-Project-Memory überführen
- **Spezifiziert in**: `pipeline/memory-system.md`
- **Aktionen**:
  1. `archiveProject(state)` → Eintrag in
     `workspace/memory/gamedev-projects.json`
  2. Für jeden Key in `.plan/used-patterns.json`:
     `updatePattern(key, success=allPhasesCompleted)`
  3. Aggregate in gamedev-projects.json neu berechnen
  4. Bei >`memory.maxProjectsInMemory`: FIFO-Archivierung
     in `gamedev-projects-archive.json`
- **Ausgangs-Bedingung**: Archivierung erfolgreich
- **Nächster Zustand**: AWAITING_FEEDBACK (wenn feedback.enabled)
                         sonst DONE

### AWAITING_FEEDBACK (Teil G, Schritt 24)
- **Beschreibung**: User wird via Telegram um Rating gebeten
- **Spezifiziert in**: `pipeline/user-feedback.md`
- **Aktionen**:
  1. Telegram-Nachricht mit Statistik + 1–5-Rating-Abfrage
  2. `pendingFeedback`-State in orchestrator-state.json setzen,
     inkl. `timeoutAt = now() + feedback.timeoutHours * 3600`
  3. Warten auf Rating / `/skip` / Timeout
  4. Bei Rating ≤ `askDetailsBelowRating`: Detail-Follow-up "Was war schlecht?"
  5. Bei Rating ≥ `askDetailsAboveRating`: Detail-Follow-up "Was war gut?"
  6. `saveFeedback(projectName, rating, categories, freeText)`
  7. Pattern-Penalty/Bonus je nach Rating anwenden
- **Timeout-Verhalten**: `saveFeedback(..., rating=null, reason="timeout")`
- **Nächster Zustand**: DONE

### DONE
- **Beschreibung**: Projekt vollständig abgeschlossen inkl. Memory-Updates
- **Aktionen**:
  1. `gamedev-state.json.currentProject = null`
  2. `orchestrator-state.json.state = "DONE"`
  3. Zurück zu WAITING
- **End-Zustand**: Zurück zu WAITING

## Zustands-Übergänge (Transitions)

| Von           | Nach           | Trigger                              | Bedingung              |
|---------------|----------------|--------------------------------------|------------------------|
| WAITING       | ANALYZING      | User-Nachricht empfangen             | Enthält Spiel-Keywords |
| ANALYZING     | PLANNING       | Genre erkannt                        | Genre-Kontext geladen  |
| PLANNING      | INITIALIZING   | Plan validiert                       | 10 Phasen vorhanden    |
| INITIALIZING  | EXECUTING      | Projekt erstellt                     | VS Code offen          |
| EXECUTING     | VERIFYING      | Copilot fertig oder Timeout          | Datei geändert         |
| VERIFYING     | PHASE_DONE     | Unity: "success"                     | Keine Fehler           |
| VERIFYING     | CORRECTING     | Unity: "error"/"runtime-error"       | Fehler erkannt         |
| CORRECTING    | VERIFYING      | Korrektur angewendet                 | attempt <= max         |
| CORRECTING    | (User-Input)   | Max Retries erschöpft                | attempt > max          |
| PHASE_DONE    | NEXT_PHASE     | Phase archiviert                     | phaseId < 10           |
| PHASE_DONE    | BUILDING       | Phase 10 archiviert                  | phaseId == 10          |
| NEXT_PHASE    | EXECUTING      | Neuer Prompt bereit                  | Phase geladen          |
| BUILDING      | COMPLETE       | Build erfolgreich                    | build-status: success  |
| BUILDING      | CORRECTING     | Build fehlgeschlagen                 | build-status: failed   |
| COMPLETE      | ARCHIVING      | Projekt fertig                       | Immer (Teil G)         |
| ARCHIVING     | AWAITING_FEEDBACK | Memory aktualisiert               | feedback.enabled=true  |
| ARCHIVING     | DONE           | Memory aktualisiert                  | feedback.enabled=false |
| AWAITING_FEEDBACK | DONE       | Rating empfangen oder Timeout        | user-input / 24h       |
| DONE          | WAITING        | Projekt abgeschlossen                | Immer                  |

## Zustands-Datei

Pfad: `[projektordner]/.plan/orchestrator-state.json`

Wird bei **jedem** Zustandswechsel aktualisiert. Hans kann damit bei
Unterbrechung (Crash, Neustart) den letzten Stand wiederherstellen.

Struktur: Siehe `templates/orchestrator-state.json`

## Wiederherstellung nach Unterbrechung (Recovery)

Falls Hans abstürzt oder neu gestartet wird:

1. Prüfe ob ein aktives Projekt existiert (gamedev-state.json → currentProject)
2. Wenn ja → Lade orchestrator-state.json aus dem Projektordner
3. Setze beim letzten bekannten Zustand fort:
   - EXECUTING → Prüfe ob sich Dateien geändert haben → VERIFYING
   - VERIFYING → Unity-Status erneut prüfen
   - CORRECTING → Letzten Fehler erneut analysieren
   - BUILDING → Build-Status prüfen
   - PHASE_DONE → Nächste Phase starten
4. Informiere User: "🔄 Fortgesetzt bei Phase [N], Zustand: [State]"

## User-Interaktionen während der Pipeline

Hans reagiert auf folgende User-Befehle **jederzeit** während der Pipeline:

| Befehl         | Aktion                                             |
|----------------|----------------------------------------------------|
| "Pause"        | State merken, Pipeline anhalten                    |
| "Weiter"       | Pipeline an letzter Stelle fortsetzen              |
| "Stopp"        | Pipeline komplett abbrechen                        |
| "Projektstand" | Aktuelle Phase + Status senden                     |
| "/skip"        | Aktuelle Phase überspringen                        |
| "/reset-phase" | Aktuelle Phase komplett neu starten                |
| "/manual"      | User übernimmt aktuelle Phase                      |
| "Code zeigen"  | Hans sendet den aktuellen Code der Phase           |

## Haupt-Ablauf als Pseudocode

```
FUNKTION: runGameDevPipeline(userPrompt)

  // Phase 0: Analyse
  state = "ANALYZING"
  updateOrchestratorState(state)
  genre = detectGenre(userPrompt)
  genreContext = loadGenreContext(genre)

  // Phase 0: Planung
  state = "PLANNING"
  updateOrchestratorState(state)
  masterPlan = requestMasterPlan(userPrompt, genre, genreContext)
  validatePlan(masterPlan)
  saveMasterPlan(masterPlan)
  notifyUser("Plan erstellt", masterPlan.phases)

  // Warte auf User-Bestätigung (wenn autoStart == false)
  IF NOT config.autoStart THEN
    waitForUserApproval()
  END IF

  // Phase 0: Initialisierung
  state = "INITIALIZING"
  updateOrchestratorState(state)
  projectPath = initializeProject(masterPlan.gameName)
  openVSCode(projectPath)

  // Phasen 1-10: Hauptschleife
  FOR phase = 1 TO masterPlan.totalPhases DO

    // Nächste Phase vorbereiten
    state = "NEXT_PHASE" (ab Phase 2)
    context = scanProject(projectPath)
    phasePrompt = requestPhasePrompt(phase, masterPlan, context)

    // Phase ausführen
    state = "EXECUTING"
    updateCurrentPhase(phase, "in_progress")
    notifyUser("Phase gestartet", phase)
    injectPrompt(phasePrompt, phase.targetFiles)

    // Verifizieren
    state = "VERIFYING"
    attempt = 1
    WHILE attempt <= config.maxRetriesPerPhase DO
      unityStatus = waitForUnityStatus()

      IF unityStatus == "success" THEN
        state = "PHASE_DONE"
        archivePhase(phase, "completed")
        commitToGit("Phase " + phase.id + " abgeschlossen")
        notifyUser("Phase abgeschlossen", phase)
        BREAK
      ELSE IF unityStatus == "error" THEN
        state = "CORRECTING"
        error = readError()
        correctionPrompt = handleError(error, attempt)
        injectPrompt(correctionPrompt)
        attempt = attempt + 1
        state = "VERIFYING"
      END IF
    END WHILE

    // Max Retries erschöpft
    IF attempt > config.maxRetriesPerPhase THEN
      userDecision = notifyUserAndWait("Phase fehlgeschlagen")
      SWITCH userDecision
        CASE "skip": markPhaseSkipped(phase)
        CASE "reset": GOTO phase_start
        CASE "manual": waitForManualFix()
        CASE custom: applyCustomFix(userDecision)
      END SWITCH
    END IF

    // Phase 10: Build
    IF phase.id == masterPlan.totalPhases THEN
      state = "BUILDING"
      buildResult = buildUnityProject(projectPath)
      IF buildResult == "success" THEN
        state = "COMPLETE"
        finalizeProject(masterPlan, projectPath)
        notifyUser("Spiel fertig!", buildResult)

        // ── Teil G: Archivierung & Feedback ──────────────────
        state = "ARCHIVING"
        archiveProject(masterPlan, projectPath)          // memory-system.md
        usedPatterns = readJSON(projectPath + "/.plan/used-patterns.json").aggregate
        FOR EACH key IN usedPatterns:
          updatePattern(key, success=allPhasesCompleted())

        IF config.feedback.enabled THEN
          state = "AWAITING_FEEDBACK"
          requestFeedbackViaTelegram(masterPlan, projectPath)   // user-feedback.md
          waitForRatingOrTimeout(config.feedback.timeoutHours * 3600)
        END IF

        state = "DONE"
        clearCurrentProject()
      ELSE
        // Build-Fehler → Korrektur-Schleife
        handleBuildError(buildResult)
      END IF
    END IF

  END FOR

  RETURN "DONE"

END FUNKTION
```
