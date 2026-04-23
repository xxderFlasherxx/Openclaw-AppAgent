# Known Issues & Design-Decisions

Dieses Dokument erklärt bekannte Abweichungen zwischen dem ursprünglichen Plan
(`AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt`) und dem tatsächlichen Stand des
`game-dev-orchestrator`-Skills sowie bewusste Design-Entscheidungen.
Adressiert Schwachstellen #1, #4, #5 aus dem Teil-F-Review.

---

## 1. Skill-basierter Orchestrator statt Code-Implementation (#1)

Im Plan wird der Orchestrator teilweise als Code-Funktion beschrieben
(`createMasterPlan()`, `advanceToNextPhase()`, …). Die tatsächliche
Implementation ist **skill-basiert**: Hans (OpenClaw) interpretiert die
Markdown-Specs in `pipeline/` und `SKILL.md` zur Laufzeit und führt die
beschriebenen Schritte mit seinen Built-in-Tools (`read`, `write`, `exec`,
`web_fetch`, …) aus.

**Konsequenz:** Die automatischen Tests in `tests/` validieren Daten und
Strukturen, aber nicht den echten Kontrollfluss. Der einzige Weg, den echten
Kontrollfluss zu testen, ist der End-to-End-Lauf (`tests/e2e-jumping-cube.md`,
Schritt 21 aus dem Plan).

**Mitigationen:**
- Dry-Run-Simulator (`tests/simulate-dry-run.sh`) emuliert die State-Machine
  in Bash und validiert Phase-Übergänge, Error-Log, History, Eskalation.
- Schema-Contract-Tests (Suite 22) garantieren das Datenformat zwischen
  `AutoCompileWatcher.cs` und dem Orchestrator.
- Template-Content-Smoke-Tests (Suite 23) verhindern „versehentlich leere"
  Template-Dateien.

---

## 2. Pfad-Konfiguration (#4)

| Quelle                                   | Pfad                                             |
|------------------------------------------|--------------------------------------------------|
| `AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt`      | `~/Documents/Programmieren/GameDev-Projekte/`    |
| `gamedev-config.json` (aktuell)          | `/home/vboxuser/GameDev-Projekte`                |

**Entscheidung:** Der Linux-Pfad in `gamedev-config.json` ist **korrekt** für
die aktuelle VM-Umgebung. Der Plan wurde ursprünglich für macOS geschrieben
(`~/Documents/Programmieren/…`) und ist nicht 1:1 auf die VM übertragbar.

**Single Source of Truth:** `gamedev-config.json`. Alle Skripte
(`setup-gamedev-environment.sh`, Skill-Specs, Pipeline-MDs) lesen den Pfad aus
dieser Config. Der Plan-Text bleibt als historisches Dokument bestehen.

**Konsequenz fürs Testing:** `check-prerequisites.sh` prüft, ob der Projekt-
Ordner existiert. Falls nicht vorhanden, wird er durch
`setup-gamedev-environment.sh` erstellt.

---

## 3. Modell-Namen (#5)

| Quelle                              | Architekt-Modell                    |
|-------------------------------------|-------------------------------------|
| `AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt` | `kimi-k2.5`                         |
| `gamedev-config.json` (aktuell)     | `qwen3-coder-next:cloud`            |
| `SKILL.md`                          | *erwähnt beide historisch*          |

**Entscheidung:** Für den aktuellen Stand gilt `gamedev-config.json` als
verbindlich. `qwen3-coder-next:cloud` hat sich für Code-Aufgaben als besser
erwiesen als `kimi-k2.5`. Hans nutzt das Modell, das in
`ollamaCloud.model` eingetragen ist — unabhängig vom Plan-Text.

**Wenn zurück auf Kimi gewechselt werden soll:** Nur den Wert in der Config
ändern, sonst nichts.

---

## 4. Wechselwirkung dryRun ↔ Produktion

`gamedev-config.json` hat einen einzelnen Flag `dryRun: true|false`.

- **false** (Standardzustand für echte Läufe): Hans ruft Günther an, steuert
  VS Code und beobachtet Unity. Echte API-Kosten, echte Code-Generation.
- **true**: Hans nutzt die Mocks in `test-data/`. Keine API-Kosten. Ideal
  zum Trockenlauf des Workflows auf einer neuen Maschine.

Der Test-Runner warnt (Suite 25), falls `dryRun=true` ist – um zu verhindern,
dass ein „Test-Flag" versehentlich im Produktionseinsatz stecken bleibt.

---

## 5. Tools, die NICHT automatisch getestet werden können

- **Ollama-Cloud-API** – nur mit `run-tests.sh --online` (opt-in, braucht Netz).
- **VS Code Copilot Code-Generation** – nicht sinnvoll automatisierbar.
  Inhalts-Qualität wird erst im E2E-Lauf sichtbar.
- **Unity Editor-Kompilierung** – benötigt installierten Unity Editor.
  `check-prerequisites.sh` meldet, falls Unity fehlt.

Für diese Bereiche ist der manuelle E2E-Lauf (Schritt 21) alternativlos.
