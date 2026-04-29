# Budget- und Zeitlimits (Teil J, Schritt 33)

Quelle: `AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt` → Teil J, Schritt 33.

Ohne harte Grenzen kann das System im Fehlerfall beliebig viele
Copilot-Calls oder eine endlose Tick-Loop verursachen. Schritt 33
definiert vier orthogonale Bremsen:

1. **Killswitch-Datei** – sofortiger Abbruch ohne Telegram-Latenz
2. **Cost-Enforcement** – pro Phase und pro Run
3. **Wallclock-Enforcement** – maximale Laufzeit pro Run
4. **Retry-Cap** – pro Phase und global pro Run

Alle Werte stehen in `gamedev-config.json → limits`.

---

## Konfigurations-Referenz

```json
"limits": {
  "maxCostUsdPerRun":         5.00,
  "maxCostUsdPerPhase":       1.00,
  "maxWallclockMinutesPerRun": 180,
  "maxRetriesPerPhase":         5,
  "maxTotalRetriesPerRun":     25,
  "killSwitchFile": "/home/vboxuser/.openclaw/STOP_GAMEDEV"
}
```

Diese Werte werden bei jedem **Tick** geprüft (siehe Schritt 32 in
`master-orchestrator.md` Sektion *Tick-Loop*).

---

## Killswitch

```
FUNKTION checkKillSwitch():
  IF fileExists(config.limits.killSwitchFile):
    runState.haltReason = "killswitch"
    transitionTo("ABORTED")
    sendTelegram("🛑 Killswitch aktiviert. Lauf abgebrochen.")
    deleteFile(config.limits.killSwitchFile)
    RETURN true
  RETURN false
ENDE
```

Aufgerufen **als allererste Aktion** in jedem `onTick()`. Damit kann
ein Operator die Maschine ohne Telegram-Verbindung stoppen:

```bash
touch ~/.openclaw/STOP_GAMEDEV
```

Die Datei wird nach Übergang in `ABORTED` automatisch gelöscht, damit
der nächste `/newgame`-Aufruf nicht direkt wieder gestoppt wird.

---

## Cost-Enforcement

Nutzt `model-usage.json` (siehe `pipeline/model-routing.md`).

```
FUNKTION enforceCostBudget(plannedCallModel):
  pricing      = config.modelRouting.pricing[plannedCallModel]
  estimatedUsd = estimateCost(currentPrompt, pricing)

  runTotal   = runState.cost.totalUsd + estimatedUsd
  phaseTotal = runState.cost.byPhase[currentPhase] + estimatedUsd

  IF runTotal > config.limits.maxCostUsdPerRun:
    RETURN halt("budget_exhausted_run", runTotal)

  IF phaseTotal > config.limits.maxCostUsdPerPhase:
    cheaper = downgradeModel(plannedCallModel)   // sonnet -> haiku
    IF cheaper IS NOT plannedCallModel:
      logRoutingDecision("downgrade_due_to_budget",
                         plannedCallModel, cheaper)
      RETURN { action: "use_model", model: cheaper }
    ELSE:
      RETURN halt("budget_exhausted_phase", phaseTotal)

  RETURN { action: "proceed" }
ENDE
```

`halt(reason, value)` löst einen Übergang in `ABORTED` aus und schickt
einen Telegram-Bericht mit dem genauen Reason und dem aktuellen
Kosten-Snapshot.

### Schätzformel

```
estimatedUsd = (promptTokens * pricing.inputPerKToken / 1000)
             + (avgOutputTokens * pricing.outputPerKToken / 1000)
```

`avgOutputTokens` wird aus `model-usage.json` als rollierender
Durchschnitt der letzten 10 Calls desselben Modells berechnet (Default
1024, falls keine Historie vorhanden).

---

## Wallclock-Enforcement

```
FUNKTION enforceWallclock():
  startedAt = parseIso(runState.startedAt)
  elapsedMin = (now() - startedAt) / 60

  IF elapsedMin > config.limits.maxWallclockMinutesPerRun:
    RETURN halt("wallclock_exceeded", elapsedMin)
  RETURN { action: "proceed" }
ENDE
```

`enforceWallclock` läuft in jedem Tick, **bevor** ein neuer Copilot-
Call gestartet wird.

---

## Retry-Caps

| Limit                      | Wirkung                                             |
|----------------------------|------------------------------------------------------|
| `maxRetriesPerPhase` = 5   | Bei Erreichen → Eskalation an User (Schritt 15.3)    |
| `maxTotalRetriesPerRun` = 25 | Bei Erreichen → `halt("retries_exhausted")`        |

Ein Retry zählt nur, wenn `state == CORRECTING` betreten wird; saubere
`PHASE_DONE`-Übergänge zählen nicht mit.

---

## Halt-Reasons (vollständige Liste)

| Reason                       | Quelle                            | Folge-State |
|------------------------------|-----------------------------------|-------------|
| `killswitch`                 | `checkKillSwitch()`               | `ABORTED`   |
| `budget_exhausted_run`       | `enforceCostBudget()`             | `ABORTED`   |
| `budget_exhausted_phase`     | `enforceCostBudget()`             | `ABORTED`   |
| `wallclock_exceeded`         | `enforceWallclock()`              | `ABORTED`   |
| `retries_exhausted`          | Retry-Cap                         | `ABORTED`   |
| `manual_abort`               | `/abort`-Kommando                 | `ABORTED`   |
| `safety_violation`           | `assertWriteAllowed()`            | `ABORTED`   |

Jeder Halt schreibt eine Zeile nach `.plan/halt-log.jsonl`:

```json
{"ts":"2026-04-29T11:23:00Z","runId":"abc123","reason":"budget_exhausted_run",
 "value":5.34,"phase":3,"state":"EXECUTING"}
```

---

## Tick-Integration

Reihenfolge der Checks pro Tick (siehe
[master-orchestrator.md – Tick-Loop](./master-orchestrator.md#tick-loop)):

```
1. checkKillSwitch()             // sofort raus
2. enforceWallclock()            // Zeit
3. enforceTotalRetries()         // Retry-Global
4. (im Action-Handler) enforceCostBudget(model)  // pro Call
```

Phase-Retries werden direkt in `error-correction.md` geprüft (Schritt 15)
und sind hier nur als Hard-Cap referenziert.

---

## Tests

`tests/test-limits.sh` (siehe Suite 34 in `run-tests.sh`) prüft:

* Mock-Usage 4.80 USD + 0.30 USD geplanter Call → `halt("budget_exhausted_run")`
* Killswitch-Datei vorhanden → state == `ABORTED` im nächsten Tick
* Wallclock 181 min vergangen → `halt("wallclock_exceeded")`
* `maxTotalRetriesPerRun` überschritten → `halt("retries_exhausted")`
* Phase-Budget überschritten + downgradebar → `use_model: haiku`
* Halt-Log-Format gegen `tests/fixtures/halt-log-entry.schema.json`
