# Fehler-Korrektur-System (Error Correction)

## Übersicht

Das Fehler-Korrektur-System ist das "Self-Healing"-Modul der Pipeline.
Es erkennt, klassifiziert und behebt Fehler automatisch. Nur wenn alle
automatischen Versuche scheitern, wird der User einbezogen.

## Fehler-Klassifizierung

### Algorithmus

```
FUNKTION: classifyError(errorMessage)

  error = {
    raw: errorMessage,
    type: "UNKNOWN",
    severity: "UNKNOWN",
    category: "",
    quickFixPossible: false
  }

  // ── CRITICAL: Kompilierungsfehler ──────────────────────────
  IF errorMessage MATCHES /CS\d{4}/:
    error.type = "COMPILATION"
    error.severity = "CRITICAL"
    error.category = extractCSCode(errorMessage)  // z.B. "CS0246"

    // Bekannte Fehler mit Quick-Fix
    SWITCH error.category:
      CASE "CS0246":  // Type or namespace not found
        error.quickFixPossible = true
        error.quickFix = "using-Statement hinzufügen"

      CASE "CS1061":  // Does not contain a definition for
        error.quickFixPossible = true
        error.quickFix = "Methodenname korrigieren oder API prüfen"

      CASE "CS0029":  // Cannot implicitly convert type
        error.quickFixPossible = true
        error.quickFix = "Typ-Cast hinzufügen oder Variable-Typ ändern"

      CASE "CS0103":  // Name does not exist in current context
        error.quickFixPossible = true
        error.quickFix = "Variable deklarieren oder Scope prüfen"

      CASE "CS0117":  // Does not contain a definition for (static)
        error.quickFixPossible = true
        error.quickFix = "Statische Methode/Property prüfen"

      CASE "CS0234":  // Namespace does not exist
        error.quickFixPossible = true
        error.quickFix = "Package installieren oder Namespace korrigieren"

      DEFAULT:
        error.quickFixPossible = false
    END SWITCH
  END IF

  // ── MAJOR: Runtime-Fehler ──────────────────────────────────
  IF errorMessage CONTAINS "NullReferenceException":
    error.type = "RUNTIME"
    error.severity = "MAJOR"
    error.category = "NullReference"
    error.quickFixPossible = true
    error.quickFix = "Null-Checks hinzufügen, GetComponent<> prüfen"
  END IF

  IF errorMessage CONTAINS "MissingComponentException":
    error.type = "RUNTIME"
    error.severity = "MAJOR"
    error.category = "MissingComponent"
    error.quickFixPossible = true
    error.quickFix = "[RequireComponent] Attribut hinzufügen"
  END IF

  IF errorMessage CONTAINS "IndexOutOfRangeException":
    error.type = "RUNTIME"
    error.severity = "MAJOR"
    error.category = "IndexOutOfRange"
    error.quickFixPossible = true
    error.quickFix = "Array-Bounds prüfen, .Length/.Count verwenden"
  END IF

  IF errorMessage CONTAINS "StackOverflowException":
    error.type = "RUNTIME"
    error.severity = "CRITICAL"
    error.category = "StackOverflow"
    error.quickFixPossible = false
    // Braucht tiefe Analyse → Günther
  END IF

  IF errorMessage CONTAINS "InvalidOperationException":
    error.type = "RUNTIME"
    error.severity = "MAJOR"
    error.category = "InvalidOperation"
    error.quickFixPossible = false
  END IF

  // ── MINOR: Warnungen ──────────────────────────────────────
  IF errorMessage MATCHES /warning\s+CS\d{4}/i:
    error.type = "WARNING"
    error.severity = "MINOR"
    error.category = "CompilerWarning"
    error.quickFixPossible = false  // Nicht zwingend beheben
  END IF

  IF errorMessage CONTAINS "obsolete" OR errorMessage CONTAINS "deprecated":
    error.type = "WARNING"
    error.severity = "MINOR"
    error.category = "Deprecated"
  END IF

  // ── UNITY-SPEZIFISCH ─────────────────────────────────────
  IF errorMessage CONTAINS "can only be called from the main thread":
    error.type = "RUNTIME"
    error.severity = "CRITICAL"
    error.category = "MainThread"
    error.quickFixPossible = false
    // Braucht Code-Umstrukturierung
  END IF

  IF errorMessage CONTAINS "SerializationException":
    error.type = "RUNTIME"
    error.severity = "MAJOR"
    error.category = "Serialization"
    error.quickFixPossible = true
    error.quickFix = "[Serializable] Attribut oder [SerializeField] hinzufügen"
  END IF

  RETURN error

ENDE
```

## Retry-Strategie (5 Stufen)

### Versuch 1: Gleicher Prompt, gleiches Modell

```
FUNKTION: retryLevel1(error, sourceCode, fileName)

  prompt = """
  Der folgende Code hat einen Fehler.

  Datei: {fileName}
  Fehler: {error.raw}
  Zeile: {error.line} (falls bekannt)

  Aktueller Code:
  ```csharp
  {sourceCode}
  ```

  Bitte korrigiere NUR den Fehler. Schreibe den vollständigen,
  korrigierten Code der gesamten Datei.
  """

  model = config.models.coderDefault  // Sonnet 4.6
  RETURN { prompt, model, strategy: "simple-retry" }

ENDE
```

### Versuch 2: Erweiterter Prompt mit Fehler-Kontext

```
FUNKTION: retryLevel2(error, sourceCode, fileName, previousAttempt)

  // Günther um Fehleranalyse bitten
  analysis = askGuentherForErrorAnalysis(error, sourceCode)

  prompt = """
  WICHTIG: Der vorherige Korrekturversuch hat NICHT funktioniert.

  ORIGINAL FEHLER: {previousAttempt.error}
  VERSUCHTE KORREKTUR: {previousAttempt.prompt}
  NEUER/GLEICHER FEHLER: {error.raw}

  ANALYSE DES ARCHITEKTEN:
  - Ursache: {analysis.rootCause}
  - Empfehlung: {analysis.correctionPrompt}

  Aktueller Code:
  ```csharp
  {sourceCode}
  ```

  AUFGABE: Korrigiere den Fehler basierend auf der Analyse oben.
  Schreibe den VOLLSTÄNDIGEN, korrigierten Code der gesamten Datei.
  Stelle sicher, dass ALLE using-Statements vorhanden sind.
  """

  model = config.models.coderDefault  // Sonnet 4.6
  RETURN { prompt, model, strategy: "analyzed-retry" }

ENDE
```

### Versuch 3: Modell-Upgrade (Sonnet → Opus)

```
FUNKTION: retryLevel3(error, sourceCode, fileName, errorHistory)

  prompt = """
  ⚠️ SCHWIERIGER FEHLER - Bereits 2x nicht behoben!

  FEHLERHISTORIE:
  1. Versuch: {errorHistory[0].error} → {errorHistory[0].fix} → FEHLGESCHLAGEN
  2. Versuch: {errorHistory[1].error} → {errorHistory[1].fix} → FEHLGESCHLAGEN

  AKTUELLER FEHLER: {error.raw}
  DATEI: {fileName}

  AKTUELLER CODE:
  ```csharp
  {sourceCode}
  ```

  AUFGABE:
  Du bist ein erfahrener Unity C# Entwickler. Dieser Fehler konnte
  bereits 2x nicht behoben werden. Analysiere die Fehlerhistorie
  sorgfältig und:
  1. Identifiziere die TATSÄCHLICHE Ursache
  2. Schreibe den GESAMTEN Code der Datei NEU und KORREKT
  3. Stelle sicher dass ALLE Abhängigkeiten korrekt sind
  4. Teste mental ob der Code kompiliert
  """

  model = config.models.coderComplex  // Opus (Upgrade!)
  RETURN { prompt, model, strategy: "model-upgrade" }

ENDE
```

### Versuch 4: Vereinfachter Ansatz

```
FUNKTION: retryLevel4(error, phase, fileName)

  // Günther um vereinfachten Ansatz bitten
  simplifiedApproach = askGuenther(
    "Phase {phase.id} ({phase.name}) scheitert nach 3 Versuchen.
     Letzter Fehler: {error.raw}
     Erstelle einen VEREINFACHTEN Ansatz:
     - Weniger Features
     - Einfachere Logik
     - Minimale Implementierung
     - Hauptsache es kompiliert und die Grundfunktion geht

     Antwort als JSON: {
       \"simplifiedPrompt\": \"...\",
       \"removedFeatures\": [\"...\"],
       \"reason\": \"...\"
     }"
  )

  prompt = simplifiedApproach.simplifiedPrompt +
    "\n\nWICHTIG: Diese Vereinfachung wurde bewusst gewählt. " +
    "Implementiere NUR das Beschriebene, nichts mehr."

  model = config.models.coderDefault  // Zurück zu Sonnet
  RETURN { prompt, model, strategy: "simplified" }

ENDE
```

### Versuch 5: Minimaler Code + User-Einbeziehung

```
FUNKTION: retryLevel5(error, phase, fileName)

  // Minimalen Stub erstellen der zumindest kompiliert
  prompt = """
  Erstelle einen MINIMALEN Stub für die Datei {fileName}.
  Der Code muss nur:
  1. Kompilieren (keine Fehler)
  2. Die Klasse und öffentlichen Methoden deklarieren
  3. Methoden können leer sein oder NotImplementedException werfen

  Dieser Stub dient als Platzhalter bis ein Mensch den echten Code schreibt.
  """

  model = config.models.coderQuick  // Haiku (schnell)
  RETURN { prompt, model, strategy: "minimal-stub" }

ENDE
```

## Haupt-Fehlerbehandlungs-Funktion

```
FUNKTION: handleError(error, sourceCode, fileName, phaseId, attempt)

  // 1. Fehler klassifizieren
  classified = classifyError(error.message)

  // 2. MINOR-Fehler ignorieren (nur loggen)
  IF classified.severity == "MINOR":
    logError(phaseId, error, "ignored")
    RETURN null  // Kein Korrektur-Prompt nötig
  END IF

  // 3. In Error-Log schreiben
  logError(phaseId, error, "attempting-fix", attempt)

  // 4. Passende Retry-Stufe wählen
  SWITCH attempt:
    CASE 1: correction = retryLevel1(error, sourceCode, fileName)
    CASE 2: correction = retryLevel2(error, sourceCode, fileName, getLastAttempt())
    CASE 3: correction = retryLevel3(error, sourceCode, fileName, getErrorHistory())
    CASE 4: correction = retryLevel4(error, phase, fileName)
    CASE 5: correction = retryLevel5(error, phase, fileName)
    DEFAULT: RETURN "MAX_RETRIES_EXCEEDED"
  END SWITCH

  // 5. User über Korrektur informieren
  notifyUser("🔧 Phase {phaseId}/10: Fehler gefunden, korrigiere... " +
             "Versuch {attempt}/{config.phases.maxRetriesPerPhase}")

  // 6. Korrektur-Info zurückgeben
  RETURN {
    prompt: correction.prompt,
    model: correction.model,
    strategy: correction.strategy,
    attempt: attempt
  }

ENDE
```

## Error-Log Format

Datei: `.plan/error-log.json`

```json
{
  "errors": [
    {
      "id": "err-001",
      "phaseId": 3,
      "attempt": 1,
      "timestamp": "2026-04-10T14:30:00Z",
      "type": "COMPILATION",
      "severity": "CRITICAL",
      "category": "CS0246",
      "message": "CS0246: The type or namespace name 'Cinemachine' could not be found",
      "file": "Assets/Scripts/Camera/CameraController.cs",
      "line": 5,
      "sourceCodeSnapshot": "using Cinemachine;\n...",
      "promptUsed": "Erstelle einen CameraController mit Cinemachine...",
      "modelUsed": "claude-sonnet-4.6",
      "strategy": "simple-retry",
      "resolution": "fixed",
      "resolutionDetails": "using-Statement korrigiert, Cinemachine Package war nicht importiert",
      "fixedAt": "2026-04-10T14:31:20Z"
    }
  ],
  "summary": {
    "totalErrors": 7,
    "fixed": 5,
    "ignored": 1,
    "escalatedToUser": 1,
    "byPhase": {
      "1": 0, "2": 2, "3": 3, "4": 1, "5": 1, "6": 0,
      "7": 0, "8": 0, "9": 0, "10": 0
    },
    "bySeverity": {
      "CRITICAL": 4,
      "MAJOR": 2,
      "MINOR": 1
    }
  }
}
```

## Incident Report (Nuclear Option)

Wenn nach 5 Versuchen nichts klappt:

```
FUNKTION: createIncidentReport(phaseId, phaseName, errorHistory)

  report = """
  ⚠️ PHASE {phaseId}/10 FEHLGESCHLAGEN: {phaseName}

  Alle 5 Korrekturversuche sind erschöpft.

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FEHLER-ZUSAMMENFASSUNG:
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  {FOR EACH entry IN errorHistory:}
  Versuch {entry.attempt}:
    Strategie: {entry.strategy}
    Modell: {entry.model}
    Fehler: {entry.error}
    Ergebnis: Fehlgeschlagen
  {END FOR}

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  LETZTER FEHLER:
  {errorHistory.last().error}

  BETROFFENE DATEI:
  {errorHistory.last().file}

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  WAS KANN ICH TUN?

  📌 /skip - Phase überspringen
  📌 /reset-phase - Phase komplett neu starten
  📌 /manual - Du übernimmst diese Phase
  📌 Oder schreib mir einen konkreten Hinweis!
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  """

  sendToUserViaTelegram(report)

  // Auf Antwort warten
  userResponse = waitForUserResponse()

  SWITCH userResponse:
    CASE "/skip":
      markPhaseSkipped(phaseId)
      RETURN "SKIP"

    CASE "/reset-phase":
      resetPhase(phaseId)
      RETURN "RESET"

    CASE "/manual":
      notifyUser("OK, ich warte bis du fertig bist. " +
                 "Sag 'Fertig' wenn du die Phase manuell erledigt hast.")
      waitForUserResponse("fertig")
      markPhaseCompleted(phaseId, "manual")
      RETURN "MANUAL_DONE"

    DEFAULT:
      // User hat einen konkreten Hinweis gegeben
      customPrompt = userResponse
      applyCustomFix(phaseId, customPrompt)
      RETURN "CUSTOM_FIX"
  END SWITCH

ENDE
```

## Günther Error-Analyse-Funktion

```
FUNKTION: askGuentherForErrorAnalysis(error, sourceCode)

  systemPrompt = readFile("prompts/error-analysis.txt")

  response = askGuenther(
    system: systemPrompt,
    user: "FEHLER-ANALYSE-ANFRAGE:

           Fehler: {error.raw}
           Datei: {error.file}
           Schwere: {error.severity}
           Kategorie: {error.category}

           Betroffener Code:
           ```csharp
           {sourceCode}
           ```

           Analysiere den Fehler und erstelle einen Korrektur-Prompt."
  )

  analysis = parseJSON(response)

  // Validierung
  ASSERT analysis.errorType IS NOT EMPTY
  ASSERT analysis.rootCause IS NOT EMPTY
  ASSERT analysis.correctionPrompt IS NOT EMPTY
  ASSERT analysis.severity IN ["critical", "major", "minor"]

  RETURN analysis

ENDE
```

## Modell-Auswahl bei Fehlern

```
FUNKTION: selectModelForCorrection(error, attempt)

  // Versuche 1-2: Standard-Modell (Sonnet)
  IF attempt <= 2:
    RETURN config.models.coderDefault

  // Versuch 3: Upgrade zu Opus für schwierige Fehler
  IF attempt == 3:
    RETURN config.models.coderComplex

  // Versuch 4: Zurück zu Sonnet (vereinfachter Ansatz)
  IF attempt == 4:
    RETURN config.models.coderDefault

  // Versuch 5: Haiku für minimalen Stub
  IF attempt == 5:
    RETURN config.models.coderQuick

  RETURN config.models.coderDefault

ENDE
```
