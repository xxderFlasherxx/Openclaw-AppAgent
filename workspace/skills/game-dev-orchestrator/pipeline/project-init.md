# Project Initializer (Schritt 6 + Teil I/Schritt 28.2)

Quelle: `AUTONOMES_GAMEDEV_SYSTEM_PLAN.txt` → Schritt 6 (Sub-Skill
"project-initializer") und Schritt 28.2 (Watcher-Deployment).

Der `project-initializer` legt vor Phase 1 jedes neue Unity-Projekt an
und sorgt dafür, dass alle für die Pipeline notwendigen Dateien an Ort
und Stelle sind. Diese Datei dokumentiert die Schritt-für-Schritt-
Implementierung – `master-orchestrator.md` referenziert sie aus dem
Zustand `INITIALIZING`.

## Voraussetzungen

- Master-Plan von Günther existiert (`PLANNING` ist abgeschlossen).
- `gamedev-config.json` wurde geladen.
- Schreibrechte für `paths.projectsRoot`.

## Reihenfolge

a) **Projektnamen ermitteln**
   - Aus `master-plan.json.gameName` (PascalCase).
   - Slug-Variante (`kebab-case`) für den Ordnernamen.

b) **Projektordner anlegen**
   ```bash
   PROJECT="$projectsRoot/$gameSlug"
   mkdir -p "$PROJECT/Assets/Scripts/Core" \
            "$PROJECT/Assets/Scripts/Player" \
            "$PROJECT/Assets/Scripts/UI" \
            "$PROJECT/Assets/Scenes" \
            "$PROJECT/Assets/Editor" \
            "$PROJECT/.plan" \
            "$PROJECT/Builds"
   ```

c) **Unity-Projekt erzeugen** (Batchmode):
   ```bash
   "$editorBinary" -batchmode -quit -nographics \
     -createProject "$PROJECT" \
     -logFile       "$PROJECT/.plan/unity-init.log"
   ```
   Wenn `editorBinary` nicht gesetzt: Skip mit Warnung – die
   `.plan/`-Strukturen werden trotzdem angelegt, sodass der Trockenlauf
   funktioniert (Schwachstelle #8).

d) **Templates kopieren**
   ```
   templates/unity-gitignore.txt    → $PROJECT/.gitignore
   templates/unity-editorconfig.txt → $PROJECT/.editorconfig
   templates/base-game-manager.cs.txt → $PROJECT/Assets/Scripts/Core/GameManager.cs
   templates/Singleton.cs.txt       → $PROJECT/Assets/Scripts/Core/Singleton.cs
   ```

e) **Initial-State-Dateien** (alle aus `templates/*.json` kopieren):
   ```
   templates/orchestrator-state.json → $PROJECT/.plan/orchestrator-state.json
   templates/current-phase.json      → $PROJECT/.plan/current-phase.json
   templates/phase-history.json      → $PROJECT/.plan/phase-history.json
   templates/copilot-prompts.json    → $PROJECT/.plan/copilot-prompts.json
   templates/used-patterns.json      → $PROJECT/.plan/used-patterns.json
   templates/model-usage.json        → $PROJECT/.plan/model-usage.json
   ```

f) **Master-Plan persistieren**
   `writeJson("$PROJECT/.plan/master-plan.json", masterPlan)`

g) **Git initialisieren**
   ```bash
   cd "$PROJECT" && git init -q && git add -A && \
     git commit -q -m "chore: initialize <gameName> via game-dev-orchestrator"
   ```

h) **Unity-Watcher deployen** (Teil I, Schritt 28.2)
   ```bash
   cp templates/AutoCompileWatcher.cs.txt \
      "$PROJECT/Assets/Editor/AutoCompileWatcher.cs"
   cp templates/BatchCompile.cs.txt \
      "$PROJECT/Assets/Editor/BatchCompile.cs"
   ```
   Beide Dateien gehören in `Assets/Editor/`, damit sie ausschließlich
   im Editor kompiliert werden und niemals in einem Build landen.

i) **Watcher-Artefakte initialisieren** (Teil I, Schritt 28.2)
   ```bash
   cp templates/unity-status.json "$PROJECT/.plan/unity-status.json"
   : > "$PROJECT/.plan/error-log.jsonl"   # leere NDJSON-Datei
   ```

j) **Aktuelle Phase auf 0 setzen**
   `current-phase.json` enthält bereits `currentPhaseId: 0`. Falls der
   Master-Plan einen abweichenden Start vorsieht, hier patchen.

k) **Erst-Kompilierung im Batchmode** (Teil I, Schritt 28.2 – damit das
   Editor-Script schon einmal kompiliert ist, bevor Phase 1 läuft)
   ```bash
   "$editorBinary" -batchmode -quit -nographics \
     -projectPath "$PROJECT" \
     -logFile     "$PROJECT/.plan/unity-init.log" \
     -executeMethod OpenClaw.BatchCompile.Run
   ```
   Der Exit-Code wird **nicht** als Fehler behandelt – Ziel ist nur,
   `Library/ScriptAssemblies` zu füllen. Falls `editorBinary` fehlt,
   wird dieser Schritt übersprungen.

l) **VS Code öffnen**
   ```bash
   code "$PROJECT"
   ```

m) **Memory-Eintrag anlegen**
   `gamedev-projects.json` mit neuer Project-Row erweitern (siehe
   `memory-system.md`).

## Validierung nach Init

Bevor der Orchestrator nach `EXECUTING` wechselt, prüft er:

| Check                                        | Pflicht | Quelle |
|----------------------------------------------|:-------:|--------|
| `$PROJECT/Assets/Editor/AutoCompileWatcher.cs` | ✓ | h     |
| `$PROJECT/Assets/Editor/BatchCompile.cs`       | ✓ | h     |
| `$PROJECT/.plan/unity-status.json`             | ✓ | i     |
| `$PROJECT/.plan/error-log.jsonl` (existiert)   | ✓ | i     |
| `$PROJECT/.plan/master-plan.json`              | ✓ | f     |
| `$PROJECT/.plan/current-phase.json`            | ✓ | e     |

Schlägt einer der Checks fehl → `INITIALIZING` bleibt aktiv und der
Fehler wird via Telegram gemeldet.

## Idempotenz

Der Initializer ist idempotent: bestehende Dateien werden nur
überschrieben, wenn `--force` gesetzt ist. `error-log.jsonl` wird
**niemals** überschrieben (Append-Only-Vertrag).
