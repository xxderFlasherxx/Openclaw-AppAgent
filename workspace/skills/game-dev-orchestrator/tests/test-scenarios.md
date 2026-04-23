# Test-Szenarien (Teil F – Schritt 20.3)

Dieses Dokument beschreibt die fünf offiziellen Testszenarien für das
autonome GameDev-System. Die ersten vier laufen vollständig im **Dry-Run**
und werden automatisiert durch `tests/run-tests.sh` bzw.
`tests/simulate-dry-run.sh` ausgeführt. Das fünfte Szenario ist der echte
End-to-End-Lauf (`tests/e2e-jumping-cube.md`).

---

## Test 1 – Happy Path

**Ziel:** Der gesamte Workflow läuft ohne einen einzigen Fehler durch.

- Szenario-Key: `happy_path`
- Unity-Sequenz: `sequence_happy_path`
- Erwartung:
  - Alle 3 Phasen aus `mock-master-plan.json` werden abgeschlossen.
  - `dry-run-summary.json.status == "success"`
  - `error-log.json.errors` ist leer.
  - Die drei erwarteten C#-Dateien liegen unter `Assets/Scripts/...`.

Aufruf:
```bash
tests/simulate-dry-run.sh happy_path /tmp/dr-happy
```

---

## Test 2 – Single Error

**Ziel:** Genau ein Kompilierfehler in Phase 2 wird im nächsten Versuch behoben.

- Szenario-Key: `single_error`
- Unity-Sequenz: `sequence_single_error` (enthält `error_cs0246` gefolgt von `success`)
- Erwartung:
  - `error-log.json.errors | length == 1`
  - `dry-run-summary.json.totalErrors == 1`
  - `dry-run-summary.json.status == "success"`
  - Alle 3 Phasen im `phase-history.json` mit status `completed`.

---

## Test 3 – Multiple Errors

**Ziel:** Drei unterschiedliche Fehler in Folge werden automatisch korrigiert.

- Szenario-Key: `multiple_errors`
- Unity-Sequenz: `sequence_multiple_errors`
- Erwartung:
  - 3 Einträge in `error-log.json.errors`
  - Am Ende trotzdem `status == "success"`
  - Der Escalation-Pfad wird **nicht** getriggert.

---

## Test 4 – Max Retries (Eskalation)

**Ziel:** Alle 5 Retries einer Phase scheitern → Incident Report, User-Eskalation.

- Szenario-Key: `max_retries`
- Unity-Sequenz: `sequence_max_retries` (nur Fehler, nie `success`)
- Erwartung:
  - Der Simulator bricht bei der eskalierten Phase ab.
  - `dry-run-summary.json.status == "escalated"`
  - `phase-history.json` enthält genau eine Phase mit `status == "escalated"`.
  - Exit-Code des Simulators = 1.

In der echten Pipeline würde an dieser Stelle eine Telegram-Nachricht an
den User gehen mit den Optionen `/skip`, `/reset-phase`, `/manual`.

---

## Test 5 – Full Pipeline (End-to-End, kein Dry-Run)

**Ziel:** Ein echtes Mini-Spiel autonom durchlaufen.

Siehe: [`tests/e2e-jumping-cube.md`](./e2e-jumping-cube.md)

- Setzt voraus: Unity installiert, Ollama Cloud API Key, VS Code Copilot aktiv.
- Wird **nicht** von `run-tests.sh` ausgeführt (manuell/getrennt).

---

## Mapping Test ↔ Pipeline-Zustände

| Test              | Abgedeckte Zustände                                          |
|-------------------|--------------------------------------------------------------|
| Happy Path        | INITIALIZING → EXECUTING → VERIFYING → PHASE_DONE → COMPLETE |
| Single Error      | + CORRECTING → VERIFYING                                     |
| Multiple Errors   | + CORRECTING (mehrfach)                                      |
| Max Retries       | + Incident Report / User-Eskalation                          |
| Full Pipeline     | Alle Zustände inkl. Günther/VS Code/Unity real               |
