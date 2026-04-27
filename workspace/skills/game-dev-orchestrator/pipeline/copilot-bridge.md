# Copilot-Bridge (Teil H, Schritt 25-26)

## Übersicht

Hans übergibt einen von Günther formulierten Prompt an den VS Code
Copilot. Da keine Methode zu 100% universell funktioniert, wird eine
**Adapter-Kette** mit sauberem Fallback verwendet. Außerdem wird der
zurückkommende Code vor dem Akzeptieren bereinigt und validiert.

Zielumgebung: Linux (vboxuser-Host). Statt AppleScript werden
`xdotool` (X11) bzw. `ydotool`/`wtype` (Wayland) verwendet.

```
+--------+    Prompt   +-----------+   Code   +----------+
| Hans   | ─────────▶  | Adapter A | ───────▶ | Datei    |
|        |             |  file-inj.|          | im Repo  |
|        |  fallback   +-----------+          +----------+
|        | ──────────▶ | Adapter B |
|        |             |  gh-cli   |
|        | last resort +-----------+
|        | ──────────▶ | Adapter C |
|        |             |  ui-auto  |
+--------+             +-----------+
```

Aufruf in der Pipeline:

```
status = callCopilotBridge(phase, copilotPrompt, targetFiles, projectPath)
```

`callCopilotBridge()` arbeitet die Reihenfolge in
`gamedev-config.json -> copilotBridge.fallbackChain` ab. Sobald ein
Adapter ein "ok" liefert UND die `Accept-Policy` (siehe unten) erfüllt
ist, wird abgebrochen. Andernfalls wird der nächste Adapter probiert.

---

## Adapter A: "file-injection" (Standard, deterministisch)

**Voraussetzung:** VS Code Workspace ist bereits offen
(`chat.agent.enabled: true` in den User-Settings, Copilot Agent Mode
verfügbar).

**Ablauf:**

1. Hans erstellt jede Zieldatei mit einem **Prompt-Header-Kommentar**
   am Anfang (siehe Schritt 8.1 / `execution-loop.md` →
   `buildPromptHeader`).
2. Hans schreibt zusätzlich in den Workspace-Ordner die Datei
   `.plan/copilot-task.md` mit dem aktuellen Prompt
   (Phase, Ziel-Dateien, Architekt-Prompt, Constraints).
3. Hans triggert den Copilot Agent Mode per CLI-Command:

   ```bash
   # bevorzugter Weg: gespeicherter VS Code Task
   code --command "workbench.action.tasks.runTask" \
        --args '{"task":"copilot-run-phase"}'

   # Fallback-Command (Inline-Editor öffnen):
   code --command "github.copilot.interactiveEditor.explain"
   ```

4. Der Task `copilot-run-phase` (in `.vscode/tasks.json` des
   Game-Projekts) ruft intern `chat.openAgent` mit dem Inhalt von
   `.plan/copilot-task.md` als Prompt auf.

**Erfolgskriterium:** Alle Pfade in `phase.expectedFiles` wurden
innerhalb des Phasen-Timeouts geschrieben/verändert UND
`extractCleanCode` (siehe unten) liefert pro Datei `accepted=true`.

**Polling:** alle `copilotBridge.pollIntervalSeconds` Sekunden, bis
`copilotBridge.timeoutSeconds` erreicht ist.

---

## Adapter B: "gh-copilot-cli" (Fallback)

**Voraussetzung:**

```bash
gh auth status
gh extension install github/gh-copilot
```

**Ablauf:**

```bash
# Shell-Snippets (Build-Skripte etc.):
gh copilot suggest -t shell --no-input "<PROMPT>"

# Tatsächliche C#-Dateien (über models-API):
cat prompt.md | gh models run claude-sonnet-4.6 > out.cs
```

Dieser Adapter ist nur sinnvoll für **Dateien ohne
Workspace-Kontext** (Utility-Klassen, Templates). Komplexe
Phasen, die existierenden Code referenzieren, sollten nicht über
Adapter B laufen, da `gh models` keinen Editor-Workspace kennt.

---

## Adapter C: "ui-automation" (Notfall-Fallback)

**Voraussetzung:** `DISPLAY` gesetzt, X11- oder Wayland-Compositor
mit `xdotool`, `ydotool` oder `wtype`. `xclip`/`wl-copy` für die
Zwischenablage.

**Referenz-Befehl (X11):**

```bash
xdotool search --name "Visual Studio Code" windowactivate \
  --sync key --clearmodifiers ctrl+alt+i
sleep 0.5
xclip -selection clipboard -i <<< "<PROMPT>"
xdotool key --clearmodifiers ctrl+v
xdotool key Return
```

**Wayland-Variante:**

```bash
ydotool key 29:1 56:1 23:1 23:0 56:0 29:0   # Strg+Alt+I
sleep 0.5
wl-copy < prompt.txt
ydotool key 29:1 47:1 47:0 29:0             # Strg+V
ydotool key 28:1 28:0                       # Enter
```

**Timing-Puffer:** 500-1500 ms zwischen Aktionen
(`copilotBridge.uiAutomation.typingDelayMs`).
Nur aktivieren, wenn Adapter A+B explizit fehlgeschlagen sind
(`copilotBridge.uiAutomation.enabled=true`).

---

## Konfiguration

Die Adapter-Auswahl wird über `gamedev-config.json` →
`copilotBridge` gesteuert:

```json
"copilotBridge": {
  "preferredAdapter": "file-injection",
  "fallbackChain": ["file-injection", "gh-copilot-cli", "ui-automation"],
  "vscodeWorkspacePath": null,
  "taskName": "copilot-run-phase",
  "uiAutomation": {
    "enabled": false,
    "tool": "xdotool",
    "display": ":0",
    "typingDelayMs": 25
  },
  "timeoutSeconds": 180,
  "pollIntervalSeconds": 3
}
```

`vscodeWorkspacePath: null` bedeutet "verwende `projectPath` der
aktuellen Phase". Wenn explizit gesetzt, muss der Pfad existieren -
sonst wird der Adapter mit Fehler `vscodeWorkspacePath_missing`
übersprungen.

---

## Extraction (Schritt 26): Code-Bereinigung

Nach jedem Adapter-Lauf MUSS `extractCleanCode(rawFile, expectedFile)`
aufgerufen werden, bevor die Datei als "fertig" gilt.

```
FUNKTION: extractCleanCode(rawFile, expectedFile)

  1. content = readFile(rawFile)

  2. Markdown-Fences strippen:
     IF content beginnt mit "```csharp" oder "```cs" oder "```":
       entferne nur die ÄUSSERSTE Hülle
       (innere ``` in Strings/Kommentaren bleiben unangetastet)
     END

  3. Preambles entfernen:
     Lösche führende Zeilen die mit folgenden Mustern beginnen:
       "Hier ist dein Code", "Here is the code",
       "Sure, ", "Of course, ", "I'll generate",
       "Let me write", "Below is", "Voici"

  4. C#-Sanity-Checks:
     a) Genau N "public class|struct|enum|interface" Definitionen,
        wobei N = phase.expectedClassesPerFile[expectedFile]
        (Default: 1)
     b) Geschweifte Klammern { } sind balanced (count("{")==count("}"))
     c) Alle "using"-Statements stehen oben (vor erster
        class/struct/namespace-Deklaration)
     d) Datei-Größe <= codeExtraction.maxFileSizeKb

  5. Verbotene Tokens:
     KEINER der folgenden Strings darf vorkommen:
       "TODO-COPILOT", "PLACEHOLDER", "<PROMPT>",
       "your code here", "implementiere dies",
       "// ... rest of code", "...existing code..."

  6. Atomar zurückschreiben:
     - Schreibe Inhalt nach <expectedFile>.tmp
     - File.Replace nach <expectedFile> (atomic rename)

  7. Diff loggen:
     git diff --no-color <expectedFile> > <diffDir>/phaseN-<basename>.diff
     (Falls kein Git-Repo: einfacher unified diff via `diff -u`)

  RETURN { accepted: bool, reason: string|null,
           bytesWritten: int, classesFound: int }

ENDE
```

Konfiguration in `gamedev-config.json`:

```json
"codeExtraction": {
  "stripMarkdownFences": true,
  "stripPreambles": true,
  "requireBalancedBraces": true,
  "maxFileSizeKb": 200,
  "diffDir": ".plan/copilot-diffs",
  "forbiddenTokens": [
    "TODO-COPILOT", "PLACEHOLDER", "<PROMPT>",
    "your code here", "implementiere dies",
    "// ... rest of code", "...existing code..."
  ]
}
```

---

## Accept-Policy

Eine Phase gilt **nur dann** als erledigt, wenn ALLE folgenden
Bedingungen erfüllt sind:

```
accepted = (
  all(expectedFiles exist) AND
  all(expectedFiles changed within phase.timeoutSeconds) AND
  for each f in expectedFiles: extractCleanCode(f).accepted == true AND
  no file contains forbidden tokens (siehe codeExtraction.forbiddenTokens)
)
```

## Rejection-Handling

Wenn `accepted == false`, schaltet der Master-Orchestrator in den
Zustand `CORRECTING` (siehe `master-orchestrator.md`). Der
`reason`-String aus `extractCleanCode` wird mitgegeben:

| Reason                | Bedeutung                                       |
|-----------------------|-------------------------------------------------|
| `extraction_failed`   | Sanity-Check fehlgeschlagen (Klassen/Klammern)  |
| `timeout`             | Datei wurde in der Zeit nicht geschrieben       |
| `unchanged`           | Datei existiert, wurde aber nicht modifiziert   |
| `forbidden_token`     | Verbotenes Schlüsselwort im Code                |
| `unbalanced_syntax`   | { und } stimmen nicht überein                   |
| `oversized`           | Datei größer als `maxFileSizeKb`                |

Dieser Reason fließt in die Fehler-Analyse von Günther
(`error-correction.md`, Schritt 15) als zusätzlicher Kontext ein.

---

## Aufruf in der Execution-Loop

Im Pseudo-Code von `execution-loop.md` ersetzt der folgende Block den
früheren `IF config.automation.method == ... ELSE ...`-Switch:

```
// Schritt 5 (modifiziert) - Bridge mit Fallback-Kette
bridgeResult = callCopilotBridge({
  phase:        phase,
  prompt:       copilotPrompt,
  targetFiles:  newFiles + modifiedFiles,
  projectPath:  projectPath,
  config:       config.copilotBridge
})

IF bridgeResult.status == "accepted":
  // alle Files clean + extracted
  proceed to VERIFYING
ELSE:
  // bridgeResult.reason fließt in Error-Korrektur
  triggerCorrection(phase, bridgeResult.reason, bridgeResult.adapterUsed)
END
```
