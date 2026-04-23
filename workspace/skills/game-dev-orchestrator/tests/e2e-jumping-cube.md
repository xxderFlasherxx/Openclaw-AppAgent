# End-to-End Testlauf – JumpingCube (Teil F, Schritt 21)

Erste echte Feuerprobe des gesamten Systems. Ein bewusst minimalistisches
Spiel – simpel genug, um Fehlerquellen schnell zu isolieren.

## Spielidee

> **JumpingCube** – Ein roter Würfel auf einer grünen Fläche. Leertaste
> löst einen Sprung aus. Jeder Sprung erhöht den Score um 1. Die
> Score-Zahl wird oben links angezeigt.

Bewusst gewählt, weil das Spiel:
- nur eine Szene benötigt,
- keine Assets aus dem Store braucht,
- alle Kern-Subsysteme berührt (Input, Physik, UI, Audio, Build).

## Erwartete 10 Phasen

| # | Phase                                      | Schlüssel-Dateien                          |
|---|--------------------------------------------|--------------------------------------------|
| 1 | Projektstruktur + Basis-Szene              | `Main.unity`, `GameManager.cs`             |
| 2 | Würfel-Controller (Spring-Mechanik)        | `CubeController.cs`                        |
| 3 | Kamera (statisch, schaut auf den Würfel)   | `CameraRig.cs` (optional)                  |
| 4 | Boden + Physik (Collider, Rigidbody)       | Szenen-Setup + Materials                   |
| 5 | Score-System                               | `ScoreManager.cs`                          |
| 6 | UI (Score-Anzeige oben links)              | `ScoreUI.cs`, Canvas-Prefab                |
| 7 | Polish (Partikel beim Springen)            | `JumpParticles.prefab`                     |
| 8 | Sound (Spring-Sound, AudioManager-Hook)    | `JumpSound.cs`                             |
| 9 | Main Menu                                  | `MainMenu.unity`, `MenuController.cs`      |
|10 | Build (StandaloneLinux64)                  | `Builds/JumpingCube`                       |

## Voraussetzungen

Vor dem Start ausführen:

```bash
bash workspace/skills/game-dev-orchestrator/references/check-prerequisites.sh
```

Es müssen **alle** als `required` markierten Checks bestanden sein:
Node.js ≥ 22, OpenClaw-Daemon läuft, Workspace vorhanden, Unity-Editor
gefunden, Ollama-API-Key gesetzt, VS Code + Copilot installiert,
`~/GameDev-Projekte/` beschreibbar.

Ebenso muss `gamedev-config.json` gültig sein:

```bash
jq . workspace/skills/game-dev-orchestrator/gamedev-config.json
```

Und `dryRun` auf **`false`** stehen.

## Durchführung

1. `openclaw` starten (als User-Daemon).
2. Chat-Nachricht an Hans (oder Telegram):

   > „Bau mir ein kleines Spiel: Ein roter Würfel, der auf Leertaste
   > springt. Jeder Sprung gibt einen Punkt. Score oben links anzeigen.
   > Nenne das Projekt JumpingCube."

3. Hans aktiviert das Skill `game-dev-orchestrator` → state transitioniert
   `WAITING → ANALYZING → PLANNING`.
4. Günther liefert den 10-Phasen-Plan. Per Telegram kommt eine
   Plan-Übersicht zur User-Bestätigung (weil `autoStart=false`).
5. Nach `"Weiter"` läuft die Pipeline autonom durch.

## Zu dokumentieren pro Phase (`.plan/test-run-log.txt`)

Für **jede** Phase festhalten:

- [ ] Startzeit
- [ ] Prompt an Günther
- [ ] Resultierender Prompt an Copilot
- [ ] Erstellte / geänderte Dateien
- [ ] Anzahl Korrektur-Versuche
- [ ] Auftretende Fehler (inkl. CS-Code bzw. Runtime-Stacktrace)
- [ ] Verwendetes Modell (Sonnet/Opus/Haiku)
- [ ] Endstatus (completed / escalated / skipped)
- [ ] Dauer

## Evaluierung (`.plan/test-evaluation.txt`)

Nach Lauf-Ende:

1. Hat der finale Build gestartet und erfolgreich gebaut?
   ```bash
   ls -lh ~/GameDev-Projekte/JumpingCube/Builds/
   ~/GameDev-Projekte/JumpingCube/Builds/JumpingCube.x86_64
   ```
2. Funktioniert das Spiel im Unity-Editor (Play-Mode)?
3. Wie viele Fehler insgesamt? (`.plan/error-log.json | jq '.errors|length'`)
4. Welche Phasen hatten besonders viele Retries?
5. Welche Prompts wirkten schlecht formuliert? → Learnings in
   `templates/learnings.json` übernehmen.
6. Welche Timings lagen über dem Erwartungswert (2–3 min/Phase)?

## Quick-Validate nach dem Lauf

```bash
PRJ=~/GameDev-Projekte/JumpingCube
jq '.status'                    "$PRJ/.plan/orchestrator-state.json"
jq '[.phases[] | .status]'      "$PRJ/.plan/phase-history.json"
jq '.errors | length'           "$PRJ/.plan/error-log.json"
test -x "$PRJ/Builds/JumpingCube.x86_64" && echo "Build OK" || echo "Build FEHLT"
```

## Abort-Kriterien (Lauf manuell stoppen)

- Eine Phase eskaliert (max_retries) **und** das Problem ist klar
  unlösbar ohne manuellen Eingriff.
- Unity-Editor crasht reproduzierbar.
- Ollama-API liefert drei Mal in Folge leere oder ungültige Pläne.

In diesen Fällen via Telegram `Stopp` senden und den Zustand in
`orchestrator-state.json` sichern.
