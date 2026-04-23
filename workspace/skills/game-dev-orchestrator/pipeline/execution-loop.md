# Ausführungsschleife (Execution Loop)

## Übersicht

Die Ausführungsschleife ist der Kern des Systems. Sie arbeitet Phase für
Phase den Master-Plan ab. Für jede Phase wird:
1. Kontext gesammelt
2. Günther nach finalisiertem Prompt gefragt
3. Prompt an den Copilot injiziert
4. Ergebnis verifiziert
5. Bei Fehler: Korrektur-Schleife

## Haupt-Ausführungsfunktion

```
FUNKTION: executePhase(phaseId, projectPath, masterPlan)

  phase = masterPlan.phases[phaseId - 1]

  // ── 1. Kontext sammeln ──────────────────────────────────────
  context = scanProject(projectPath)        // Siehe context-management.md
  existingFiles = getRelevantFiles(context, phase)
  previousErrors = getPhaseErrors(phaseId)

  // ── 2. Finalisierten Prompt von Günther holen ───────────────
  phaseTransitionPrompt = readFile("prompts/phase-transition.txt")

  guentherRequest = fillTemplate(phaseTransitionPrompt, {
    "N": phaseId - 1,           // abgeschlossene Phase
    "N+1": phaseId,             // neue Phase
    "fileList": context.scripts.map(s => s.path),
    "problems": previousErrors,
    "codeLines": context.totalLines,
    "phaseDescription": phase.description,
    "expectedFiles": phase.expectedFiles
  })

  finalPrompt = askGuenther(
    system: readFile("prompts/architect-system.txt"),
    user: guentherRequest
  )

  copilotPrompt = finalPrompt.detailedPrompt
  contextFiles = finalPrompt.contextFiles
  newFiles = finalPrompt.newFiles
  modifiedFiles = finalPrompt.modifiedFiles

  // ── 3. Copilot-Prompt protokollieren ────────────────────────
  logCopilotPrompt(phaseId, copilotPrompt, contextFiles)

  // ── 4. Modell-Auswahl (Teil G, Schritt 22) ─────────────────
  // Spezifiziert in: pipeline/model-routing.md
  // Entscheidet auf Basis von:
  //   a) config.modelRouting.overrides[phaseId]
  //   b) retryCount >= config.modelRouting.escalateAtRetry → Opus
  //   c) phase.category → config.modelRouting.categoryMap
  //   d) Keyword-Scoring über phase.name + copilotPrompt
  //   e) Fallback: config.modelRouting.defaultModel (sonnet)
  model = selectModel(phase, currentPhase.retryCount)
  logRoutingDecision(phaseId, model, decisionReason)   // in .plan/model-usage.json

  // ── 4b. Pattern-Detection (Teil G, Schritt 23) ─────────────
  // Extrahiere verwendete Patterns aus dem finalisierten Prompt.
  // Ein "Pattern-Use" wird gezählt wenn der Prompt eines der
  // Schlüsselwörter aus workspace/memory/gamedev-patterns.json
  // (description oder prompt-Auszüge) referenziert.
  usedPatterns = detectUsedPatterns(copilotPrompt)
  appendUsedPatterns(projectPath, phaseId, usedPatterns)
  // → .plan/used-patterns.json wird pro Phase ergänzt

  // ── 5. VS Code Bridge: Code generieren ─────────────────────
  FOR EACH targetFile IN (newFiles + modifiedFiles):

    // a) Datei erstellen mit Prompt-Kommentar
    promptHeader = buildPromptHeader(copilotPrompt, phase, targetFile)
    writeFile(projectPath + "/" + targetFile, promptHeader)

    // b) Datei in VS Code öffnen
    exec("code --goto " + projectPath + "/" + targetFile + ":1")
    wait(2000)

    // c) Copilot-Injection (je nach Methode)
    IF config.automation.method == "file-based":
      // Copilot liest den Kommentar-Block und generiert
      // User muss ggf. Tab/Enter drücken oder es passiert automatisch
      // via Copilot Agent Mode
      waitForFileChange(targetFile, config.phases.copilotWaitSeconds)

    ELSE IF config.automation.method == "xdotool":
      // Linux UI-Automation
      injectViaXdotool(copilotPrompt)
      waitForFileChange(targetFile, config.phases.copilotWaitSeconds)
    END IF

    // d) Code bereinigen
    cleanGeneratedCode(projectPath + "/" + targetFile)

  END FOR

  // ── 6. current-phase.json aktualisieren ────────────────────
  updateCurrentPhase({
    "currentPhaseId": phaseId,
    "currentPhaseName": phase.name,
    "status": "testing",
    "attempt": 1,
    "copilotModel": model,
    "promptSent": copilotPrompt,
    "filesCreated": newFiles,
    "filesModified": modifiedFiles
  })

  RETURN "VERIFYING"

ENDE
```

## Prompt-Header Builder

Der Prompt-Header ist der Kommentar-Block der an den Anfang jeder
Zieldatei geschrieben wird. Er dient als Anweisung für den Copilot.

```
FUNKTION: buildPromptHeader(prompt, phase, targetFile)

  extension = getFileExtension(targetFile)

  IF extension == ".cs":
    RETURN """
/*
 * ══════════════════════════════════════════════════════════════
 * AUTOMATISCH GENERIERT - Game Dev Orchestrator
 * Phase: {phase.id}/10 - {phase.name}
 * Datei: {targetFile}
 * ══════════════════════════════════════════════════════════════
 *
 * AUFGABE:
 * {prompt}
 *
 * TECHNISCHE ANFORDERUNGEN:
 * - Unity 2022.3 LTS mit URP
 * - C# 9.0+ (.NET Standard 2.1)
 * - Namespace: GameName.{getNamespace(targetFile)}
 *
 * ABHÄNGIGKEITEN:
 * {listDependencies(phase)}
 *
 * WICHTIG:
 * - Schreibe vollständigen, kompilierbaren C#-Code
 * - Alle using-Statements am Anfang
 * - Keine Platzhalter oder TODOs
 * - Keine Markdown-Codeblöcke
 * ══════════════════════════════════════════════════════════════
 */

using UnityEngine;

// Implementierung beginnt hier:

"""
  END IF

ENDE
```

## Smart Wait: Auf Copilot-Ergebnis warten

```
FUNKTION: waitForFileChange(filePath, timeoutSeconds)

  startTime = now()
  initialSize = getFileSize(filePath)
  initialHash = getFileHash(filePath)
  lastChangeTime = null

  WHILE (now() - startTime) < timeoutSeconds:

    currentSize = getFileSize(filePath)
    currentHash = getFileHash(filePath)

    IF currentHash != initialHash:
      // Datei hat sich geändert
      lastChangeTime = now()
      initialHash = currentHash

      // Warte noch 5 Sekunden - Copilot könnte noch schreiben
      wait(5000)

      // Prüfe ob sich nochmal was geändert hat
      IF getFileHash(filePath) == currentHash:
        // Keine weitere Änderung → Copilot ist fertig
        RETURN "changed"
      END IF
    END IF

    wait(config.phases.pollingIntervalSeconds * 1000)

  END WHILE

  // Timeout erreicht
  IF lastChangeTime != null:
    // Es gab Änderungen, möglicherweise unvollständig
    RETURN "partial"
  END IF

  RETURN "timeout"

ENDE
```

## Code-Bereinigung

```
FUNKTION: cleanGeneratedCode(filePath)

  content = readFile(filePath)

  // 1. Markdown-Codeblöcke entfernen
  // Manchmal fügt der Copilot ```csharp ... ``` ein
  IF content CONTAINS "```":
    // Extrahiere Code zwischen ``` Blöcken
    matches = regex.findAll(content, /```(?:csharp|cs)?\n([\s\S]*?)```/)
    IF matches.length > 0:
      content = matches.map(m => m.group(1)).join("\n\n")
    END IF
  END IF

  // 2. Doppelte using-Statements entfernen
  lines = content.split("\n")
  usings = []
  otherLines = []
  FOR EACH line IN lines:
    IF line.startsWith("using ") AND line.endsWith(";"):
      IF line NOT IN usings:
        usings.push(line)
      END IF
    ELSE:
      otherLines.push(line)
    END IF
  END FOR
  content = usings.join("\n") + "\n\n" + otherLines.join("\n")

  // 3. Doppelte Klassen-Definitionen erkennen
  classMatches = regex.findAll(content, /class\s+(\w+)/)
  classNames = classMatches.map(m => m.group(1))
  IF hasDuplicates(classNames):
    warn("WARNUNG: Doppelte Klassen-Definition in " + filePath)
    // Nur die erste behalten
    // TODO: Intelligenteres Merging
  END IF

  // 4. Klammerbalancierung prüfen
  openBraces = count(content, "{")
  closeBraces = count(content, "}")
  IF openBraces != closeBraces:
    warn("WARNUNG: Unbalancierte Klammern in " + filePath)
    // Versuche zu reparieren
    IF openBraces > closeBraces:
      content += "\n" + "}".repeat(openBraces - closeBraces)
    END IF
  END IF

  // 5. Leere Datei-Check
  codeContent = content.replace(/\/\*[\s\S]*?\*\//g, "")  // Kommentare entfernen
                       .replace(/\/\/.*/g, "")              // Einzeiler-Kommentare
                       .trim()
  IF codeContent.length < 20:
    RETURN "empty"  // Copilot hat keinen Code generiert
  END IF

  // 6. Bereinigten Code speichern
  writeFile(filePath, content)
  RETURN "ok"

ENDE
```

## Kontext-Aggregation pro Phase

Die Menge an Kontext die an Günther und den Copilot gegeben wird,
variiert je nach Phase-Fortschritt:

```
FUNKTION: getRelevantFiles(projectContext, phase)

  allScripts = projectContext.scripts
  phaseId = phase.id

  // Phase 1-3: Wenig Code, alles mitgeben
  IF phaseId <= 3:
    RETURN allScripts.map(s => {
      path: s.path,
      content: readFile(s.path)    // Vollständiger Inhalt
    })
  END IF

  // Phase 4-7: Relevante Dateien komplett, Rest als Summary
  IF phaseId <= 7:
    relevant = phase.dependencies.flatMap(dep =>
      allScripts.filter(s => s.path CONTAINS dep)
    )
    // Plus die Dateien die in dieser Phase geändert werden
    relevant.push(...allScripts.filter(s =>
      phase.expectedFiles.some(f => s.path CONTAINS f)
    ))

    RETURN allScripts.map(s => {
      IF s IN relevant:
        RETURN { path: s.path, content: readFile(s.path) }
      ELSE:
        RETURN { path: s.path, summary: summarizeFile(s) }
      END IF
    })
  END IF

  // Phase 8-10: Nur aktuelle Datei + Interfaces
  RETURN phase.expectedFiles.map(f => {
    path: f,
    content: fileExists(f) ? readFile(f) : ""
  }).concat(
    allScripts.filter(s => s.publicMethods.length > 0).map(s => {
      path: s.path,
      summary: "Klassen: " + s.classes.join(", ") +
               " | Methoden: " + s.publicMethods.join(", ")
    })
  )

ENDE
```

## Datei-Summary-Generator

```
FUNKTION: summarizeFile(scriptInfo)

  RETURN """
  // ── {scriptInfo.path} ({scriptInfo.lines} Zeilen) ──
  // Klassen: {scriptInfo.classes.join(", ")}
  // Public Methoden: {scriptInfo.publicMethods.join(", ")}
  // Abhängigkeiten: {scriptInfo.dependencies.join(", ")}
  """

ENDE
```

## Timing-Management

### Erwartete Zeiten pro Phase

| Aktion                    | Idealfall | Realistisch | Timeout   |
|---------------------------|-----------|-------------|-----------|
| Günther-Anfrage           | 5-10s     | 10-30s      | 60s       |
| Datei-Vorbereitung        | 1-2s      | 2-5s        | 10s       |
| Copilot-Injection         | 2-5s      | 5-15s       | 30s       |
| Copilot-Generierung       | 15-60s    | 30-120s     | 300s      |
| Unity-Kompilierung        | 5-15s     | 10-30s      | 120s      |
| Status-Check              | 1-2s      | 2-5s        | 10s       |
| **Gesamt pro Phase**      | **~40s**  | **~2-3min** | **~9min** |

### Gesamt-Projekt Schätzung

| Szenario    | 10 Phasen        | Mit Fehlern         |
|-------------|------------------|---------------------|
| Ideal       | ~7 Minuten       | ~15 Minuten         |
| Realistisch | ~25 Minuten      | ~45-90 Minuten      |
| Worst Case  | ~90 Minuten      | ~2-3 Stunden        |

## Git-Commit pro Phase

Nach jeder erfolgreichen Phase macht Hans einen Git-Commit:

```
FUNKTION: commitPhase(phaseId, phaseName, filesChanged)

  exec("cd " + projectPath)
  exec("git add -A")
  exec('git commit -m "✅ Phase ' + phaseId + '/10: ' + phaseName + '"')

  // Optional: Tag für wichtige Meilensteine
  IF phaseId IN [1, 5, 10]:
    exec('git tag -a "phase-' + phaseId + '" -m "' + phaseName + '"')
  END IF

ENDE
```

## Copilot-Prompt-Log

Alle an den Copilot gesendeten Prompts werden protokolliert:

Datei: `.plan/copilot-prompts.json`

```json
{
  "prompts": [
    {
      "phaseId": 1,
      "attempt": 1,
      "timestamp": "2026-04-10T14:05:00Z",
      "model": "claude-sonnet-4.6",
      "targetFile": "Assets/Scripts/Core/GameManager.cs",
      "prompt": "...",
      "resultStatus": "success",
      "codeLines": 85
    }
  ]
}
```

## Pattern-Detection (Teil G, Schritt 23)

Während der Ausführung wird getrackt welche Library-Patterns verwendet
wurden. Jedes Pattern in `gamedev-patterns.json` hat ein `keywords[]`-Feld
mit kurzen, hochspezifischen Begriffen (z.B. `["cinemachine", "virtual camera"]`).

```
FUNKTION: detectUsedPatterns(copilotPrompt)

  patternLib = readJSON(config.memory.patternsFile)
  promptLc = copilotPrompt.toLowerCase()

  used = []

  FOR EACH key, pattern IN patternLib.patterns:
    IF pattern.deprecated == true: CONTINUE

    FOR EACH kw IN (pattern.keywords OR []):
      IF promptLc.contains(kw.toLowerCase()):
        used.push(key); BREAK
      END IF
    END FOR
  END FOR

  RETURN uniqueKeys(used)

ENDE

FUNKTION: appendUsedPatterns(projectPath, phaseId, usedKeys)

  file = projectPath + "/.plan/used-patterns.json"
  data = fileExists(file) ? readJSON(file) : { "phases": {}, "aggregate": [] }

  data.phases[phaseId] = usedKeys
  data.aggregate = unique(flatten(values(data.phases)))

  writeJSON_atomic(file, data)   // .tmp + File.Replace
```

## Routing-Decision-Log (Teil G, Schritt 22)

```
FUNKTION: logRoutingDecision(phaseId, chosenModel, reason)

  file = projectPath + "/.plan/model-usage.json"
  usage = fileExists(file) ? readJSON(file)
                           : readJSON("templates/model-usage.json")

  usage.decisions.push({
    "phaseId": phaseId,
    "model": chosenModel,
    "reason": reason,                 // "override"|"retry-escalation"|"category"|"keyword-score"|"default"
    "timestamp": now()
  })
  usage.lastUpdate = now()
  writeJSON_atomic(file, usage)
```
