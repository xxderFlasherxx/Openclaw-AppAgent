# Genre-Erkennung & Planungsphase

## Genre-Erkennung

Hans muss aus dem User-Prompt das passende Genre erkennen, um den
richtigen Genre-Kontext an Günther weiterzugeben.

### Keyword-Regelwerk

```json
{
  "rules": [
    {
      "genre": "driving-game",
      "genreFile": "prompts/game-genres/driving-game.txt",
      "keywords_de": ["fahren", "auto", "wagen", "straße", "drive", "rennspiel", "rennen", "motor", "lkw", "truck", "bus", "taxi", "lieferung", "transport", "geschwindigkeit", "treibstoff", "benzin", "tank"],
      "keywords_en": ["drive", "driving", "car", "vehicle", "race", "racing", "road", "truck", "bus", "speed", "fuel"],
      "referenceGames": ["the long drive", "my summer car", "jalopy", "euro truck", "need for speed", "forza"]
    },
    {
      "genre": "platformer",
      "genreFile": "prompts/game-genres/platformer.txt",
      "keywords_de": ["springen", "plattform", "hüpfen", "2d", "seitlich", "level", "münzen", "gegner", "boss", "leben", "checkpoint"],
      "keywords_en": ["jump", "platform", "2d", "side-scroller", "coins", "enemies", "boss", "lives", "checkpoint"],
      "referenceGames": ["mario", "celeste", "hollow knight", "super meat boy", "rayman", "sonic", "megaman"]
    },
    {
      "genre": "rpg",
      "genreFile": "prompts/game-genres/rpg.txt",
      "keywords_de": ["rpg", "quest", "level-up", "charakter", "erfahrungspunkte", "xp", "inventar", "dialog", "kampf", "magie", "zauber", "schwert", "rüstung", "dungeon", "rolle"],
      "keywords_en": ["rpg", "quest", "level-up", "character", "xp", "inventory", "dialogue", "combat", "magic", "sword", "armor", "dungeon", "role-playing"],
      "referenceGames": ["zelda", "pokemon", "stardew valley", "skyrim", "final fantasy", "diablo", "dark souls", "undertale"]
    },
    {
      "genre": "sandbox",
      "genreFile": "prompts/game-genres/sandbox.txt",
      "keywords_de": ["sandbox", "open world", "bauen", "crafting", "block", "überleben", "survival", "ressourcen", "voxel", "frei", "erkunden", "hunger", "welt"],
      "keywords_en": ["sandbox", "open world", "build", "crafting", "block", "survival", "resources", "voxel", "explore", "hunger", "world"],
      "referenceGames": ["minecraft", "terraria", "raft", "subnautica", "valheim", "rust", "7 days to die", "ark"]
    }
  ]
}
```

### Erkennungs-Algorithmus

```
FUNKTION: detectGenre(userPrompt)

  prompt = lowercase(userPrompt)
  scores = {}

  FÜR JEDE rule IN genreRules:
    score = 0

    // Keywords prüfen (deutsch + englisch)
    FÜR JEDES keyword IN rule.keywords_de + rule.keywords_en:
      WENN prompt ENTHÄLT keyword:
        score += 1
      ENDE
    ENDE

    // Referenz-Spiele prüfen (doppeltes Gewicht)
    FÜR JEDES game IN rule.referenceGames:
      WENN prompt ENTHÄLT game:
        score += 3    // Referenz-Spiele sind starke Indikatoren
      ENDE
    ENDE

    scores[rule.genre] = score
  ENDE

  // Genre mit höchstem Score wählen
  bestGenre = maxBy(scores, "score")

  WENN bestGenre.score == 0:
    // Kein Genre erkannt → Günther fragen
    RETURN askGuentherForGenre(userPrompt)
  ENDE

  WENN bestGenre.score < 2 UND zweitBester.score > 0:
    // Uneindeutig → Günther fragen zur Bestätigung
    RETURN askGuentherForGenre(userPrompt, hint=bestGenre.genre)
  ENDE

  RETURN bestGenre.genre

ENDE
```

### Günther als Fallback

Wenn die Keyword-Erkennung nicht sicher ist, fragt Hans Günther:

```
POST an Günther:
System: "Du bist ein Game-Genre-Experte. Analysiere den folgenden
         Spielwunsch und bestimme das passende Genre."
User: "Spielwunsch: [userPrompt]
       Mögliche Genres: driving-game, platformer, rpg, sandbox
       Antwort als JSON: {\"genre\": \"...\", \"confidence\": 0.0-1.0, \"reason\": \"...\"}"
```

## Planungs-Workflow

### Schritt 1: Master-Plan von Günther anfordern

```
FUNKTION: requestMasterPlan(userPrompt, genre, genreContext)

  // 1. Prompts laden
  systemPrompt = readFile("prompts/architect-system.txt")
  genreInfo = readFile("prompts/game-genres/" + genre + ".txt")

  // 2. Learnings aus vorherigen Projekten laden (falls vorhanden)
  learnings = ""
  IF fileExists("workspace/memory/gamedev-patterns.json"):
    patterns = readJSON("workspace/memory/gamedev-patterns.json")
    learnings = formatLearnings(patterns)
  END IF

  // 3. Anfrage zusammenbauen
  userMessage = """
    NEUES SPIELPROJEKT

    Wunsch des Users:
    {userPrompt}

    Erkanntes Genre: {genre}

    Genre-Kontext:
    {genreInfo}

    {IF learnings}
    Learnings aus vorherigen Projekten:
    {learnings}
    {END IF}

    Erstelle jetzt den 10-Phasen-Plan mit detaillierten Copilot-Prompts
    für jede Phase. Antwort MUSS valides JSON sein.
  """

  // 4. An Günther senden
  response = webFetch("POST", ollamaCloud.baseUrl + "/chat/completions", {
    "model": ollamaCloud.model,
    "messages": [
      {"role": "system", "content": systemPrompt},
      {"role": "user", "content": userMessage}
    ],
    "temperature": ollamaCloud.temperature,
    "max_tokens": ollamaCloud.maxTokens,
    "response_format": {"type": "json_object"}
  })

  // 5. Antwort parsen
  plan = parseJSON(response.choices[0].message.content)

  // 6. Validieren
  validateMasterPlan(plan)

  RETURN plan

ENDE
```

### Schritt 2: Plan validieren

```
FUNKTION: validateMasterPlan(plan)

  // Pflichtfelder prüfen
  ASSERT plan.gameName IS NOT EMPTY
  ASSERT plan.totalPhases == 10
  ASSERT plan.phases IS ARRAY WITH LENGTH 10

  FÜR JEDE phase IN plan.phases:
    ASSERT phase.id IS NUMBER (1-10)
    ASSERT phase.name IS NOT EMPTY
    ASSERT phase.copilotPrompt IS NOT EMPTY AND LENGTH > 50
    ASSERT phase.expectedFiles IS ARRAY WITH LENGTH >= 1
    ASSERT phase.validationCriteria IS ARRAY WITH LENGTH >= 1
  ENDE

  // Logische Prüfungen
  ASSERT plan.phases[0].name ENTHÄLT "Struktur" ODER "Setup" ODER "Basis"
  ASSERT plan.phases[9].name ENTHÄLT "Build" ODER "Final" ODER "Optimierung"

  // Keine doppelten Phase-IDs
  ids = plan.phases.map(p => p.id)
  ASSERT unique(ids).length == 10

  // Abhängigkeiten prüfen
  FÜR JEDE phase IN plan.phases:
    FÜR JEDE dep IN phase.dependencies:
      ASSERT findPhaseByName(plan, dep) EXISTS
      ASSERT findPhaseByName(plan, dep).id < phase.id
    ENDE
  ENDE

  RETURN true

ENDE
```

### Schritt 3: User informieren

Nachdem der Plan erstellt und validiert wurde, sendet Hans eine
Zusammenfassung an den User per Telegram:

```
📝 Plan erstellt für: "[plan.gameName]"
Beschreibung: [plan.gameDescription]
Genre: [genre]

10 Phasen:
1️⃣ [Phase 1 Name]
2️⃣ [Phase 2 Name]
3️⃣ [Phase 3 Name]
4️⃣ [Phase 4 Name]
5️⃣ [Phase 5 Name]
6️⃣ [Phase 6 Name]
7️⃣ [Phase 7 Name]
8️⃣ [Phase 8 Name]
9️⃣ [Phase 9 Name]
🔟 [Phase 10 Name]

Soll ich anfangen? (Ja/Nein/Ändern)
```

### Schritt 4: Auto-Start vs. User-Bestätigung

Gesteuert über `gamedev-config.json → automation.autoStart`:

- **autoStart = false (Standard)**:
  Hans wartet auf explizite Bestätigung:
  - "Ja" / "Start" / "Los" → Beginne mit Phase 1
  - "Ändere Phase X zu..." → Plan anpassen (neuer Günther-Request)
  - "Mehr Details zu Phase X" → Günther soll Phase X erklären
  - "Nein" / "Stopp" → Abbrechen, Plan archivieren

- **autoStart = true**:
  Hans beginnt sofort nach Plan-Erstellung mit Phase 1.
  User wird trotzdem informiert, kann jederzeit "Pause" sagen.

### Plan-Anpassung

Wenn der User eine Phase ändern möchte:

```
FUNKTION: modifyPhasePlan(phaseId, userRequest)

  // An Günther senden
  response = askGuenther(
    System: "Du hast folgenden Plan erstellt: [Plan]
             Der User möchte Phase {phaseId} ändern."
    User: "Änderungswunsch: {userRequest}
           Erstelle nur die geänderte Phase als JSON."
  )

  // Phase im Plan ersetzen
  plan.phases[phaseId - 1] = parseJSON(response)
  saveMasterPlan(plan)
  notifyUser("Phase {phaseId} wurde angepasst.")

ENDE
```

## Projektname generieren

Falls der User keinen expliziten Namen gibt:

```
FUNKTION: generateProjectName(userPrompt)

  // Versuche einen Namen aus dem Prompt abzuleiten
  // z.B. "Bau mir ein Spiel wie The Long Drive mit Katzen"
  // → "CatLongDrive" oder "KatzenFahrspiel"

  // Option 1: Günther fragen
  response = askGuenther(
    "Generiere einen kurzen, einzigartigen Projektnamen (CamelCase,
     keine Sonderzeichen, max 20 Zeichen) für folgendes Spiel:
     [userPrompt]
     Antwort als JSON: {\"projectName\": \"...\"}"
  )

  name = response.projectName

  // Sicherstellen dass der Name valide ist
  name = name.replace(/[^a-zA-Z0-9]/g, "")
  name = name.substring(0, 30)

  // Prüfen ob Ordner schon existiert
  IF directoryExists(config.paths.projectsRoot + "/" + name):
    name = name + "_" + timestamp()
  END IF

  RETURN name

ENDE
```
