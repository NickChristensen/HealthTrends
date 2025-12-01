# Project Management - Workflow & Issue Tracking

This document covers workflow rules for managing GitHub issues, GitHub Projects, Beads, git operations, and project status tracking.

## Workflow Rules

### Issue Tracking (Hybrid GitHub + Beads)

**GitHub Issues** (Product/Engineering Manager's tool):
- User-facing work: bugs, features, major improvements
- Single source of truth for "what needs to be done"
- User creates and manages these as the PM/EM
- View issues: `gh issue list`
- View specific issue: `gh issue view <number>`

**Beads** (Engineer's internal tool):
- My private task breakdown and dependency tracking
- I create beads issues linked to GitHub via `external_ref: "GH-123"`
- I manage my own workflow without user intervention
- All beads commands available without approval
- Beads issues can exist independently or be linked to GitHub issues

**GitHub Projects** (Organization/tracking tool):
- GitHub Issues in project 1 get enhanced with additional fields
- **Priority field replaces custom labels** (use P0/P1/P2 instead of priority:high/medium/low)
- Status field tracks workflow state (Backlog → Ready → In progress → In review → Done)
- All project field updates done via `gh project` commands

### Starting Work on a GitHub Issue

**IMPORTANT:** Always create a branch before starting work:

1. **Get the GitHub issue number** (e.g., #42)
2. **Create branch** named: `{issue-number}-short-description`
   - Example: `git checkout -b 42-fix-widget-refresh`
   - Example: `git checkout -b 42-dark-mode-colors`
3. **Work on the branch**, commit changes as needed
4. **When done**, use `/merge` command which will:
   - Merge to main
   - Include `fixes #42` in commit message to auto-close the issue

### Work Completion

- **GitHub issue closes when:** Commit with `fixes #123` is pushed to main
- **Beads issues:** I manage independently (open, close, track sub-tasks)
- **Don't be overeager:** User will tell you when work is feature-complete

### Git Commits

- **When closing GitHub issues via commit:**
  - Include `fixes #123` in commit message to auto-close
  - Close corresponding beads issue if it exists
  - Update .beads/issues.jsonl if beads state changed
- **Always include .beads/issues.jsonl in commits if it changed**
  - Add it together with code changes: `git add <files> .beads/issues.jsonl`

### GitHub Projects Integration

**Project Details:**
- Project number: 1
- Project ID: `PVT_kwHOAAldws4BISwl`
- Owner: `@me` (NickChristensen)

**Key Fields:**

| Field | Field ID | Type | Options |
|-------|----------|------|---------|
| Status | `PVTSSF_lAHOAAldws4BISwlzg4y6lw` | Single Select | Backlog (f75ad846), Ready (61e4505c), In progress (47fc9ee4), In review (df73e18b), Done (98236657) |
| Priority | `PVTSSF_lAHOAAldws4BISwlzg4y6oI` | Single Select | P0 (79628723), P1 (0a877460), P2 (da944a9c) |
| Size | `PVTSSF_lAHOAAldws4BISwlzg4y6oM` | Single Select | XS (6c6483d2), S (f784b110), M (7515a9f1), L (817d0097), XL (db339eb2) |

**Workflow Commands:**

```bash
# Add an issue to the project
gh project item-add 1 --owner "@me" --url https://github.com/NickChristensen/HealthTrends/issues/123

# Set priority (use option IDs from table above)
gh project item-edit --id <item-id> --field-id PVTSSF_lAHOAAldws4BISwlzg4y6oI --project-id PVT_kwHOAAldws4BISwl --single-select-option-id 79628723

# Set status
gh project item-edit --id <item-id> --field-id PVTSSF_lAHOAAldws4BISwlzg4y6lw --project-id PVT_kwHOAAldws4BISwl --single-select-option-id 47fc9ee4

# Get item ID from issue URL (list all project items)
gh project item-list 1 --owner "@me" --format json | jq '.items[] | select(.content.number == 123) | .id'
```

**Priority Mapping:**
- P0 (Critical/Urgent) = Beads priority 0-1
- P1 (Normal) = Beads priority 2
- P2 (Low) = Beads priority 3

**Status Mapping:**
- Backlog = Not yet ready to start (has dependencies or unclear requirements)
- Ready = No blockers, can be picked up
- In progress = Actively being worked on (Beads: `in_progress`)
- In review = Code written, awaiting review/testing
- Done = Completed and merged (Beads: `closed`)

**When to Update Project Fields:**
1. **Creating new GitHub issues**: Add to project and set Priority
2. **Starting work**: Update Status to "In progress"
3. **Opening PR**: Update Status to "In review"
4. **Merging**: Status automatically updates to "Done" when issue closes
5. **Priority changes**: Update if urgency changes

**Labels:**
- Priority is managed via GitHub Projects Priority field (P0/P1/P2) - NOT labels
- Type is managed via simple labels: `bug`, `feature`, `improvement`, `chore`
- Old prefixed labels (`priority:*`, `type:*`) have been removed
