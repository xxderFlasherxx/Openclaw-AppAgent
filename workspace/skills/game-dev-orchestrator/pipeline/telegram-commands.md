# Telegram-Commands (Teil J, Schritt 31)

Quelle: `AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt` → Teil J, Schritt 31.

Hans läuft als OpenClaw-Daemon und reagiert über den Telegram-Provider
auf Nachrichten. Dieser Abschnitt definiert das **Kommando-Vokabular**
für den `game-dev-orchestrator` und mappt jedes Kommando auf einen
State-Übergang im [master-orchestrator.md](./master-orchestrator.md).

---

## Kommando-Übersicht

| Kommando                         | Min-Argumente | Erlaubt in States                          | Wirkung                                                                           |
|----------------------------------|---------------|---------------------------------------------|-----------------------------------------------------------------------------------|
| `/newgame <freitext>`            | freitext ≥ 3 Zeichen | `WAITING`, `DONE`                     | `state = ANALYZING`, `currentRun = startRun(freitext)`                            |
| `/status`                        | —             | alle                                        | sendet Status-Snapshot (state, phase, cost, ETA) zurück                           |
| `/phases`                        | —             | `PLANNING`–`DONE`                           | sendet `master-plan.json` als nummerierte Liste                                   |
| `/pause`                         | —             | alle laufenden                              | `state.paused = true`, kein neuer Copilot-Call                                    |
| `/resume`                        | —             | nur wenn `state.paused`                     | `state.paused = false`, nächster Tick startet wieder                              |
| `/abort [grund]`                 | optional      | alle laufenden                              | Hard-Stop, `state = ABORTED`, Postmortem in Telegram                              |
| `/approve <planHash>`            | planHash      | `PLANNING` mit `approvalMode=manual`        | bestätigt Plan, Übergang `PLANNING → INITIALIZING`                                |
| `/rating <1-5> [kommentar]`      | rating        | `AWAITING_FEEDBACK`                         | speichert Feedback (siehe [user-feedback.md](./user-feedback.md))                  |
| `/realrun`                       | —             | alle                                        | beendet `safety.dryRunFirstRun` für den User (siehe [safety-gates.md](./safety-gates.md)) |
| `/dryrun`                        | —             | alle                                        | erzwingt `dryRunFirstRun = true`                                                  |
| `/skip`                          | —             | nur wenn `correctingExhausted=true`         | überspringt aktuelle Phase                                                        |
| `/reset-phase`                   | —             | `EXECUTING`–`CORRECTING`                    | startet aktuelle Phase neu (attempt = 1)                                          |
| `/manual`                        | —             | `EXECUTING`–`CORRECTING`                    | Übergibt Phase an User, wartet auf `/resume`                                      |

> **Implizite Aktivierung:** Erhält Hans im State `WAITING` Freitext mit
> Spiel-Keywords (Trigger-Set aus `SKILL.md`), behandelt er das wie
> `/newgame <freitext>` — schickt aber zuerst eine Rückfrage
> ("Soll ich das als neues Spielprojekt starten? /yes oder /no").

---

## Parser-Algorithmus

```
FUNKTION parseTelegramCommand(message):
  text = trim(message.text)
  IF text starts with "/":
    parts = split(text, " ", limit=2)
    command = parts[0].lower()
    args    = parts[1] OR ""
  ELSE:
    command = "<freitext>"
    args    = text
  END IF
  RETURN { command, args, chatId, userId, messageId }
ENDE
```

Kommandos werden case-insensitiv akzeptiert (`/Status` == `/status`).

### Argument-Validierung

| Kommando      | Validator                                                |
|---------------|----------------------------------------------------------|
| `/newgame`    | `length(args) >= 3 && length(args) <= 1000`              |
| `/approve`    | `args matches ^[0-9a-f]{12}$` (sha256-Prefix aus Schritt 27) |
| `/rating`     | `args matches ^[1-5]( .*)?$`                             |

Schlägt eine Validierung fehl, antwortet Hans mit der zugehörigen
Usage-Nachricht (siehe `tests/fixtures/telegram-events.json`).

---

## Berechtigungen

Nur Telegram-Chats, die in `credentials/telegram-pairing.json` gepairt sind,
dürfen Kommandos absenden. Unbekannte `chatId`/`userId`-Kombinationen
werden ignoriert und in `logs/config-audit.jsonl` mit `event=denied` geloggt.

---

## State-Übergangs-Tabelle (vollständig)

| State            | Erlaubte Kommandos                                                       |
|------------------|--------------------------------------------------------------------------|
| `WAITING`        | `/newgame`, `/status`, `/realrun`, `/dryrun`                             |
| `ANALYZING`      | `/status`, `/abort`                                                      |
| `PLANNING`       | `/status`, `/phases`, `/abort`, `/approve`                               |
| `INITIALIZING`   | `/status`, `/abort`                                                      |
| `EXECUTING`      | `/status`, `/pause`, `/abort`, `/reset-phase`, `/manual`                 |
| `VERIFYING`      | `/status`, `/pause`, `/abort`                                            |
| `CORRECTING`     | `/status`, `/pause`, `/abort`, `/skip`, `/reset-phase`, `/manual`        |
| `PHASE_DONE`     | `/status`, `/pause`, `/abort`                                            |
| `BUILDING`       | `/status`, `/abort`                                                      |
| `COMPLETE`       | `/status`, `/rating`                                                      |
| `ARCHIVING`      | `/status`                                                                |
| `AWAITING_FEEDBACK` | `/status`, `/rating`, `/abort`                                        |
| `DONE`           | `/newgame`, `/status`                                                    |
| `ABORTED`        | `/newgame`, `/status`                                                    |

Falls ein Kommando in einem unzulässigen State eingeht, antwortet Hans:

```
Befehl '/skip' ist im aktuellen Status (EXECUTING) nicht erlaubt.
Erlaubt sind: /status, /pause, /abort, /reset-phase, /manual.
```

---

## Bestätigungs- und Veto-Flow

Bei `approvalMode = auto-with-telegram-veto` (Default) öffnet Hans nach
Plan-Erstellung ein **Veto-Fenster** (Default 20 s). Innerhalb dieser
Zeit kann der User mit `/abort` den Lauf stoppen. Sonst startet
`INITIALIZING` automatisch.

Bei `approvalMode = manual` muss der User aktiv `/approve <planHash>`
schicken. Hans verweigert den Übergang sonst.

---

## Antwort-Formate (Telegram)

### `/status`-Antwort
```
🎮 Run: CatLongDrive
State: EXECUTING (Phase 3/10 – Camera-System)
Attempt: 1/5
Cost: $0.42 / $5.00
Wallclock: 12 min
ETA: ~30 min
```

### `/phases`-Antwort
```
📋 Master-Plan (CatLongDrive):
1. ✅ Projektstruktur
2. ✅ Player Controller
3. ⏳ Camera-System
4. ⬜ Terrain
…
10. ⬜ Build
```

### `/abort`-Antwort
```
🛑 Run abgebrochen.
Grund: <vom User eingegebener Text|"manual">
Postmortem: .plan/postmortem-<runId>.md
```

---

## Tests

`tests/test-telegram-commands.sh` (siehe Suite 33 in `run-tests.sh`)
prüft:

* Parser akzeptiert alle 13 Kommandos in beliebiger Schreibweise
* Argument-Validierung schlägt bei zu kurzen / falsch formatierten
  Eingaben fehl
* State-Erlaubnis-Matrix (Erlaubt vs. Verboten)
* `parseTelegramCommand` ignoriert Whitespace-Padding
* Mock-Telegram-Events aus `tests/fixtures/telegram-events.json`
  werden auf erwartete State-Übergänge gemappt
