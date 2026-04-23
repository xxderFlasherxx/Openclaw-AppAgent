# User-Feedback-Integration (Teil G, Schritt 24)

## Übersicht

Nach Projekt-Fertigstellung bittet Hans den User via Telegram um eine
Bewertung. Das Feedback fließt in die Memory-Systeme (Project Memory +
Pattern Library) und verbessert zukünftige Pläne.

## Zustandsintegration

```
COMPLETE → ARCHIVING → AWAITING_FEEDBACK → DONE
```

`AWAITING_FEEDBACK` hat einen Timeout (default 24h) – danach wird als
"no-rating" archiviert, das Projekt bleibt aber im Memory.

## Feedback-Flow

### Schritt 1: Quick-Rating (1–5 Sterne)

Telegram-Nachricht von Hans:

```
🎮 Spiel "{gameName}" ist fertig!

Build: {buildPath}
Dauer: {duration}
Phasen: {phasesCompleted}/{totalPhases} abgeschlossen
Fehler behoben: {totalErrors}
Kosten: ${totalCostUsd}

Wie findest du es?
1 ⭐ Schlecht, funktioniert kaum
2 ⭐⭐ Geht so, viele Bugs
3 ⭐⭐⭐ OK, spielbar aber simpel
4 ⭐⭐⭐⭐ Gut, macht Spaß
5 ⭐⭐⭐⭐⭐ Super, genau was ich wollte

Antworte mit 1–5 oder überspringen mit /skip.
```

### Schritt 2: Detail-Feedback (Follow-up)

Nur wenn Rating ≤ 3:

```
Schade 😕 – was war schlecht?

(Mehrfachauswahl, z.B. "1 3"):
1) 🐛 Bugs
2) 🧩 Fehlende Features
3) 🐢 Schlechte Performance
4) 🎮 Unverständliche Steuerung
5) 🎨 Grafik
6) 💻 Code-Qualität
7) Anderes (Text)

Oder beschreibe es kurz in eigenen Worten.
```

Nur wenn Rating ≥ 4:

```
Super! 🎉 Was war besonders gut?

(Mehrfachauswahl, z.B. "1 3"):
1) 💻 Code-Qualität
2) 🎮 Spielmechaniken
3) 🎨 Grafik
4) 🚀 Performance

Oder schreib es kurz als Text.
```

### Schritt 3: Speicherung

```
FUNKTION: saveFeedback(projectName, rating, categories, freeText)

  projects = readJSON("workspace/memory/gamedev-projects.json")

  entry = projects.projects.find(p => p.name == projectName)
  IF NOT entry: RETURN

  entry.qualityRating = rating
  entry.feedback = {
    rating: rating,
    categories: categories,       // ["bugs", "performance"]
    freeText: freeText OR null,
    submittedAt: now()
  }

  // Aggregate updaten
  ratings = projects.projects
    | map(p => p.qualityRating)
    | filter(r => r != null)
  projects.aggregate.avgQualityRating = average(ratings)
  projects.aggregate.ratedProjects = length(ratings)

  writeJSON("workspace/memory/gamedev-projects.json", projects)

  // Pattern-Library: Patterns dieses Projekts bewerten
  IF rating <= 2:
    // Patterns die hier genutzt wurden bekommen Penalty
    FOR EACH patternKey IN entry.usedPatterns:
      updatePattern(patternKey, success=false)

  // Bei positivem Rating: Bonus
  IF rating >= 4:
    FOR EACH patternKey IN entry.usedPatterns:
      updatePattern(patternKey, success=true)
```

## Nutzung des Feedbacks

### a) Prompt-Verbesserung

Wenn `feedback.categories` z.B. `"controls"` enthält, wird beim
nächsten Projekt des gleichen Genres der Günther-Prompt ergänzt:

```
"Achtung: In vorherigen Projekten wurde die Steuerung als
 unverständlich bewertet. Lege in Phase-Prompts explizit Wert
 auf: intuitive Tastenbelegung, Tooltip/UI-Hinweis beim Start,
 Rebinding-Option."
```

Mapping Kategorie → Prompt-Hinweis in `templates/feedback-prompt-hints.json`:

```json
{
  "bugs":         "Validierung und Null-Checks in jedem Controller.",
  "missing":      "Feature-Liste aus User-Wunsch 1:1 abarbeiten, nichts weglassen.",
  "performance":  "Object-Pooling, FixedUpdate nur wo nötig, keine GetComponent() in Update.",
  "controls":     "Intuitive Belegung, UI-Hinweis, Rebinding.",
  "graphics":     "URP mit Post-Processing, konsistente Materials.",
  "code":         "Saubere Trennung, keine Monolithen, Kommentare bei Public-API."
}
```

### b) Zeit-Budget-Anpassung

Bei Rating ≤ 2 wird im nächsten gleichen-Genre-Plan der
`timeoutPerPhaseSeconds` um 50% erhöht und `maxRetriesPerPhase` um 2,
damit Günther/Copilot mehr Raum für Qualität haben.

### c) Günther-Kontext

Der Planner-Kontext (siehe `memory-system.md` → `buildPlannerContext`)
wird um die Feedback-Aggregates erweitert:

```
"Statistik gleiches Genre: {n} Projekte, Ø-Rating {avg}/5.
 Häufigste Beschwerden: {top3 Kategorien}."
```

## Telegram-Integration

Hans nutzt seine bestehende Telegram-Infrastruktur (`credentials/telegram-*`,
`telegram/`-Ordner). Die Feedback-Kommandos sind:

| Command             | Aktion                                       |
|---------------------|----------------------------------------------|
| `1` … `5`           | Quick-Rating                                 |
| `/skip`             | Kein Rating                                  |
| Freitext            | wird als `freeText` gespeichert              |
| `/feedback bugs`    | Kategorie-Shortcut                           |

### Listener-Logik (Pseudocode)

```
WHEN state == "AWAITING_FEEDBACK":
  pendingFeedback = {
    projectName: state.currentProject,
    expectingRating: true,
    timeoutAt: now() + 24h
  }

  ON telegram_message(msg):
    IF msg MATCHES /^[1-5]$/:
      pendingFeedback.rating = int(msg)
      pendingFeedback.expectingRating = false
      IF rating <= 3: sendDetailFeedbackBad()
      ELSE IF rating >= 4: sendDetailFeedbackGood()
      ELSE: saveAndDone()

    IF msg == "/skip":
      saveFeedback(projectName, rating=null, ...)
      state → "DONE"

  ON timeout:
    saveFeedback(projectName, rating=null, reason="timeout")
    state → "DONE"
```

## Schwachstellen / Edge Cases

- **User antwortet nicht**: 24h-Timeout → Projekt trotzdem archiviert,
  nur ohne Rating.
- **Projekt wird während AWAITING_FEEDBACK neu gestartet**: Altes
  Feedback wird als `null` persistiert, neues Projekt startet sauber.
- **Mehrfach-Ratings**: Letztes Rating überschreibt das erste.
- **Telegram nicht verfügbar**: Feedback-Block übersprungen; Eintrag
  erhält `feedback.deliveryError = true`.
- **Prompt-Hints-Explosion**: Max 3 Hints pro Genre gleichzeitig, FIFO.
