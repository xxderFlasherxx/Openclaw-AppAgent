# Kontext-Management

## Übersicht

Das Kontext-Management ist das "Gedächtnis" des Systems. Es sorgt dafür,
dass Hans, Günther und der Copilot jederzeit genau die Informationen
haben, die sie brauchen — nicht zu viel (Kontext-Überlauf) und nicht
zu wenig (fehlende Abhängigkeiten).

## 1. Project Scanner

Der Project Scanner analysiert den aktuellen Zustand des Unity-Projekts.

```
FUNKTION: scanProject(projectPath)

  result = {
    projectPath: projectPath,
    scanTimestamp: now(),
    totalFiles: 0,
    totalLines: 0,
    scripts: [],
    scenes: [],
    prefabs: [],
    materials: [],
    shaders: [],
    otherAssets: []
  }

  // ── C# Scripts scannen ────────────────────────────────────
  scriptFiles = findFiles(projectPath + "/Assets/Scripts/**/*.cs")

  FOR EACH file IN scriptFiles:
    content = readFile(file)
    lines = content.split("\n")

    scriptInfo = {
      path: relativePath(file, projectPath),
      lines: lines.length,
      sizeBytes: getFileSize(file),
      lastModified: getModifiedTime(file),
      classes: [],
      publicMethods: [],
      publicProperties: [],
      dependencies: [],
      usings: [],
      hasErrors: false
    }

    // Klassen extrahieren
    classMatches = regex.findAll(content,
      /(?:public|internal|abstract)\s+(?:partial\s+)?class\s+(\w+)/)
    scriptInfo.classes = classMatches.map(m => m.group(1))

    // Public Methoden extrahieren
    methodMatches = regex.findAll(content,
      /public\s+(?:static\s+)?(?:virtual\s+)?(?:override\s+)?\w+\s+(\w+)\s*\(/)
    scriptInfo.publicMethods = methodMatches.map(m => m.group(1))

    // Public Properties extrahieren
    propMatches = regex.findAll(content,
      /public\s+\w+\s+(\w+)\s*\{/)
    scriptInfo.publicProperties = propMatches.map(m => m.group(1))

    // using-Statements extrahieren
    usingMatches = regex.findAll(content, /using\s+([\w.]+);/)
    scriptInfo.usings = usingMatches.map(m => m.group(1))

    // Abhängigkeiten zu anderen Scripts erkennen
    // (Wenn eine Klasse aus einem anderen Script referenziert wird)
    FOR EACH otherScript IN scriptFiles:
      IF otherScript != file:
        otherClasses = extractClassNames(otherScript)
        FOR EACH cls IN otherClasses:
          IF content CONTAINS cls:
            scriptInfo.dependencies.push(cls)
          END IF
        END FOR
      END IF
    END FOR

    result.scripts.push(scriptInfo)
    result.totalFiles += 1
    result.totalLines += lines.length
  END FOR

  // ── Szenen scannen ────────────────────────────────────────
  sceneFiles = findFiles(projectPath + "/Assets/Scenes/**/*.unity")
  result.scenes = sceneFiles.map(f => relativePath(f, projectPath))

  // ── Prefabs scannen ───────────────────────────────────────
  prefabFiles = findFiles(projectPath + "/Assets/Prefabs/**/*.prefab")
  result.prefabs = prefabFiles.map(f => relativePath(f, projectPath))

  // ── Materials scannen ─────────────────────────────────────
  materialFiles = findFiles(projectPath + "/Assets/Materials/**/*.mat")
  result.materials = materialFiles.map(f => relativePath(f, projectPath))

  // ── Shader scannen ────────────────────────────────────────
  shaderFiles = findFiles(projectPath + "/Assets/Shaders/**/*.shader")
  result.shaders = shaderFiles.map(f => relativePath(f, projectPath))

  RETURN result

ENDE
```

### Scanner-Ausgabe Beispiel

```json
{
  "projectPath": "/home/vboxuser/GameDev-Projekte/CatLongDrive",
  "scanTimestamp": "2026-04-10T14:30:00Z",
  "totalFiles": 12,
  "totalLines": 1850,
  "scripts": [
    {
      "path": "Assets/Scripts/Core/GameManager.cs",
      "lines": 85,
      "sizeBytes": 2340,
      "lastModified": "2026-04-10T14:05:00Z",
      "classes": ["GameManager"],
      "publicMethods": ["PauseGame", "ResumeGame", "QuitGame"],
      "publicProperties": ["Instance", "isGameRunning", "isPaused"],
      "dependencies": [],
      "usings": ["UnityEngine"],
      "hasErrors": false
    },
    {
      "path": "Assets/Scripts/Player/PlayerController.cs",
      "lines": 230,
      "sizeBytes": 7820,
      "lastModified": "2026-04-10T14:15:00Z",
      "classes": ["PlayerController"],
      "publicMethods": ["Move", "Jump", "Interact"],
      "publicProperties": ["Speed", "JumpForce"],
      "dependencies": ["GameManager", "InputManager"],
      "usings": ["UnityEngine", "UnityEngine.InputSystem"],
      "hasErrors": false
    }
  ],
  "scenes": ["Assets/Scenes/MainMenu.unity", "Assets/Scenes/GameScene.unity"],
  "prefabs": ["Assets/Prefabs/Player/Player.prefab"],
  "materials": ["Assets/Materials/PlayerMat.mat", "Assets/Materials/GroundMat.mat"],
  "shaders": []
}
```

## 2. Context Compressor

Da Günther (Kimi K2.5, ~128k Kontext) und der Copilot (Sonnet 4.6)
begrenzte Kontextfenster haben, muss der Kontext intelligent komprimiert
werden.

### Strategie nach Phase

| Phase   | Kontext-Level     | Was wird mitgegeben                        |
|---------|-------------------|--------------------------------------------|
| 1-3     | FULL              | Alle Dateien komplett                      |
| 4-6     | RELEVANT          | Relevante Dateien komplett, Rest Summary   |
| 7-9     | FOCUSED           | Nur aktuelle Datei + Interface-Summaries   |
| 10      | MINIMAL           | Nur Build-Konfiguration                    |

### Implementierung

```
FUNKTION: compressContext(projectContext, phase, targetAudience)

  phaseId = phase.id
  contextLevel = determineContextLevel(phaseId)

  // ── FULL: Alles mitgeben ──────────────────────────────────
  IF contextLevel == "FULL":

    context = "AKTUELLER PROJEKTSTAND:\n\n"
    context += "Dateien: " + projectContext.totalFiles + "\n"
    context += "Zeilen: " + projectContext.totalLines + "\n\n"

    FOR EACH script IN projectContext.scripts:
      content = readFile(script.path)
      context += "═══ " + script.path + " (" + script.lines + " Zeilen) ═══\n"
      context += content + "\n\n"
    END FOR

    RETURN context

  END IF

  // ── RELEVANT: Nur relevante Dateien komplett ──────────────
  IF contextLevel == "RELEVANT":

    context = "AKTUELLER PROJEKTSTAND:\n\n"
    context += "Dateien: " + projectContext.totalFiles + "\n"
    context += "Zeilen: " + projectContext.totalLines + "\n\n"

    // Relevante Dateien bestimmen
    relevantPaths = phase.expectedFiles
                    .concat(phase.dependencies || [])
                    .concat(getDirectDependencies(phase, projectContext))

    FOR EACH script IN projectContext.scripts:
      IF script.path IN relevantPaths OR
         script.classes.some(c => phase.copilotPrompt CONTAINS c):
        // Relevant → Vollständig
        content = readFile(script.path)
        context += "═══ " + script.path + " (VOLLSTÄNDIG) ═══\n"
        context += content + "\n\n"
      ELSE:
        // Nicht relevant → Summary
        context += "═══ " + script.path + " (ZUSAMMENFASSUNG) ═══\n"
        context += generateFileSummary(script) + "\n\n"
      END IF
    END FOR

    RETURN context

  END IF

  // ── FOCUSED: Nur aktuelle Datei + Interfaces ──────────────
  IF contextLevel == "FOCUSED":

    context = "PROJEKTÜBERSICHT:\n"
    context += "Dateien: " + projectContext.totalFiles + "\n"
    context += "Zeilen: " + projectContext.totalLines + "\n\n"

    // Interface-Übersicht aller Scripts
    context += "VERFÜGBARE KLASSEN & METHODEN:\n"
    FOR EACH script IN projectContext.scripts:
      context += "  " + script.path + ":\n"
      context += "    Klassen: " + script.classes.join(", ") + "\n"
      context += "    Methoden: " + script.publicMethods.join(", ") + "\n"
      context += "    Properties: " + script.publicProperties.join(", ") + "\n\n"
    END FOR

    // Aktuelle Datei(en) vollständig
    context += "\nAKTUELLE DATEIEN (VOLLSTÄNDIG):\n"
    FOR EACH file IN phase.expectedFiles:
      IF fileExists(file):
        content = readFile(file)
        context += "═══ " + file + " ═══\n"
        context += content + "\n\n"
      END IF
    END FOR

    RETURN context

  END IF

  // ── MINIMAL: Nur Build-Konfiguration ──────────────────────
  IF contextLevel == "MINIMAL":

    context = "BUILD KONFIGURATION:\n\n"
    context += "Szenen: " + projectContext.scenes.join(", ") + "\n"
    context += "Build Target: " + config.unity.buildTarget + "\n"
    context += "Render Pipeline: " + config.unity.renderPipeline + "\n"

    RETURN context

  END IF

ENDE
```

### File Summary Generator

```
FUNKTION: generateFileSummary(scriptInfo)

  summary = ""
  summary += "// Zeilen: " + scriptInfo.lines + "\n"
  summary += "// Klassen: " + scriptInfo.classes.join(", ") + "\n"
  summary += "// Public Methoden:\n"
  FOR EACH method IN scriptInfo.publicMethods:
    summary += "//   - " + method + "()\n"
  END FOR
  summary += "// Public Properties:\n"
  FOR EACH prop IN scriptInfo.publicProperties:
    summary += "//   - " + prop + "\n"
  END FOR
  summary += "// Abhängigkeiten: " + scriptInfo.dependencies.join(", ") + "\n"

  RETURN summary

ENDE
```

## 3. Dependency Graph

Hans baut einen Abhängigkeits-Graphen um zu wissen, welche Dateien
voneinander abhängen. Das ist wichtig für:
- Kontext-Auswahl (welche Dateien muss der Copilot sehen)
- Fehler-Diagnose (Fehler in A kann durch Änderung in B verursacht sein)
- Phase-Reihenfolge (kann nicht B machen bevor A existiert)

```
FUNKTION: buildDependencyGraph(projectContext)

  graph = {
    nodes: {},     // Klasse → { file, methods, properties }
    edges: []      // { from: Klasse, to: Klasse, type: "uses"|"extends" }
  }

  // Knoten erstellen
  FOR EACH script IN projectContext.scripts:
    FOR EACH cls IN script.classes:
      graph.nodes[cls] = {
        file: script.path,
        methods: script.publicMethods,
        properties: script.publicProperties
      }
    END FOR
  END FOR

  // Kanten erstellen (Abhängigkeiten)
  FOR EACH script IN projectContext.scripts:
    FOR EACH dep IN script.dependencies:
      FOR EACH cls IN script.classes:
        graph.edges.push({
          from: cls,
          to: dep,
          type: "uses"
        })
      END FOR
    END FOR
  END FOR

  RETURN graph

ENDE
```

### Abhängigkeits-Analyse für eine Phase

```
FUNKTION: getDirectDependencies(phase, projectContext)

  // Welche existierenden Dateien MUSS der Copilot sehen,
  // um die neue Datei korrekt zu implementieren?

  depFiles = []

  FOR EACH expectedFile IN phase.expectedFiles:
    // Suche im Prompt nach Referenzen auf existierende Klassen
    FOR EACH script IN projectContext.scripts:
      FOR EACH cls IN script.classes:
        IF phase.copilotPrompt CONTAINS cls:
          depFiles.push(script.path)
        END IF
      END FOR
    END FOR
  END FOR

  // Deduplizieren
  RETURN unique(depFiles)

ENDE
```

## 4. Memory Writer (Learnings)

Nach jeder Phase speichert Hans die gewonnenen Erkenntnisse.

### Learnings-Datei

Pfad: `[projektordner]/.plan/learnings.json`

```json
{
  "projectName": "CatLongDrive",
  "startedAt": "2026-04-10T14:00:00Z",
  "patterns": [
    {
      "phase": 2,
      "learning": "WheelCollider braucht Rigidbody auf Parent-Objekt",
      "errorThatTaughtUs": "MissingComponentException: WheelCollider requires Rigidbody",
      "fix": "[RequireComponent(typeof(Rigidbody))] Attribut hinzugefügt",
      "category": "unity-physics"
    },
    {
      "phase": 3,
      "learning": "Cinemachine muss als Package importiert werden",
      "errorThatTaughtUs": "CS0246: The type 'CinemachineVirtualCamera' could not be found",
      "fix": "Package com.unity.cinemachine in manifest.json hinzugefügt",
      "category": "unity-packages"
    }
  ],
  "modelPreferences": {
    "physics": { "model": "opus", "reason": "Sonnet hat 2x falsche WheelCollider-Config erzeugt" },
    "ui": { "model": "sonnet", "reason": "Standard-UI funktionierte beim ersten Versuch" },
    "boilerplate": { "model": "haiku", "reason": "Einfache Dateien, schnell erledigt" }
  },
  "timingData": {
    "avgGuentherResponseTime": "8.3s",
    "avgCopilotGenerationTime": "42s",
    "avgCompileTime": "12s",
    "avgPhaseTime": "3m 20s",
    "fastestPhase": { "id": 1, "time": "1m 10s" },
    "slowestPhase": { "id": 2, "time": "8m 45s", "reason": "3 Fehler-Korrekturen" }
  },
  "promptQuality": [
    {
      "phase": 1,
      "promptLength": 450,
      "attemptsNeeded": 1,
      "rating": "good"
    },
    {
      "phase": 2,
      "promptLength": 820,
      "attemptsNeeded": 3,
      "rating": "poor",
      "improvement": "Mehr Details zu WheelCollider-Setup nötig"
    }
  ]
}
```

### Learnings speichern

```
FUNKTION: savePhaselearnings(projectPath, phaseId, phaseResult)

  learningsFile = projectPath + "/.plan/learnings.json"
  learnings = readJSON(learningsFile)

  // Neue Patterns aus Fehlern extrahieren
  IF phaseResult.errors.length > 0:
    FOR EACH error IN phaseResult.errors:
      IF error.resolution == "fixed":
        learnings.patterns.push({
          phase: phaseId,
          learning: error.resolutionDetails,
          errorThatTaughtUs: error.message,
          fix: error.fix,
          category: categorizeError(error)
        })
      END IF
    END FOR
  END IF

  // Timing-Daten aktualisieren
  updateTimingData(learnings, phaseId, phaseResult)

  // Prompt-Qualität bewerten
  quality = "good"
  IF phaseResult.attempts > 2: quality = "poor"
  ELSE IF phaseResult.attempts > 1: quality = "fair"

  learnings.promptQuality.push({
    phase: phaseId,
    promptLength: phaseResult.promptUsed.length,
    attemptsNeeded: phaseResult.attempts,
    rating: quality,
    improvement: quality != "good" ?
      askGuentherForPromptImprovement(phaseResult) : null
  })

  writeJSON(learningsFile, learnings)

ENDE
```

### Globale Learnings aktualisieren

Nach Projektabschluss werden die Learnings ins globale Memory übernommen:

```
FUNKTION: updateGlobalLearnings(projectLearnings)

  globalPatterns = readJSON("workspace/memory/gamedev-patterns.json")

  FOR EACH pattern IN projectLearnings.patterns:
    existing = globalPatterns.patterns[pattern.category]

    IF existing:
      // Pattern existiert schon → Erfolgsrate aktualisieren
      existing.timesUsed += 1
      existing.successRate = recalculate(existing, pattern)
    ELSE:
      // Neues Pattern → Hinzufügen
      globalPatterns.patterns[pattern.category] = {
        prompt: pattern.fix,
        successRate: 1.0,
        timesUsed: 1,
        learnedFrom: projectLearnings.projectName
      }
    END IF
  END FOR

  // Model-Preferences aktualisieren
  FOR EACH [task, pref] IN projectLearnings.modelPreferences:
    IF globalPatterns.modelPreferences[task]:
      // Voting: aktuelles Preference + neues → gewichtet
      globalPatterns.modelPreferences[task] =
        mergePreference(globalPatterns.modelPreferences[task], pref)
    ELSE:
      globalPatterns.modelPreferences[task] = pref
    END IF
  END FOR

  writeJSON("workspace/memory/gamedev-patterns.json", globalPatterns)

ENDE
```

## 5. Recovery: Projektstand wiederherstellen

Falls Hans neu gestartet wird, kann er den Projektstand wiederherstellen:

```
FUNKTION: recoverProjectState()

  // 1. Aktives Projekt prüfen
  gamedevState = readJSON("workspace/memory/gamedev-state.json")

  IF gamedevState.currentProject == null:
    RETURN null  // Kein aktives Projekt
  END IF

  projectPath = gamedevState.currentProject.path

  // 2. Orchestrator-State laden
  orchState = readJSON(projectPath + "/.plan/orchestrator-state.json")

  // 3. Current-Phase laden
  currentPhase = readJSON(projectPath + "/.plan/current-phase.json")

  // 4. State-Zusammenfassung erstellen
  recovery = {
    project: orchState.project,
    lastState: orchState.state,
    currentPhase: currentPhase.currentPhaseId,
    phaseName: currentPhase.currentPhaseName,
    phaseStatus: currentPhase.status,
    attempt: currentPhase.attempt,
    lastUpdate: orchState.lastUpdate
  }

  // 5. Entscheidung wie fortgesetzt wird
  SWITCH orchState.state:
    CASE "EXECUTING":
      // Prüfe ob sich Dateien geändert haben
      IF filesChangedSince(orchState.lastUpdate):
        recovery.resumeAt = "VERIFYING"
      ELSE:
        recovery.resumeAt = "EXECUTING"  // Erneut versuchen
      END IF

    CASE "VERIFYING":
      recovery.resumeAt = "VERIFYING"  // Unity-Status erneut prüfen

    CASE "CORRECTING":
      recovery.resumeAt = "CORRECTING"  // Letzten Fehler erneut analysieren

    CASE "BUILDING":
      recovery.resumeAt = "BUILDING"  // Build-Status prüfen

    CASE "PHASE_DONE":
      recovery.resumeAt = "NEXT_PHASE"  // Nächste Phase starten

    DEFAULT:
      recovery.resumeAt = orchState.state
  END SWITCH

  // 6. User informieren
  notifyUser("🔄 Projekt wiederhergestellt: " + recovery.project +
             "\nFortgesetzt bei Phase " + recovery.currentPhase +
             " (" + recovery.phaseName + ")" +
             "\nStatus: " + recovery.phaseStatus)

  RETURN recovery

ENDE
```
