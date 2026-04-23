# Mehrstufiges Memory-System (Teil G, Schritt 23)

## Übersicht

Das Memory-System macht das Gesamtsystem lernfähig. Über mehrere
Projekte hinweg sammelt Hans:

1. **Project Memory** – Archiv abgeschlossener Projekte
2. **Pattern Library** – Bewährte Lösungs-Patterns mit Erfolgsquote
3. **Per-Project Learnings** – Phase-spezifische Erkenntnisse
   (bereits in `.plan/learnings.json` pro Projekt, wird hier aggregiert)

## Drei Memory-Ebenen

### Ebene 1: Kurzzeit (Per-Phase, in `.plan/`)
- Lebensdauer: aktuelles Projekt
- Dateien: `learnings.json`, `error-log.json`, `phase-history.json`, `model-usage.json`
- Zweck: Kontext für laufende Pipeline

### Ebene 2: Mittelfristig (Per-Projekt, in workspace memory)
- Lebensdauer: permanent, projekt-gebunden
- Datei: `workspace/memory/gamedev-projects.json`
- Zweck: Historie aller Projekte, User-Bewertungen

### Ebene 3: Langfristig (Cross-Project Patterns)
- Lebensdauer: permanent, projektübergreifend
- Datei: `workspace/memory/gamedev-patterns.json`
- Zweck: Wiederverwendbare Lösungs-Muster

## Project Memory

### Datei: `workspace/memory/gamedev-projects.json`

Schema (siehe `templates/gamedev-projects.json`):

```json
{
  "schemaVersion": 1,
  "projects": [
    {
      "name": "CatLongDrive",
      "projectPath": "/home/vboxuser/GameDev-Projekte/CatLongDrive",
      "genre": "driving-game",
      "startDate": "2026-04-10T10:00:00Z",
      "endDate":   "2026-04-10T10:47:00Z",
      "durationSeconds": 2820,
      "phases": 10,
      "phasesCompleted": 10,
      "phasesEscalated": 0,
      "totalErrors": 7,
      "totalRetries": 12,
      "modelUsage": {
        "haiku":  { "calls": 5,  "tokens": 2000,  "costUsd": 0.005 },
        "sonnet": { "calls": 12, "tokens": 15000, "costUsd": 0.09  },
        "opus":   { "calls": 3,  "tokens": 8000,  "costUsd": 0.30  }
      },
      "totalCostUsd": 0.395,
      "learnings": [
        "WheelCollider braucht Parent-Rigidbody",
        "Terrain Generation besser mit Perlin Noise",
        "Cinemachine für Kamera statt eigener Code"
      ],
      "qualityRating": null,
      "feedback": null,
      "finalBuildPath": "/home/vboxuser/GameDev-Projekte/CatLongDrive/Builds/",
      "success": true
    }
  ],
  "aggregate": {
    "totalProjects": 1,
    "successfulProjects": 1,
    "avgDurationSeconds": 2820,
    "avgPhasesEscalated": 0,
    "totalCostUsd": 0.395
  }
}
```

### Schreib-Workflow

```
FUNKTION: archiveProject(projectState)

  projects = readJSON("workspace/memory/gamedev-projects.json")

  entry = {
    name: projectState.name,
    projectPath: projectState.path,
    genre: projectState.genre,
    startDate: projectState.startedAt,
    endDate: now(),
    durationSeconds: now() - projectState.startedAt,
    phases: projectState.totalPhases,
    phasesCompleted: countCompleted(projectState.phaseHistory),
    phasesEscalated: countEscalated(projectState.phaseHistory),
    totalErrors: length(projectState.errorLog),
    totalRetries: sumRetries(projectState.phaseHistory),
    modelUsage: readJSON(projectState.path + "/.plan/model-usage.json").models,
    totalCostUsd: readJSON(projectState.path + "/.plan/model-usage.json").totalCostUsd,
    learnings: extractLearnings(projectState.learnings),
    qualityRating: null,     // wird durch Feedback-System gefüllt
    feedback: null,
    finalBuildPath: projectState.path + "/Builds/",
    success: allPhasesCompleted(projectState)
  }

  projects.projects.push(entry)
  updateAggregate(projects)
  writeJSON("workspace/memory/gamedev-projects.json", projects)
```

## Pattern Library

### Datei: `workspace/memory/gamedev-patterns.json`

Schema (siehe `templates/gamedev-patterns.json`):

```json
{
  "schemaVersion": 1,
  "patterns": {
    "vehicle-physics": {
      "category": "physics",
      "description": "Fahrzeug-Physik mit WheelColliders",
      "prompt": "Nutze WheelCollider mit Rigidbody auf Parent-GameObject. Stelle sicher dass Mass >= 1000, Suspension Distance 0.3, und Center of Mass nach unten verschoben ist.",
      "successRate": 0.8,
      "timesUsed": 3,
      "lastUsed": "2026-04-10T10:30:00Z",
      "appliesToGenres": ["driving-game"],
      "relatedFiles": ["VehicleController.cs"],
      "knownPitfalls": [
        "Ohne Parent-Rigidbody fällt Auto durch Boden",
        "Center of Mass zu hoch → Auto kippt"
      ]
    },
    "camera-follow": {
      "category": "gamelogic",
      "description": "Smooth-Follow Kamera",
      "prompt": "Nutze Cinemachine Virtual Camera mit Follow-Target. Dead Zone 0.1, Soft Zone 0.3, Damping 1.5.",
      "successRate": 1.0,
      "timesUsed": 5,
      "lastUsed": "2026-04-10T10:45:00Z",
      "appliesToGenres": ["platformer", "driving-game", "rpg"],
      "relatedFiles": [],
      "knownPitfalls": []
    }
  },
  "categoryIndex": {
    "physics": ["vehicle-physics"],
    "gamelogic": ["camera-follow"]
  }
}
```

### Pattern-Update-Workflow

Nach Phase-Abschluss:

```
FUNKTION: updatePattern(patternKey, success)

  lib = readJSON("workspace/memory/gamedev-patterns.json")

  IF NOT lib.patterns[patternKey] EXISTS:
    RETURN   // nur bekannte Patterns werden getrackt

  p = lib.patterns[patternKey]
  oldRate = p.successRate
  oldCount = p.timesUsed
  newCount = oldCount + 1

  // Running average:
  newRate = (oldRate * oldCount + (success ? 1 : 0)) / newCount

  p.successRate = newRate
  p.timesUsed = newCount
  p.lastUsed = now()

  writeJSON("workspace/memory/gamedev-patterns.json", lib)
```

### Pattern-Discovery (optional, Phase 2)

Wenn ein Fehler nach 2+ Retries mit einem bestimmten Prompt-Muster
gelöst wird, kann ein neuer Pattern-Vorschlag erstellt werden
(Status: `suggested`, nicht `active`), den der User bestätigen kann.

## Nutzung der Learnings im Planning

In der Planungsphase (`pipeline/planning-phase.md`) wird der System-Prompt
für Günther um Kontext aus Ebene 2/3 erweitert:

```
FUNKTION: buildPlannerContext(genre)

  lib = readJSON("workspace/memory/gamedev-patterns.json")
  projects = readJSON("workspace/memory/gamedev-projects.json")

  // Top-Patterns für dieses Genre (successRate >= 0.7, timesUsed >= 2)
  relevantPatterns = lib.patterns
    | filter(p => p.appliesToGenres.contains(genre))
    | filter(p => p.successRate >= 0.7 AND p.timesUsed >= 2)
    | sortBy(p => p.successRate DESC)
    | take(5)

  // Top-Learnings aus letzten 3 Projekten gleichen Genres
  recentLearnings = projects.projects
    | filter(p => p.genre == genre)
    | sortBy(p => p.endDate DESC)
    | take(3)
    | flatMap(p => p.learnings)
    | unique()
    | take(10)

  RETURN {
    patterns: relevantPatterns,
    learnings: recentLearnings
  }
```

Dieser Kontext wird in den Architect-Prompt injiziert:
```
"Basierend auf vergangenen Projekten:
 - Nutze immer Cinemachine statt eigenem Camera-Code
 - WheelCollider braucht Parent-Rigidbody
 - TextMeshPro statt legacy Text-Komponente
 Berücksichtige das bei deinem Plan."
```

## Datenschutz / Robustheit

- **Keine User-Daten**: Nur technische Patterns, keine persönlichen Infos.
- **Atomic Writes**: Alle Memory-Writes via `tmp → File.Replace` (wie
  `AutoCompileWatcher`), damit bei Absturz nichts korrupt ist.
- **Lockfile**: Vor jedem Write wird `config.memory.lockFile` per
  `O_CREAT | O_EXCL` erstellt (flock-Semantik). Wird beim Write
  gehalten, danach gelöscht. Bei Stale-Lock (>30s alt) darf überschrieben
  werden (TTL-basiert, keine harte Deadlock-Gefahr für Single-User).
- **Schema-Versioning**: `schemaVersion` in allen Memory-Dateien; beim
  Start prüft der Orchestrator `readVersion == config.memory.schemaVersion`.
  Bei Abweichung: Migration-Script in
  `workspace/skills/game-dev-orchestrator/tools/migrate-memory.sh`
  (wenn vorhanden) wird aufgerufen, sonst Fehler ins Log und User
  wird per Telegram informiert. Keine automatische Schreib-Korruption.
- **Size-Limit**: `projects.projects` wird bei >100 Einträgen auf die
  letzten 100 gekürzt (FIFO), ältere in `gamedev-projects-archive.json`
  ausgelagert.
- **Idempotenz**: Project-Namen sind eindeutig; zweites Archivieren
  desselben Namens aktualisiert den bestehenden Eintrag, fügt keinen
  neuen hinzu.

## Integration in State Machine

Neue Zustandsübergänge:

```
COMPLETE → ARCHIVING  (nach Build-Erfolg)
ARCHIVING → AWAITING_FEEDBACK  (siehe user-feedback.md)
AWAITING_FEEDBACK → DONE  (nach User-Rating oder Timeout 24h)
```

Im `ARCHIVING`-Schritt:
1. `archiveProject(state)` aufrufen
2. Für jeden genutzten Pattern: `updatePattern(key, success)`
3. Gesamt-Aggregate neu berechnen

## Schwachstellen / Edge Cases

- **Leeres Memory beim ersten Lauf**: Dateien werden beim Start lazy
  aus `templates/` kopiert, wenn sie fehlen.
- **Concurrent Writes**: Nur ein Orchestrator-Prozess schreibt; kein
  Lock nötig. Falls doch: Lockfile `workspace/memory/.lock`.
- **Pattern-Drift**: Wenn `successRate` dauerhaft unter 0.3 fällt, wird
  Pattern automatisch auf `deprecated: true` markiert und nicht mehr
  vorgeschlagen.
