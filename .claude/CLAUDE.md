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

## Project Structure

The project consists of three main targets with the following structure:

### 1. Main App Target (`HealthTrends/`)
```
HealthTrends/
├── HealthTrendsApp.swift              # App entry point (@main)
├── Managers/
│   └── HealthKitManager.swift         # App-level HealthKit state management (@Observable)
├── Models/
│   ├── HourlyEnergyData.swift         # App target's copy (for app-specific logic)
│   └── SharedEnergyData.swift         # Data model for app/widget communication
├── Views/
│   ├── App/
│   │   ├── ContentView.swift          # Main app view (NOT in root!)
│   │   └── DevelopmentToolsSheet.swift
│   └── Shared/
│       ├── EnergyChartView.swift      # Swift Charts visualization
│       ├── EnergyTrendView.swift      # Main trend display (chart + stats)
│       └── HeaderStatistic.swift      # Reusable statistic component
├── Utilities/
│   ├── ShakeGesture.swift             # Debug shake gesture
│   ├── TextMeasurement.swift          # Chart label collision detection
│   └── WidgetPreviewContainer.swift   # Widget preview in app
└── Assets.xcassets/                   # App-specific assets and colors
```

### 2. Widget Extension Target (`DailyActiveEnergyWidget/`)
```
DailyActiveEnergyWidget/
├── DailyActiveEnergyWidgetBundle.swift  # Widget bundle definition
├── DailyActiveEnergyWidget.swift        # Timeline provider & widget views
├── RefreshWidgetIntent.swift            # App Intent for manual refresh
├── WidgetConfigurationIntent.swift      # Widget configuration
└── Assets.xcassets/                     # Widget-specific assets
```

### 3. Shared Swift Package (`HealthTrendsShared/`)
**Purpose:** Code shared between app and widget (widget can't access app code directly)
```
HealthTrendsShared/
├── Package.swift                        # SPM manifest
└── Sources/HealthTrendsShared/
    ├── HealthKitQueryService.swift      # HealthKit query logic (shared!)
    ├── AverageDataCache.swift           # Caching for average calculations
    └── HourlyEnergyData.swift           # Core data model (shared!)
```

### Key File Locations (Most Frequently Modified)

**Widget timeline:** `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift`
**Main app view:** `HealthTrends/Views/App/ContentView.swift` (NOT in root!)
**Chart rendering:** `HealthTrends/Views/Shared/EnergyChartView.swift`
**App HealthKit manager:** `HealthTrends/Managers/HealthKitManager.swift`
**Development tools:** `HealthTrends/Views/App/DevelopmentToolsSheet.swift`
**Trend display:** `HealthTrends/Views/Shared/EnergyTrendView.swift`
**HealthKit queries (shared):** `HealthTrendsShared/Sources/HealthTrendsShared/HealthKitQueryService.swift`

### Important Notes
- **ContentView is NOT in `HealthTrends/ContentView.swift`** — it's nested in `Views/App/`
- **Two copies of `HourlyEnergyData.swift`** exist:
  - Shared version: `HealthTrendsShared/Sources/HealthTrendsShared/HourlyEnergyData.swift`
  - App version: `HealthTrends/Models/HourlyEnergyData.swift`
- **HealthKit queries** are centralized in the shared package, not scattered
- **Widget uses shared package** for all HealthKit logic—don't duplicate code

### Additional Resources
- **Documentation:** `documentation/` contains data flow and widget debugging guides
- **Design reference:** `design-reference/` has inspiration and mockups
- **Xcode project:** `HealthTrends.xcodeproj/`

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
- Eliminate excessive `DispatchQueue.main.async` calls in modern concurrency contexts
- Remove unnecessary `@MainActor` annotations in new app projects (views are implicitly `@MainActor`)

**Modern API Usage (iOS 17+):**
- Replace deprecated `foregroundColor()` with `foregroundStyle()`
- Switch `cornerRadius()` to `clipShape(.rect(cornerRadius:))` for advanced features
- Avoid single-parameter `onChange()` modifier—use two parameters or none instead
- Replace old `tabItem()` with the new `Tab` API for type-safe selection
- Use actual `Button` instead of `onTapGesture()` (except when location/tap count matters)
- Change `NavigationView` to `NavigationStack` (unless supporting iOS 15)
- Switch `Task.sleep(nanoseconds:)` to `Task.sleep(for:)` with duration values
- Replace `UIGraphicsImageRenderer` with `ImageRenderer` for SwiftUI rendering
- Use `URL.documentsDirectory` instead of manual documents directory code

**Navigation Patterns:**
- Update inline `NavigationLink` in lists to `navigationDestination(for:)` pattern
- Use `Button()` with inline syntax or `Label` instead of image-only buttons

**Data & Formatting:**
- Prefer type-safe number formatting over C-style `String(format:)` approaches
- Be cautious with `@Attribute(.unique)` in SwiftData—incompatible with CloudKit

**Code Simplification:**
- Remove unnecessary `Array()` wrapper: use `ForEach(x.enumerated()...` directly
- Reduce overuse of `fontWeight()` modifier—prefer semantic font styles

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
- Avoid consolidating multiple types into single files to reduce build times
- Split complex computed properties into separate SwiftUI views instead of inline definitions

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

## Product Requirements & Terminology

> **See [PRD.md](../documentation/PRD.md)** for complete product requirements, feature specifications, and detailed metric definitions.

### Quick Reference: Core Metrics

The app displays three key metrics (full definitions in PRD):

1. **"Today"** (`todayTotal: Double`) - Cumulative calories burned from midnight to now
2. **"Average"** (`averageHourlyData: [HourlyEnergyData]`) - Typical calories burned by this hour, calculated from last ~10 occurrences of current weekday
3. **"Total"** (`projectedTotal: Double`) - Average of complete daily totals from matching weekdays (where you'll likely end up)

**Why it matters:** These metrics answer "How much have I burned?", "Am I on pace?", and "Where will I end up?" The distinction between "Average" (cumulative by hour) and "Total" (daily average) is critical for accurate graphing and projections.
