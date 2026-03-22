# Autonomous Workflow Patterns

## Pattern: Background Task with State

For tasks that span multiple heartbeats:

1. **Initialize**: Create state file in memory/
2. **Progress**: Update state after each step
3. **Complete**: Finalize, log results, clean up state
4. **Resume**: Use state to continue after interruption

## Pattern: Rotating Checks

Prevent monotony and ensure coverage:

```json
{
  "checkRotation": ["email", "calendar", "memory", "skills", "git", "trading"],
  "currentIndex": 0
}
```

Each heartbeat: increment index, perform check, wrap around.

## Pattern: Autonomous Decision Tree

When choosing what to work on:

1. Any urgent items? (alerts, deadlines)
2. Any user-flagged priorities?
3. Any active projects in progress?
4. Any scheduled recurring tasks?
5. What provides most value for user?

## Pattern: Safe External Actions

For actions with external impact:

- Queue in `pending-actions.json`
- Review with user before execution
- Or: Log draft, mark for user approval
- Execute only after confirmation

## Pattern: Progressive Enhancement

Start simple, iterate:

- v1: Manual checks, log only
- v2: Automated checks, user approval
- v3: Full automation for low-risk tasks

## Pattern: Autonomous Learning

From each autonomous session:

1. What worked?
2. What failed?
3. What was inefficient?
4. Update SKILL.md with learnings
