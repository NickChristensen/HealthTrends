# Health Trends - Technical Documentation

> **For project management workflows** (GitHub issues, GitHub Projects, Beads, git workflow, status tracking, branching strategy): see [PROJECT_MANAGEMENT.md](./PROJECT_MANAGEMENT.md)

## Documentation
- **apple-docs MCP server is available** for Swift, SwiftUI, Swift Charts, and other Apple framework documentation
  - Use it to look up APIs, best practices, and implementation details
  - Available tools: search_apple_docs, get_apple_doc_content, list_technologies, etc.

### Skills Quick Reference

Use these skills for deep-dive expertise when working on specific iOS topics:

| Skill | Use When... |
|-------|-------------|
| `healthkit-queries` | Implementing HealthKit queries, debugging data accuracy, handling date/time edge cases, widget timeline strategies, midnight boundaries, observer queries |
| `swiftui-advanced` | Custom layouts, GeometryReader techniques, animations, PreferenceKey/EnvironmentKey, performance optimization, result builders, custom view modifiers |
| `swift-charts-advanced` | Complex charts, label collision detection, custom axis marks, @ChartContentBuilder patterns, chart performance optimization |

## Development Environment
- **Default Simulator**: Always use iPhone 17 Pro for builds and testing

## iOS Development Practices

### Swift & SwiftUI Fundamentals

**State Management:**
- Prefer `@Observable` over `@ObservableObject` for iOS 17+ (cleaner, more performant)
  - `@Observable` provides fine-grained tracking (updates only when accessed properties change)
  - For iOS 17+ targets, migrate: `@ObservableObject` → `@Observable`, `@Published` → plain properties
  - Keep `@ObservableObject` for compatibility with iOS 16 or framework requirements
- Use `@State` for view-local state, `@Binding` for parent-child communication
- Use `@Environment` for dependency injection (HealthStore, formatters, etc.)
- Keep views pure and stateless when possible—extract complex logic to computed properties or view models

**SwiftUI Patterns:**
- Extract complex views into computed properties or separate view structs
- Use view modifiers for reusable styling (e.g., `.cardStyle()`)
- Leverage `PreviewProvider` extensively—fast iteration beats rebuild cycles
- Consider performance: avoid expensive computations in `body`, use `@State` or `let` bindings

**Swift 6 Concurrency:**
- Use `async/await` for asynchronous operations (HealthKit queries, background tasks)
- Mark types `@MainActor` when they update UI (view models, observable objects)
- Use `Task` for structured concurrency, avoid raw `DispatchQueue` unless necessary
- Handle cancellation properly with `Task.isCancelled`

> **For advanced SwiftUI** (custom view modifiers, GeometryReader techniques, animations, PreferenceKey/EnvironmentKey, performance profiling with Instruments): use the **`swiftui-advanced`** skill
>
> *Example: "Help me optimize this view's performance using the swiftui-advanced skill"*

### HealthKit Integration

**Authorization & Privacy:**
- Request authorization before any queries—handle denial gracefully
- Request only the specific data types you need (principle of least privilege)
- Show clear explanations in authorization prompts (Info.plist descriptions)
- Test with authorization denied to ensure graceful fallbacks

**Query Patterns:**
- Use `HKStatisticsCollectionQuery` for time-series data (hourly, daily aggregates)
- Use `HKAnchoredObjectQuery` for real-time updates and incremental changes
- Use `HKObserverQuery` to detect when new data becomes available
- Cache results appropriately—don't re-query on every view update

**Data Accuracy:**
- Query with appropriate date intervals—respect day boundaries at midnight
- Use `Calendar.current` for date arithmetic—handle DST and timezone changes
- Filter out zero-value data points if they're artifacts (e.g., hours with no activity)
- Validate that predicates and date ranges match your mental model

**Performance:**
- Avoid excessive HealthKit queries—batch requests when possible
- Use background delivery for data that updates while app is backgrounded
- Debounce or throttle queries triggered by user interaction
- Test with large datasets (years of data) to catch O(n²) problems

> **For HealthKit implementation details** (query construction, authorization patterns, observer queries, date/time edge cases, widget timeline strategies, debugging techniques): use the **`healthkit-queries`** skill
>
> *Example: "Help me fix this midnight boundary issue in my widget timeline using the healthkit-queries skill"*

### Widget Development

**Widget Lifecycle:**
- Keep `getTimeline` fast—aim for <1 second execution time
- Return appropriate refresh policies (`atEnd`, `after`, `never`)
- Test timeline generation across day boundaries (midnight transitions)

> **For widget HealthKit patterns** (timeline strategies, midnight handling, fallback strategies, caching, stale data detection): use the **`healthkit-queries`** skill
>
> *Example: "Help me implement hybrid HealthKit queries for my widget using the healthkit-queries skill"*

### Swift Charts Integration

**Chart Construction:**
- Use `RuleMark` for reference lines (e.g., average/target values)
- Use `LineMark` for continuous data (cumulative calories over time)
- Use `BarMark` for discrete comparisons (daily totals, categories)
- Layer marks thoughtfully—order matters for visual hierarchy

**Styling & Accessibility:**
- Use semantic colors (`.primary`, `.secondary`) instead of hardcoded colors
- Provide `accessibilityLabel` and `accessibilityValue` for chart elements
- Test charts with Dynamic Type—ensure labels remain readable
- Use `chartYScale` and `chartXScale` to control axis ranges

**Performance:**
- Limit data points rendered—use aggregation for large datasets
- Use `animation()` judiciously—smooth transitions but don't overdo it
- Test charts with empty data—show meaningful empty states

### Architecture & Code Organization

**MVVM Pattern:**
- Use view models (`@Observable`) for complex views with business logic
- Keep SwiftUI views focused on presentation, not data transformation
- Extract data fetching logic to dedicated services (e.g., `HealthKitService`)
- Use dependency injection via `@Environment` or initializer injection

**Protocol-Oriented Design:**
- Define protocols for testability (e.g., `protocol HealthDataProvider`)
- Use protocols to abstract external dependencies (HealthKit, UserDefaults)
- Mock protocol implementations for previews and tests

**Modular Structure:**
- Group related files: Views/, Models/, Services/, Extensions/
- Keep view files focused—one primary view per file
- Extract reusable components to shared locations
- Use extensions to organize protocol conformances

**App/Widget Code Sharing:**
- **Shared Swift Package** (`HealthTrendsShared`): Models, query services, caching logic shared between app and widget
- **App-specific**: UI, navigation, state management (`HealthKitManager`)
- **Widget-specific**: Timeline providers, entry views, widget-specific caching strategies
- **Why this works**: Widget extensions can't access app code directly; Swift package compiles once and is used by both targets
- **Pattern**: Keep shared logic in the package, keep target-specific implementations separate

### Testing & Quality

**XCTest Patterns:**
- Write unit tests for business logic (data transformations, calculations)
- Write UI tests for critical user flows (widget display, chart rendering)
- Use `@testable import` to test internal implementation details
- Mock HealthKit queries for deterministic tests

**Preview-Driven Development:**
- Create rich preview providers with multiple states (loading, error, success)
- Use preview data fixtures for consistent test data
- Test edge cases in previews (empty data, extreme values)

### Performance & Optimization

**Common Pitfalls:**
- Avoid force-unwrapping optionals—use `guard` or `if let`
- Avoid expensive work in SwiftUI `body`—use `@State` or computed properties
- Be cautious with `.onAppear`—it fires more often than you think
- Watch for retain cycles with closures—use `[weak self]` when needed

**Instruments & Profiling:**
- Profile with Time Profiler for CPU bottlenecks
- Use Allocations instrument for memory leaks
- Monitor widget memory usage—they're memory-constrained
- Check for main thread blocking during HealthKit queries

> **For detailed performance optimization** (using SwiftUI instrument, reducing view update frequency, debugging hitches, GeometryReader performance patterns): use the **`swiftui-advanced`** skill
>
> *Example: "Help me profile this view's update frequency using the swiftui-advanced skill"*

### Accessibility

**Essential Practices:**
- Test with VoiceOver enabled regularly
- Provide meaningful accessibility labels for custom views
- Support Dynamic Type—use `.font(.body)` instead of fixed sizes
- Test with Reduce Motion—respect user preferences

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
**Definition:** The average cumulative calories burned BY each hour, calculated across the last ~10 occurrences of the current weekday (excluding today).

**Example:** At 1:00 PM on a Saturday:
- Saturday 1: burned 400 cal by 1 PM
- Saturday 2: burned 380 cal by 1 PM
- ...
- Saturday 10: burned 395 cal by 1 PM

Then "Average" at 1 PM = (400 + 380 + ... + 395) / 10 = 389 cal

**In Code:**
- `averageHourlyData: [HourlyEnergyData]` - Average cumulative values at each hour
  - For hour H: average of (saturday1_total_by_H + saturday2_total_by_H + ... + saturday10_total_by_H) / 10
  - Example: `[8, 12, ..., 350, 389]` (cumulative averages)

**Display:** Show the value at the current hour (e.g., 389 cal at 1 PM)

**Note:** Uses weekday filtering to account for weekday variability in activity patterns and schedules.

---

### "Total"
**Definition:** The average of complete daily totals from the last ~10 occurrences of the current weekday (excluding today).

**Example:** On a Saturday:
- Saturday 1: burned 1,050 cal (full day)
- Saturday 2: burned 1,020 cal (full day)
- ...
- Saturday 10: burned 1,032 cal (full day)

Then "Total" = (1,050 + 1,020 + ... + 1,032) / 10 = 1,034 cal

**In Code:**
- `projectedTotal: Double` - Average of complete daily totals for matching weekdays
  - This represents where you'd end up at midnight if you follow the average pattern

**Visual:** Shown as a horizontal green line on the chart and a green statistic

---

## Why This Matters

These three metrics answer different questions:

1. **"Today"**: How much have I burned so far?
2. **"Average"**: How much had I typically burned by this time of day?
3. **"Total"**: If I follow my average pattern, where will I end up?

The distinction between "Average" (cumulative by hour) and "Total" (daily average) is critical for accurate graphing and projections.
