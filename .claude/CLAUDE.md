# Health Trends - Technical Documentation

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

### Documentation
- **apple-docs MCP server is available** for Swift, SwiftUI, Swift Charts, and other Apple framework documentation
  - Use it to look up APIs, best practices, and implementation details
  - Available tools: search_apple_docs, get_apple_doc_content, list_technologies, etc.

## Development Environment
- **Default Simulator**: Always use iPhone 17 Pro for builds and testing

## Xcode Project Management

### Adding Targets (Widget Extensions, App Extensions, etc.)
**Avoid manually editing `project.pbxproj`** when adding new targets like widget extensions. Manual editing is error-prone and leads to issues:
- Missing required Info.plist keys (like `NSExtension` dictionary)
- File synchronization conflicts with File System Synchronized Groups
- Bundle identifier validation problems
- Build phase configuration errors

**Better approaches:**
1. **Preferred**: Use Xcode GUI to add targets (File > New > Target > Widget Extension)
2. **Alternative**: Use scaffolding tools like `mcp__XcodeBuildMCP__scaffold_ios_project`
3. **Last resort**: Only manually edit `.pbxproj` for small tweaks after target is created

## Terminology
This document defines the key metrics used throughout the app to avoid confusion.

### "Today"
**Definition:** Cumulative calories burned from midnight to the current time.

**Example:** At 1:00 PM, if you've burned:
- 0-1 AM: 10 cal
- 1-2 AM: 5 cal
- ...
- 12-1 PM: 217 cal

Then "Today" = 467 cal (total from midnight to 1 PM)

**In Code:**
- `todayTotal: Double` - Current cumulative total
- `todayHourlyData: [HourlyEnergyData]` - Cumulative values at each hour
  - Example: `[10, 15, ..., 250, 467]` (running sum)

---

### "Average"
**Definition:** The average cumulative calories burned BY each hour, calculated across the last 30 days (excluding today).

**Example:** At 1:00 PM:
- Day 1: burned 400 cal by 1 PM
- Day 2: burned 380 cal by 1 PM
- ...
- Day 30: burned 395 cal by 1 PM

Then "Average" at 1 PM = (400 + 380 + ... + 395) / 30 = 389 cal

**In Code:**
- `averageHourlyData: [HourlyEnergyData]` - Average cumulative values at each hour
  - For hour H: average of (day1_total_by_H + day2_total_by_H + ... + day30_total_by_H) / 30
  - Example: `[8, 12, ..., 350, 389]` (cumulative averages)

**Display:** Show the value at the current hour (e.g., 389 cal at 1 PM)

---

### "Total"
**Definition:** The average of complete daily totals from the last 30 days (excluding today).

**Example:**
- Day 1: burned 1,050 cal (full day)
- Day 2: burned 1,020 cal (full day)
- ...
- Day 30: burned 1,032 cal (full day)

Then "Total" = (1,050 + 1,020 + ... + 1,032) / 30 = 1,034 cal

**In Code:**
- `projectedTotal: Double` - Average of complete daily totals
  - This represents where you'd end up at midnight if you follow the average pattern

**Visual:** Shown as a horizontal green line on the chart and a green statistic

---

## Why This Matters

These three metrics answer different questions:

1. **"Today"**: How much have I burned so far?
2. **"Average"**: How much had I typically burned by this time of day?
3. **"Total"**: If I follow my average pattern, where will I end up?

The distinction between "Average" (cumulative by hour) and "Total" (daily average) is critical for accurate graphing and projections.
