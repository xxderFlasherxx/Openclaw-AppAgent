# HEARTBEAT.md - Periodic Autonomous Tasks

## Overview
This file configures periodic tasks that run every ~30 minutes via heartbeat mechanism.
Agent should read this file and execute the checklist.

## When to Trigger Alerts (send to user)
1. **Email**: Urgent unread messages (flagged/marked important)
2. **Calendar**: Events starting within next 2 hours
3. **Trading**: Significant price movements (if configured)
4. **Errors**: Failed autonomous tasks or stuck processes

## Background Work (silent, no alert unless error)
Rotate through these tasks, ~2-4 per heartbeat cycle:

### Daily Rotation (track in memory/heartbeat-state.json)
- Check email for unread/important
- Check calendar for upcoming events
- Review memory/ files from last 7 days, update MEMORY.md
- Review own skills for improvement opportunities
- Check workspace git status, commit if needed
- Review TODO items in memory/todo.md

### Trading Analysis (if configured)
- Check portfolio/watchlist
- Analyze price movements
- Update trading journal

### Skill Development
- Identify gaps in current skills
- Research new skill ideas
- Document learnings

## Output
- Important findings: ACTIVE ALERT to user
- Routine work: Log to memory/YYYY-MM-DD.md silently
- Errors: Log to memory/errors.md with timestamp

## Tracking
Maintain state in: memory/heartbeat-state.json
{
  "lastChecks": {
    "email": null,
    "calendar": null,
    "memoryReview": null,
    "skillsReview": null,
    "gitStatus": null,
    "trading": null
  },
  "cyclesCompleted": 0
}
