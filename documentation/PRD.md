# HealthTrends - Product Requirements Document

**Version:** 1.0
**Last Updated:** December 11, 2024
**Status:** Living Document

---

## Executive Summary

HealthTrends is a widget-first iOS fitness tracking app that helps users understand their daily active energy patterns by comparing today's activity against historical averages. The app provides minimal UI—all user-facing functionality lives in home screen widgets that display real-time calorie burn data with comparative visualizations.

**Core Value Proposition:** Answer the question "Am I ahead or behind my typical pace for this day of week?" at a glance.

---

## Problem Statement

Fitness tracking apps typically show raw numbers (calories burned today, move streak, etc.) without context. Users don't know if their current activity level is normal for them or if they're falling behind. The Apple Fitness app shows the Move Ring but doesn't provide historical comparison or predictive insights. The Health app does offer a cumulative energy chart, but it requires opening the app and navigating to Active Energy—not glanceable from the home screen.

**HealthTrends solves this by:**
- Comparing today's activity against weekday-specific historical averages
- Visualizing trends throughout the day with a clear chart
- Projecting end-of-day totals based on typical patterns
- Surfacing this insight directly on the home screen via widgets

---

## Product Goals

1. **Reduce friction to insight:** Zero taps required—widget shows status at a glance
2. **Contextual awareness:** Account for weekday variability (weekends ≠ weekdays)
3. **Predictive guidance:** Help users understand if they'll hit their move goal

---

## Core Metrics & Terminology

The app displays three key metrics that answer different questions:

### 1. "Today"
**Definition:** Cumulative active energy (calories) burned from midnight to Data Time (the timestamp of the most recent HealthKit data).

**User Question Answered:** "How much have I burned so far?"

---

### 2. "Average"
**Definition:** The average cumulative calories burned BY each hour, calculated across the last ~10 occurrences of the current weekday (excluding today).

**Example:** At 1:00 PM on a Saturday:
- Saturday 1: burned 400 cal by 1 PM
- Saturday 2: burned 380 cal by 1 PM
- ...
- Saturday 10: burned 395 cal by 1 PM

Then **"Average" at 1 PM = 389 cal** (average across those 10 Saturdays)

**User Question Answered:** "How much had I typically burned by this time of day?"

**Note:** Uses weekday filtering to account for schedule variability—Saturdays are compared to Saturdays, Mondays to Mondays, etc.

---

### 3. "Total" (Projected End-of-Day)
**Definition:** The average of complete daily totals from the last ~10 occurrences of the current weekday (excluding today).

**Example:** On a Saturday:
- Saturday 1: burned 1,050 cal (full day)
- Saturday 2: burned 1,020 cal (full day)
- ...
- Saturday 10: burned 1,032 cal (full day)

Then **"Total" = 1,034 cal** (average daily total for Saturdays)

**User Question Answered:** "If I follow my average pattern, where will I end up?"

---

### 4. "Data Time"
**Definition:** The timestamp of the most recent HealthKit data sample. Typically matches the current time, but may lag during sync delays (e.g., waiting for Apple Watch to sync to iPhone, or iPhone to sync in background).

**Technical Purpose:**
- Marks the boundary on the chart between actual data (before Data Time) and projected averages (after Data Time)
- Used for interpolating average values at the precise moment of latest data
- Determines data staleness (is data from today or yesterday?)

**Visual Representation:** Vertical line on chart with HH:MM timestamp label

---

### Why These Metrics Matter

Each metric serves a distinct purpose:
- **"Today"** = Current progress (actual data up to Data Time)
- **"Average"** = Historical context (am I on pace?)
- **"Total"** = Projected outcome (where am I headed?)
- **"Data Time"** = Temporal anchor (when is this data from?)

Together, they enable users to make informed decisions about their activity level throughout the day.

---

## Feature Requirements

### F1: Home Screen Widgets

**Priority:** P0 (Core Feature)

**Description:** Display active energy data in three widget sizes with chart visualization and key statistics.

**Widget Sizes:**
- **System Medium:** Horizontal layout (stats left, chart right)
- **System Large:** Vertical layout (stats top, chart bottom)
- **System Extra Large:** Full-screen vertical layout

**Displayed Information:**
- Three header statistics (Today, Average, Total) with color-coded indicators
- Multi-line chart showing:
  - Today's cumulative calories
  - Average (split into two segments: before Data Time and after Data Time with different opacity)
  - Move goal reference (dashed horizontal line)
  - Vertical marker at Data Time with timestamp
  - Dots at Data Time position for today/average values
- Smart X-axis labels (midnight, Data Time, midnight)
- Auto-scaled Y-axis

**Update Frequency:**
- Refresh as frequently as possible (balanced with battery impact)
- Special midnight refresh to reset "Today" to zero

**Widget Interactions:**
- **Tap action (configurable):**
  - Option 1: Refresh widget data immediately
  - Option 2: Open main app

---

### F2: HealthKit Integration

**Priority:** P0 (Core Feature)

**Description:** Query Apple Health for active energy data and move goals.

**Required Permissions:**
- Read: Active Energy Burned
- Read: Activity Summary (for Move goal)

**Query Strategy:**
- **Today's data:** Live HealthKit query when available, falls back to cache when queries fail (device locked, etc.)
- **Average data:** Cached per weekday (minimize queries, improve widget performance)
- **Graceful degradation:** Widget shows cached data or average-only view when HealthKit unavailable

**Data Handling:**
- Filter weekday-specific data (last ~10 occurrences)
- Calculate hourly cumulative totals
- Interpolate values at Data Time for smooth visualization
- Handle midnight boundary transitions correctly

---

### F3: Main App (Minimal UI)

**Priority:** P0 (Core Feature)

**Description:** Provide single-purpose app for granting HealthKit permissions.

**Requirements:**
- Button to request HealthKit authorization
- All other UI elements are optional filler to explain the app's purpose.

**Rationale:** Widget-first design—app exists only to request permissions. 

---

### F4: Data Caching & Sharing

**Priority:** P0 (Core Feature)

**Description:** Share data between app and widget using App Group container.

**Shared Data:**
- Today's total calories
- Move goal value
- Hourly breakdowns (today and average)
- Latest sample timestamp (data freshness indicator)

**Cache Strategy:**
- App writes to shared container after HealthKit queries
- Widget reads from shared container as fallback when queries fail
- Weekday-specific cache (7 separate caches, one per weekday)

> **Technical Implementation:** See [caching-strategy.md](./caching-strategy.md) for detailed cache architecture, staleness checks, fallback behavior, and performance characteristics.

---

### F5: Widget Authorization State

**Priority:** P0 (Core Feature)

**Description:** Handle unauthorized state gracefully.

**Unauthorized Widget Display:**
- Message: "Health Access Required"
- Call-to-action: Tap to open app
- No data visualization shown

**Note:** This state is most commonly encountered by new users who have added the widget before granting HealthKit permissions, hence the clear call-to-action to open the app.

**Authorized Widget Display:**
- Full chart and statistics
- All features enabled

---

## User Experience Requirements

### UX1: Glanceable Information

Users should understand their activity status in <3 seconds without tapping the widget.

**Success Criteria:**
- Header statistics are large and readable
- Color coding is intuitive and consistent
- Chart shows clear visual comparison

---

### UX2: Contextual Accuracy

Data must account for weekday variability—comparing apples to apples.

**Success Criteria:**
- Averages calculated from same weekday only
- Move goals respect weekday-specific settings
- Midnight boundaries handled correctly

---

### UX3: Real-Time Freshness

Widget should feel "live" without excessive battery drain.

**Success Criteria:**
- Frequent refresh interval balances freshness with battery impact
- Data Time marker clearly shows when data is from (allows users to assess freshness at a glance)

---

### UX4: Graceful Degradation

Widget should show useful information even when HealthKit is unavailable.

**Success Criteria:**
- Fall back to cached data when device locked
- Show average even if today's data unavailable
- Never show blank/broken widget

---

## Technical Constraints

### Platform Requirements
- iOS 26+
- HealthKit-enabled device

### Code Architecture
- Shared Swift Package for app/widget common code
- @Observable pattern for state management
- Swift Concurrency (async/await) for HealthKit queries

---

## User Scenarios

### Scenario 1: Normal Operation (Fresh Data)

**Context:** Saturday, 3:00 PM with up-to-date HealthKit data

**HealthKit Data:**
- Today (this Saturday): 550 cal burned by 3 PM
- Last 10 Saturdays by 3 PM: [520, 490, 510, 530, 500, 515, 505, 525, 510, 495]
- Last 10 Saturdays full-day totals: [1050, 980, 1020, 1040, 990, 1010, 1000, 1030, 1015, 995]
- Move goal for Saturdays: 900 cal

**Widget Display:**
- **Today:** 550 cal (actual progress)
- **Average:** 510 cal (average of the 10 values above)
- **Total:** 1,013 cal (average of full-day totals)
- **Move Goal:** 900 cal (dashed line on chart)

**User Insight:** "I've burned 550 cal so far, which is 40 cal ahead of my typical Saturday pace at 3 PM. If I continue my average pattern, I'll finish the day around 1,013 cal, which exceeds my 900 cal move goal."

---

### Scenario 2: Delayed Sync

**Context:** Saturday, 3:00 PM, but HealthKit data last updated at 2:15 PM (45 minutes ago)

**HealthKit Data:**
- Data Time: 2:15 PM (45 minutes old)
- Today (this Saturday): 480 cal burned by 2:15 PM
- Last 10 Saturdays by 2:15 PM: [average calculations same as Scenario 1]
- Last 10 Saturdays full-day totals: [same as Scenario 1]
- Move goal for Saturdays: 900 cal

**Widget Display:**
- Data Time marker shows: 2:15 PM
- Chart displays data through 2:15 PM
- Today's line stops at 2:15 PM
- Average line continues to midnight (projected)

**User Experience:** User sees slightly outdated data but can clearly identify when it's from via the Data Time marker. Widget functions normally with last available data.

---

### Scenario 3: Stale Data (Previous Day)

**Context:** Saturday, 10:00 AM, but last HealthKit data is from Friday 11:00 PM (11 hours ago, different day)

**HealthKit Data:**
- Data Time: Friday 11:00 PM
- Latest cached data is from yesterday

**Widget Display:**
- Shows average-only view for Saturday
- No "Today" line (stale data from wrong day)
- Shows Saturday's average pattern

**User Experience:** User understands there is no available data for today, and needs to open app or wait for sync. Widget remains useful by showing expected pattern for today.

---

### Scenario 4: First-Time User (No Authorization)

**Context:** User has added widget but hasn't granted HealthKit permissions

**Widget Display:**
- Message: "Health Access Required"
- Call-to-action: Tap to open app
- No chart or statistics shown

**User Experience:** Clear path to grant permissions via the app.
