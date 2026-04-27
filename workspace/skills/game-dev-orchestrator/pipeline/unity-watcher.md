# Unity Watcher (Teil I)

Quelle: `AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt` → Teil I, Schritte 28 + 29.

Der Unity-Watcher ist die Brücke zwischen dem Unity Editor (oder einem
Batchmode-Run) und Hans' Pipeline. Er liefert die zwei einzigen
Dateien, die Hans aktiv beobachtet:

- `.plan/unity-status.json` – aktueller Zustand (überschrieben, atomar)
- `.plan/error-log.jsonl`   – Append-Only NDJSON, eine Zeile je Fehler

Das Editor-Script (`templates/AutoCompileWatcher.cs.txt`) wird vom
`project-initializer` (siehe [project-init.md](./project-init.md)) in
jedes neue Projekt nach `Assets/Editor/AutoCompileWatcher.cs` kopiert.

## Datenmodell

### `unity-status.json`

```json
{
  "status":       "idle | compiling | success | error | runtime-error",
  "message":      "string (max ~500 Zeichen)",
  "timestamp":    "ISO-8601 UTC, z.B. 2026-04-27T10:15:30.123Z",
  "phaseId":      1,
  "project":      "string (aus current-phase.json.project)",
  "compileCount": 0,
  "errorCount":   0
}
```

Felder:
- `status` – Pflichtfeld, einer der genannten Werte. `failed` und
  `timeout` werden zusätzlich von Batchmode-Fallback (Schritt 29) erzeugt.
- `phaseId` – `null` falls `.plan/current-phase.json` (noch) nicht existiert.
- `project` – leerer String wenn unbekannt.
- `compileCount` – kumuliert pro Editor-Session.
- `errorCount` – nicht akkumuliert über Sessions, sondern letzte Compile-Welle.

Schema-Datei: `tests/fixtures/unity-status.schema.json` (siehe Suite 22 in
`tests/run-tests.sh`).

### `error-log.jsonl`

Eine Zeile pro Eintrag, NDJSON:

```json
{"timestamp":"2026-04-27T10:15:30.123Z","phaseId":3,"project":"CatDriver",
 "type":"Error","message":"CS0246: ...","stackTrace":"",
 "file":"Assets/Scripts/Camera/CameraController.cs","line":12}
```

Feld-Konventionen:
- `type` ∈ `Error`, `Exception`, `Warning` (Warnings nur falls explizit
  aktiviert – siehe Schritt 30).
- `file` ist projekt-relativ (`Assets/...`), oder leerer String.
- `line` ist Integer; `0` falls unbekannt.

Schema-Datei: `tests/fixtures/error-log-entry.schema.json`.

## Lese-Strategie für Hans

```
FUNKTION readUnityStatus(projectPath, sinceMs):
  status = readJson(projectPath + "/.plan/unity-status.json")
  newErrors = tailJsonl(
    projectPath + "/.plan/error-log.jsonl",
    sinceTimestamp = sinceMs
  )
  RETURN { status, newErrors }
ENDE
```

`tailJsonl` liest ab dem zuletzt gemerkten Byte-Offset (gespeichert in
`orchestrator-state.json.unityWatcherCursor`) und gibt nur neue Zeilen
zurück. Das ist O(1) bei jedem Poll, auch wenn die Logdatei wächst.

## Atomare Writes

`AutoCompileWatcher.WriteStatus(...)` schreibt immer in
`unity-status.json.tmp` und ruft danach `File.Replace`. Damit kann Hans
niemals eine halbfertige Datei lesen (Schwachstelle #12 aus Teil F).

`AppendErrorEntry(...)` öffnet die Datei mit
`FileShare.Read` und schließt jede Zeile mit `\n` – Append ist auf allen
gängigen Filesystemen für POSIX-Writes < 4 KiB atomar.

## Polling

- Hans pollt `unity-status.json` alle `phases.pollingIntervalSeconds`
  (default `3 s`) – siehe `gamedev-config.json`.
- Bei Statuswechsel `compiling → success|error` triggert die
  Pipeline `onVerifyPhase()` (siehe
  [error-correction.md](./error-correction.md) Sektion *Wiring*).

## Batchmode (Schritt 29)

Wenn der User Unity nicht laufen hat, würde der Editor-Watcher keine
Events liefern. Für diesen Fall startet Hans Unity selbst im Batchmode.

### `compileOnce(projectPath)` Algorithmus

```
FUNKTION compileOnce(projectPath):
  cfg = readConfig().unity

  // 1. Editor läuft mit dem Projekt?
  IF unityEditorRunsWithProject(projectPath):
    waitForStatusChange(timeoutSeconds = cfg.compileTimeoutSeconds)
    RETURN readJson(cfg.statusFile)
  END IF

  // 2. Sonst Batchmode triggern.
  logFile = projectPath + "/" + cfg.batchLogFile  // z.B. .plan/unity-batch.log
  exec(
    cfg.editorBinary,
    "-batchmode -nographics -quit",
    "-projectPath", projectPath,
    "-logFile",    logFile,
    "-executeMethod", "OpenClaw.BatchCompile.Run",
    timeoutSeconds = cfg.compileTimeoutSeconds
  )

  // 3. Log parsen.
  parsed = parseBatchLog(logFile)
  // parsed = { errorCount, status, errors[], succeeded }

  // 4. Synthetisches unity-status.json schreiben (damit der Rest
  //    der Pipeline nichts vom Batchmode wissen muss).
  writeJsonAtomic(cfg.statusFile, {
    status:      parsed.status,        // success | error | timeout | failed
    message:     parsed.message,
    timestamp:   nowIso8601(),
    phaseId:     readCurrentPhaseId(projectPath),
    project:     readCurrentProject(projectPath),
    compileCount: 1,
    errorCount:  parsed.errorCount
  })

  // 5. Fehler in error-log.jsonl appenden (eine Zeile pro Fehler).
  FOR EACH e IN parsed.errors:
    appendJsonLine(cfg.errorLogFile, {
      timestamp: nowIso8601(),
      phaseId:   readCurrentPhaseId(projectPath),
      project:   readCurrentProject(projectPath),
      type:      "Error",
      message:   e.message,
      stackTrace: "",
      file:      e.file || "",
      line:      e.line || 0
    })
  END FOR

  RETURN parsed
ENDE
```

### Log-Parser

`parseBatchLog` arbeitet streng zeilenbasiert, damit dasselbe Skript für
alle Unity-Versionen 2021–6 funktioniert.

Erkennungs-Pattern:
- `error CS\d{4}` → Compile-Error. `errorCount++`,
  `status = "error"`. Datei/Zeile aus dem Präfix
  `(Assets/.../File.cs:12,5):` extrahieren.
- `Compilation succeeded` *oder* `Scripts have compiled successfully` →
  `status = "success"`.
- `Aborting batchmode due to failure` → `status = "failed"`.
- Kein passender Marker innerhalb von `compileTimeoutSeconds` →
  `status = "timeout"`.

### Konfiguration (Auszug aus `gamedev-config.json`)

```json
{
  "unity": {
    "version": "2022.3",
    "renderPipeline": "URP",
    "buildTarget": "StandaloneLinux64",
    "batchModeFlags": "-batchmode -nographics -quit",
    "mode":   "auto",
    "editorBinary": "",
    "batchLogFile": ".plan/unity-batch.log",
    "statusFile":   ".plan/unity-status.json",
    "errorLogFile": ".plan/error-log.jsonl",
    "compileTimeoutSeconds": 180
  }
}
```

`mode`-Werte:
- `editor` – Watcher only, niemals Batchmode anstoßen (für lokale Devs).
- `batch`  – immer Batchmode (CI/Server-Setups).
- `auto`   – wie oben beschrieben (Default).

`editorBinary` ist der absolute Pfad zur Unity-Binary; falls leer, sucht
Hans der Reihe nach in:
1. `$UNITY_EDITOR_BINARY` (Env-Var)
2. `~/Unity/Hub/Editor/<unity.version>*/Editor/Unity`
3. `/Applications/Unity/Hub/Editor/<unity.version>*/Unity.app/Contents/MacOS/Unity`
4. `which unity-editor`

## Verzahnung mit der State-Machine

```
EXECUTING ──► VERIFYING
                 │
                 ▼
            onVerifyPhase()        ◄── nutzt readUnityStatus()
                 │
        ┌────────┴─────────┐
        ▼                  ▼
   PHASE_DONE        CORRECTING (siehe error-correction.md)
```

Details: [error-correction.md – Sektion *Wiring*](./error-correction.md#wiring-unity-→-hans-→-günther).
