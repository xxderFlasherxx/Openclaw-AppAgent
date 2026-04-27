# Safety-Gates (Teil H, Schritt 27)

## Zweck

Hans bringt den VS Code Copilot dazu, **direkt auf das Dateisystem**
zu schreiben. Ohne klar definierte Sicherheitsgrenzen könnte eine
fehlerhafte Plan-Generierung Dateien außerhalb des Projektes
verändern. Die Safety-Gates definieren

* **Wo** geschrieben werden darf (`writeScope`)
* **Wo nicht** (`denyScope`)
* **Wer/was** den Lauf freigibt (`approvalMode`)
* **Wie viel** pro Phase passieren darf (Limits)
* **Ob** ein Dry-Run erzwungen wird (`dryRunFirstRun`)

Die Werte stehen in `gamedev-config.json` -> `safety`.

---

## Approval-Modi

| Modus                          | Verhalten                                                                                  |
|--------------------------------|--------------------------------------------------------------------------------------------|
| `manual`                       | Jede Phase muss explizit per Telegram-Befehl `/approve` bestätigt werden.                  |
| `auto-with-telegram-veto`      | Phase startet automatisch; ein Telegram-Veto innerhalb `vetoWindowSeconds` bricht ab.       |
| `fully-autonomous`             | Kein Veto-Fenster, nur Notfall-Halt (`/abort`) möglich.                                    |

Default: `auto-with-telegram-veto` mit `vetoWindowSeconds: 20`.

---

## State-Übergänge mit Gates

```
PLANNING --[gate: planHashApproval]--> INITIALIZING
INITIALIZING --[gate: writeScopeCheck]--> EXECUTING
EXECUTING --[gate: writeScopeCheck + limits]--> VERIFYING
VERIFYING --[gate: -none-]--> PHASE_DONE
PHASE_DONE --[gate: budgetCheck]--> NEXT_PHASE
```

### `planHashApproval` (PLANNING -> INITIALIZING)

1. Hans berechnet `sha256` des master-plan.json.
2. Sendet Telegram-Nachricht:
   ```
   Plan bereit:
     Game: <gameName>
     Phasen: 10
     Hash: <sha256[:12]>
   Veto innerhalb von 20 s mit /abort möglich.
   ```
3. Wartet `safety.vetoWindowSeconds` Sekunden auf eingehende
   `/abort`-Nachrichten.
4. Bei `manual` wird stattdessen aktiv `/approve` erwartet.

### `writeScopeCheck` (vor jedem Schreibvorgang)

```
FUNKTION: assertWriteAllowed(targetPath, config.safety)

  absolute = realpath(targetPath)

  // 1. Deny-Liste hat Vorrang
  FOR EACH pattern IN config.safety.denyScope:
    IF glob_match(absolute, expandUser(pattern)):
      throw SafetyViolation("denyScope_match", absolute, pattern)
  END

  // 2. Mindestens ein writeScope muss matchen
  matched = false
  FOR EACH pattern IN config.safety.writeScope:
    IF glob_match(absolute, expandUser(pattern, projectName)):
      matched = true
      BREAK
  END

  IF NOT matched:
    throw SafetyViolation("not_in_writeScope", absolute, null)

ENDE
```

`expandUser` ersetzt `~` durch `$HOME` und `<projectName>`
durch den aktuellen Projekt-Slug.

### Limits (pro Phase)

* `maxFilesChangedPerPhase` (Default 15) - mehr -> Phase wird
  abgebrochen, Hans schickt Telegram-Warnung.
* `maxBytesPerFile` (Default 204800 = 200 KB) - größere Dateien
  werden nicht akzeptiert (passt zu `codeExtraction.maxFileSizeKb`).

### `budgetCheck` (PHASE_DONE -> NEXT_PHASE)

Siehe Schritt 33. Hier nur als Hook erwähnt; reine Token-/Zeit-
Budgets werden in `pipeline/budget-limits.md` (Schritt 33) bewertet.

---

## Dry-Run-Modus

Beim **allerersten** Lauf eines neuen Users erzwingt das System
`safety.dryRunFirstRun = true`. In diesem Modus:

1. Pläne werden generiert
2. Prompts werden gebaut
3. **Adapter A wird NICHT ausgeführt**
4. Stattdessen schreibt Hans alle Prompts in
   `<projectPath>/.plan/dry-run/phaseN-prompt.md`
5. Hans sendet dem User eine Zusammenfassung per Telegram

Erst nach explizitem Befehl `Hans, echter Lauf` (oder
Telegram-Command `/realrun`) wird `dryRunFirstRun` auf `false`
gesetzt und der nächste Lauf führt Adapter A aus.

`dryRun: true` (oberste Ebene in `gamedev-config.json`) bleibt als
manueller Schalter erhalten und überschreibt `dryRunFirstRun`.

---

## Telegram-Kommandos

| Kommando      | Wirkung                                              |
|---------------|------------------------------------------------------|
| `/approve`    | manuelle Freigabe (Modus `manual`)                   |
| `/abort`      | Veto / Notfall-Halt (alle Modi)                      |
| `/realrun`    | Beendet den Dry-Run-Modus für diesen User            |
| `/dryrun`     | Schaltet wieder in Dry-Run                           |
| `/status`     | Aktueller Phasen-Status                              |

---

## Audit-Log

Alle Gate-Entscheidungen werden in `<projectPath>/.plan/safety-audit.jsonl`
appended geloggt:

```json
{"ts":"2026-04-27T08:11:23Z","gate":"writeScopeCheck",
 "path":"/home/x/GameDev-Projekte/foo/Assets/Scripts/Bar.cs",
 "result":"allowed","matchedScope":"~/GameDev-Projekte/<projectName>/**"}
```

Das Log darf von Hans nur **angehängt** (append-only) werden.

---

## Konfigurations-Referenz

```json
"safety": {
  "writeScope": [
    "~/GameDev-Projekte/<projectName>/**",
    "~/.openclaw/workspace/memory/gamedev-*.json"
  ],
  "denyScope": [
    "~/.ssh/**", "/etc/**", "/usr/**", "~/.config/**",
    "~/.openclaw/openclaw.json"
  ],
  "approvalMode": "auto-with-telegram-veto",
  "vetoWindowSeconds": 20,
  "maxFilesChangedPerPhase": 15,
  "maxBytesPerFile": 204800,
  "dryRunFirstRun": true
}
```

Erlaubte Werte für `approvalMode`:
`manual`, `auto-with-telegram-veto`, `fully-autonomous`.
