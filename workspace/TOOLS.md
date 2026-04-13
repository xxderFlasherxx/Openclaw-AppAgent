# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.

---

## Game Development

### Konfiguration
- **Config-Datei:** `skills/game-dev-orchestrator/gamedev-config.json`
- **Projekte-Ordner:** `/home/vboxuser/GameDev-Projekte/`
- **Templates:** `/home/vboxuser/GameDev-Projekte/_templates/`

### Engine & Tools
- **Engine:** Unity 2022.3 LTS mit URP (Universal Render Pipeline)
- **Code-Sprache:** C# (.NET)
- **IDE:** VS Code mit GitHub Copilot
- **Build-Target:** StandaloneLinux64 (Linux VirtualBox System)

### KI-Rollen (3-Agenten-System)
- **Hans (OpenClaw/Gizmo):** Orchestrator — steuert Ablauf, erstellt Dateien, führt Befehle aus
- **Günther (Ollama Cloud / Kimi K2.5):** Architekt — plant Phasen, formuliert Prompts, analysiert Fehler
- **Copilot (Claude Sonnet 4.6):** Programmierer — schreibt den eigentlichen C#/Unity-Code

### Copilot Modell-Auswahl
- **Standard-Code:** Claude Sonnet 4.6
- **Komplexe Logik (Physik, KI, prozedurale Generierung):** Claude Opus
- **Schnelle kleine Aufgaben (Boilerplate, UI):** Claude Haiku

### Unity CLI (Linux)
- Projekt erstellen: `Unity -createProject [pfad] -quit -batchmode`
- Build: `Unity -batchmode -projectPath [pfad] -executeMethod AutoBuilder.Build -buildTarget StandaloneLinux64 -quit -logFile build.log`
- Tests: `Unity -batchmode -projectPath [pfad] -runTests -testResults results.xml -quit`

### Skill: game-dev-orchestrator
- **Aktivierung:** User sagt "Bau mir ein Spiel..." / "Erstelle ein Game..."
- **Phasen:** 10-Phasen-Raster (Planung → Build)
- **Zustandsdateien:** `.plan/` Ordner im jeweiligen Projektverzeichnis
- **Fehlerkorrektur:** Max 5 Versuche pro Phase, danach User benachrichtigen
