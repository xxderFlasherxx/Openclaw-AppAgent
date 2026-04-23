# Modell-Routing (Teil G, Schritt 22)

## Übersicht

Das Modell-Routing entscheidet pro Aufgabe, welches Copilot-Modell
(Haiku / Sonnet / Opus) verwendet wird. Ziel: Kosten und Latenz
optimieren, ohne Code-Qualität zu verlieren.

Das Routing basiert auf:
1. **Aufgaben-Kategorie** (phase.category oder phase.name)
2. **Keyword-Match** im Prompt / Phase-Namen
3. **Retry-Eskalation** (steigende Versuche → stärkeres Modell)
4. **Config-Overrides** in `gamedev-config.json`

## Routing-Tabelle

| Aufgabe / Phase-Kategorie       | Standard-Modell | Begründung                  |
|---------------------------------|-----------------|-----------------------------|
| Boilerplate / Struktur / Config | `haiku`         | Einfach, schnell, günstig   |
| Editor-Scripts                  | `haiku`         | Einfache Unity-API          |
| Datei-/Szenen-Erstellung        | `haiku`         | Triviale Tasks              |
| UI / HUD / Menüs                | `sonnet`        | Standard-Layout & Logik     |
| Standard Game-Logik             | `sonnet`        | Bester Allrounder           |
| Bug-Fix (einfach, CS-Codes)     | `sonnet`        | Standard                    |
| Physik / Collider / Rigidbody   | `opus`          | Braucht Präzision           |
| Prozedurale Generierung         | `opus`          | Komplexe Algorithmen        |
| AI / Pathfinding / Behavior     | `opus`          | Strategisches Denken        |
| Shader / Material / RenderPipe  | `opus`          | Spezialisierte Domäne       |
| Bug-Fix (komplex, Retry >= 3)   | `opus`          | Eskalation nötig            |

## Keyword-Mapping

### Haiku-Keywords (sparsam)
```
structure, setup, config, template, boilerplate, folder,
gitignore, editorconfig, asmdef, project settings,
editor script, editor window, menu item, scene bootstrapper,
file creation, json, readme
```

### Sonnet-Keywords (Default)
```
ui, hud, menu, settings, options, pause, inventory view,
input, controller, movement (basic), camera follow,
audio manager, score, health, timer, gamemanager,
dialogue, save load (einfach)
```

### Opus-Keywords (Premium)
```
physics, rigidbody, wheelcollider, joint, ragdoll,
procedural, noise, perlin, generation, terrain,
ai, pathfinding, navmesh, behavior tree, state machine (komplex),
shader, material, urp, post processing, compute,
optimization, multithread, jobs, burst,
netcode, networking, multiplayer
```

## Routing-Algorithmus

```
FUNKTION: selectModel(phase, retryCount)

  // ── 1) Config-Override prüfen ──────────────────────────────
  IF config.modelRouting.overrides[phase.id] EXISTS:
    RETURN config.modelRouting.overrides[phase.id]

  // ── 2) Retry-Eskalation (höchste Priorität nach Override) ──
  IF retryCount >= config.modelRouting.escalateAtRetry:  // default 3
    RETURN "opus"

  // ── 3) Phase-Kategorie prüfen (explizites Feld) ───────────
  IF phase.category IN ["structure", "setup", "config",
                         "template", "editor"]:
    RETURN "haiku"

  IF phase.category IN ["physics", "procedural", "ai",
                         "shader", "optimization"]:
    RETURN "opus"

  IF phase.category IN ["ui", "menu", "gamelogic"]:
    RETURN "sonnet"

  // ── 4) Keyword-Scoring auf Name + Prompt ──────────────────
  text = (phase.name + " " + phase.copilotPrompt).toLowerCase()

  scores = { haiku: 0, sonnet: 0, opus: 0 }

  FOR EACH kw IN HAIKU_KEYWORDS:
    IF text.contains(kw): scores.haiku += 1

  FOR EACH kw IN SONNET_KEYWORDS:
    IF text.contains(kw): scores.sonnet += 1

  FOR EACH kw IN OPUS_KEYWORDS:
    IF text.contains(kw): scores.opus += 2       // Opus-Keywords stärker gewichtet

  // ── 5) Entscheidung ───────────────────────────────────────
  IF scores.opus >= 2:
    RETURN "opus"
  IF scores.haiku > scores.sonnet AND scores.opus == 0:
    RETURN "haiku"

  RETURN "sonnet"   // Safe Default
```

## Phase-Kategorie-Zuordnung (für Master-Plan)

Günther soll beim Erstellen des Master-Plans eine `category` pro Phase
setzen. Zulässige Werte:

```
structure   → Projektstruktur, Ordner, Config
setup       → Basis-Setup, Package-Manager, Scenes
ui          → UI / HUD / Menüs
gamelogic   → Standard-Spielmechanik
physics     → Physik / Collider / Rigidbody
procedural  → Prozedurale Generierung
ai          → KI, Pathfinding, Behavior
shader      → Shader, Material, Rendering
optimization→ Performance, Profiling
editor      → Unity Editor-Scripts
build       → Build-Pipeline, Deployment
```

Phase 1 ist IMMER `structure`, Phase 10 ist IMMER `build`.

## Logging der Modell-Nutzung

Pro Projekt wird eine Datei `.plan/model-usage.json` geführt (siehe
`templates/model-usage.json`). Nach jedem Copilot-Call wird der Eintrag
inkrementiert:

```
FUNKTION: logModelUsage(model, promptTokens, completionTokens, phaseId)

  usage = readJSON(".plan/model-usage.json")

  usage.models[model].calls += 1
  usage.models[model].promptTokens += promptTokens
  usage.models[model].completionTokens += completionTokens

  // Kostenberechnung (Platzhalter-Preise in config.modelRouting.pricing):
  price = config.modelRouting.pricing[model]   // { inputPer1K, outputPer1K }
  cost = (promptTokens / 1000) * price.inputPer1K
       + (completionTokens / 1000) * price.outputPer1K

  usage.models[model].costUsd += cost
  usage.totalCostUsd += cost

  usage.perPhase[phaseId] = usage.perPhase[phaseId] OR { model, cost }
  usage.lastUpdate = now()

  writeJSON(".plan/model-usage.json", usage)
```

## Integration in die Ausführungsschleife

In `pipeline/execution-loop.md` Schritt 3 ("Copilot-Modell wählen") ersetzt
durch:

```
model = selectModel(currentPhase, currentPhase.retryCount)
logDecision(phaseId, model, reason)   // reason = "keyword-match:opus" etc.
```

Nach Ende der Phase:
```
logModelUsage(model, ...tokens..., phaseId)
```

## Config-Beispiel

```json
"modelRouting": {
  "enabled": true,
  "escalateAtRetry": 3,
  "defaultModel": "sonnet",
  "overrides": {
    "1": "haiku",
    "10": "haiku"
  },
  "pricing": {
    "haiku":  { "inputPer1K": 0.00025, "outputPer1K": 0.00125 },
    "sonnet": { "inputPer1K": 0.003,   "outputPer1K": 0.015   },
    "opus":   { "inputPer1K": 0.015,   "outputPer1K": 0.075   }
  }
}
```

## Schwachstellen / Edge Cases

- **Unbekanntes Genre / freie Prompts**: Fallback auf Sonnet.
- **Null-Phase.name**: Validation schon im Planning; trotzdem Default.
- **Preis-Updates**: Pricing in Config zentral änderbar, nicht hartkodiert.
- **Opus-Overuse durch Keyword "game"**: Keyword "game" NICHT in Opus-Liste.
- **Retry-Eskalation Loop**: Wenn Opus dreimal scheitert → User-Eskalation
  (siehe `error-correction.md`, Stufe 5).
