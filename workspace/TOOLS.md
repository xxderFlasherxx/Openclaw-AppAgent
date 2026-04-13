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

### Game Development

- Projekte-Ordner: ~/GameDev-Projekte/
- Bevorzugte Engine: Unity mit URP (Universal Render Pipeline)
- Unity Version: 2022.3 LTS
- Build Target: StandaloneLinux64
- Copilot-Modell für Code: Claude Sonnet 4.6
- Copilot-Modell für komplexe Logik: Claude Opus
- Copilot-Modell für Quick-Fixes: Claude Haiku
- Architekt-Modell (Günther): kimi-k2.5 via Ollama Cloud
- Config: workspace/skills/game-dev-orchestrator/gamedev-config.json
- Skill: game-dev-orchestrator
