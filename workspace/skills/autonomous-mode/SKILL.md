---
name: autonomous-mode
description: Autonomous self-improvement and task execution mode for the AI assistant. Triggers when the user wants the agent to work autonomously, iterate on itself, perform background tasks, or develop new capabilities. Use for: continuous self-improvement, skill development, background monitoring, periodic checks, research tasks, code iteration, and autonomous project work.
---

# Autonomous Mode

Enables autonomous operation where the agent continuously works on self-improvement, background tasks, and skill development without requiring constant user input.

## Core Philosophy

The agent should be **proactive, not reactive**. When idle, work on:
1. **Skill improvement** — Refactor, document, extend existing skills
2. **New capabilities** — Research and build useful features
3. **Background monitoring** — Check emails, calendar, trading, etc.
4. **Documentation** — Update MEMORY.md, daily logs, project status
5. **Code quality** — Review and improve own implementations

## Autonomous Task Categories

### 1. Skill Development (High Priority)
- Review existing skills for gaps or bugs
- Refactor skills for better structure
- Create new skills for recurring tasks
- Move repetitive code to reusable scripts

### 2. Memory & Documentation (Daily)
- Review `memory/YYYY-MM-DD.md` files from last 7 days
- Distill important learnings into `MEMORY.md`
- Update `IDENTITY.md` if personality evolved
- Document new tools or integrations in `TOOLS.md`

### 3. Background Monitoring (Every 30 min via heartbeat)
- Check for important emails
- Monitor calendar for upcoming events
- Track trading positions/watchlists (if configured)
- Check git status, commit pending changes

### 4. Research & Learning (When idle)
- Research new APIs or tools mentioned by user
- Learn about technologies relevant to user's interests
- Document findings in references/

### 5. Code Quality (Weekly)
- Review own code for efficiency
- Add error handling
- Improve error messages
- Add logging

## Execution Workflow

### When Heartbeat Triggers (every ~30 min):
1. Read `memory/heartbeat-state.json` for last check timestamps
2. Rotate through check categories
3. Perform 2-4 background tasks silently
4. If important finding → ALERT user
5. If routine work → Log to memory/YYYY-MM-DD.md
6. Update heartbeat-state.json

### When User Explicitly Activates Autonomous Mode:
1. Check current project status (scan workspace)
2. Identify next logical task
3. Execute it
4. Report back with results
5. Suggest follow-up tasks

## State Tracking

Maintain state in `memory/autonomous-state.json`:
```json
{
  "activeProjects": [{
    "name": "string",
    "status": "in_progress|blocked|completed",
    "lastAction": "string",
    "nextStep": "string"
  }],
  "backlog": ["string"],
  "completedToday": ["string"],
  "focusArea": "string"
}
```

## Autonomous Mode Activation

### Via Heartbeat (automatic)
- System triggers every ~30 minutes
- Agent reads this skill and executes checklist
- User gets notified only for important findings

### Via Explicit Command
User can activate with:
- "Enter autonomous mode"
- "Work autonomously on..."
- "Continue this project"
- "Analyze X in background"

## Safety Rules

- **Never** make external actions (email, posts) without approval
- **Log everything** to memory/ files for accountability
- **Ask before** destructive operations (delete, overwrite)
- **Stay within** workspace and configured tools
- **Respect quiet hours** (configurable, default: 23:00-08:00)

## Success Metrics

Track in memory/autonomous-metrics.json:
- Skills created/refactored
- Background checks completed
- Documentation updates
- Autonomous hours logged
- User-initiated vs autonomous task ratio

## Interaction Modes

### Proactive Mode (default)
Agent periodically suggests tasks based on:
- Detected patterns in user requests
- Gaps in current capabilities
- Pending items in backlog

### Reactive Mode (on request)
User specifies task, agent executes autonomously with periodic updates

### Hybrid Mode (recommended)
- Agent works autonomously on low-risk tasks
- Requests input for decisions requiring judgment
- Provides summaries of background work

## Getting Started

When user asks for autonomous mode:
1. Read current MEMORY.md for context
2. Check memory/autonomous-state.json for active projects
3. Scan workspace for current state
4. Recommend first action
5. Execute and report results
