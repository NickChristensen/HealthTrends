---
name: healthkit-queries
description: Deep expertise for HealthKit query construction, optimization, and debugging. Use when implementing new HealthKit features, debugging data accuracy issues, or optimizing query performance.
---

# HealthKit Queries - Deep Dive

Expert guidance for constructing HealthKit queries with focus on accuracy, performance, and edge case handling.

## When to Use This Skill

- Implementing new HealthKit data queries
- Debugging "why is my data off by X?" issues
- Optimizing query performance for large datasets
- Handling day/hour boundary edge cases
- Implementing background delivery and observer queries
- Dealing with timezone/DST issues in HealthKit data

## Core Query Types

### HKSampleQuery - Direct Sample Access

**When to use:** Simple queries, custom aggregation logic, widget contexts where you need full control

**Pattern:**
```swift
let predicate = HKQuery.predicateForSamples(
    withStart: startDate,
    end: endDate,
    options: .strictStartDate  // Samples that START in range (not overlap)
)

let samples = try await withCheckedThrowingContinuation { continuation in
    let query = HKSampleQuery(
        sampleType: quantityType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,  // Get all matching samples
        sortDescriptors: nil  // Sort in memory if needed
    ) { _, samples, error in
        if let error = error {
            continuation.resume(throwing: error)
            return
        }
        continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
    }
    healthStore.execute(query)
}

// Manual aggregation
var hourlyTotals: [Date: Double] = [:]
for sample in samples {
    let hourStart = calendar.dateInterval(of: .hour, for: sample.startDate)?.start
        ?? sample.startDate
    let calories = sample.quantity.doubleValue(for: .kilocalorie())
    hourlyTotals[hourStart, default: 0] += calories
}
```

**Pros:**
- Full control over aggregation logic
- Works in widget extensions (no long-running queries)
- Can implement custom grouping (by hour, by source, etc.)
- Straightforward error handling

**Cons:**
- Manual aggregation required
- More verbose than statistics queries
- Need to handle empty intervals yourself

**Real example from HealthTrends:**
```swift
// From HealthKitQueryService.swift:85-111
private func fetchHourlyData(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [HourlyEnergyData] {
    let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

    var hourlyTotals: [Date: Double] = [:]

    let samples = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
        }
        healthStore.execute(query)
    }

    // Group by hour
    for sample in samples {
        let hourStart = calendar.dateInterval(of: .hour, for: sample.startDate)?.start ?? sample.startDate
        let calories = sample.quantity.doubleValue(for: .kilocalorie())
        hourlyTotals[hourStart, default: 0] += calories
    }

    return hourlyTotals.map { HourlyEnergyData(hour: $0.key, calories: $0.value) }
        .sorted { $0.hour < $1.hour }
}
```

### HKStatisticsCollectionQuery - Built-in Time Series Aggregation

**When to use:** App context (not widgets), standard time intervals, built-in aggregation

**Pattern:**
```swift
// Define anchor and interval
let calendar = Calendar.current
let anchorDate = calendar.startOfDay(for: Date())  // Anchor at midnight
let interval = DateComponents(hour: 1)  // 1-hour intervals

let query = HKStatisticsCollectionQuery(
    quantityType: activeEnergyType,
    quantitySamplePredicate: nil,
    options: .cumulativeSum,  // For cumulative metrics like calories
    anchorDate: anchorDate,
    intervalComponents: interval
)

// Set initial results handler
query.initialResultsHandler = { query, results, error in
    guard let results = results else {
        if let error = error {
            print("Query failed: \(error)")
        }
        return
    }

    // Enumerate statistics
    results.enumerateStatistics(from: startDate, to: endDate) { statistics, stop in
        if let sum = statistics.sumQuantity() {
            let calories = sum.doubleValue(for: .kilocalorie())
            print("\(statistics.startDate): \(calories) cal")
        }
    }
}

healthStore.execute(query)
```

**Pros:**
- HealthKit handles aggregation (correct, efficient)
- Natural time interval alignment
- Handles empty intervals gracefully (returns nil quantity)
- Can act as long-running query with `statisticsUpdateHandler`

**Cons:**
- More complex setup (anchor dates, intervals)
- Less flexible for custom aggregation
- **Not suitable for widgets** (long-running queries)

**Choosing Statistics Options:**

```swift
// For CUMULATIVE metrics (calories burned, steps, distance)
options: .cumulativeSum

// For DISCRETE metrics (heart rate, blood pressure)
options: [.discreteAverage, .discreteMin, .discreteMax]

// To separate by data source (Apple Watch vs iPhone)
options: [.cumulativeSum, .separateBySource]

// CANNOT combine cumulative and discrete
// ❌ [.cumulativeSum, .discreteAverage]  // ERROR
```

**Understanding Anchor Dates:**

The anchor date defines when each interval starts. For 1-hour intervals:
- Anchor at 3:00 AM → intervals start at 3 AM, 4 AM, 5 AM...
- Anchor at midnight → intervals start at 12 AM, 1 AM, 2 AM...

**The exact date doesn't matter** - only the time component. These are equivalent:
- `2020-01-01 03:00`
- `2025-11-26 03:00`

Both produce intervals starting at 3 AM daily.

## Authorization & Privacy

### Requesting Authorization

```swift
func requestAuthorization() async throws {
    guard HKHealthStore.isHealthDataAvailable() else {
        throw HealthKitError.notAvailable
    }

    let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
    let activitySummaryType = HKObjectType.activitySummaryType()

    let typesToRead: Set<HKObjectType> = [activeEnergyType, activitySummaryType]
    let typesToWrite: Set<HKSampleType> = [activeEnergyType]

    try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

    // For read permissions, HealthKit NEVER reveals if user granted access (privacy)
    // Assume success if no error thrown
    isAuthorized = true
}
```

**Privacy Protection:**
- HealthKit **never** tells you if read permission was denied
- Apps only see data they wrote themselves (if denied)
- Check authorization status before writes:

```swift
let status = healthStore.authorizationStatus(for: activeEnergyType)

switch status {
case .notDetermined:
    // Haven't requested yet - call requestAuthorization()
    try await requestAuthorization()
case .sharingDenied:
    // User denied - show error, can't save
    throw HealthKitError.authorizationDenied
case .sharingAuthorized:
    // Can save samples
    try await healthStore.save(samples)
@unknown default:
    break
}
```

### Guest User Mode (Vision Pro)

```swift
// In Guest User sessions, writes fail with specific error
do {
    try await healthStore.save(sample)
} catch let error as HKError where error.code == .errorNotPermissibleForGuestUserMode {
    // Silently ignore for passive saves, or show alert for explicit actions
    print("Cannot save in Guest User mode")
}
```

## Date & Time Edge Cases

### Midnight Boundaries

**Critical insight:** HealthKit samples can span midnight. Always consider boundary conditions.

```swift
// ❌ WRONG: Might miss samples that start before midnight and end after
let today = calendar.startOfDay(for: Date())
let predicate = HKQuery.predicateForSamples(withStart: today, end: Date(), options: .strictStartDate)

// ✅ CORRECT: strictStartDate means "sample starts in range"
// This is usually what you want for daily queries
let predicate = HKQuery.predicateForSamples(
    withStart: startOfDay,
    end: Date(),
    options: .strictStartDate  // Sample.startDate >= startOfDay
)

// If you need samples that OVERLAP the interval (rare):
let predicate = HKQuery.predicateForSamples(
    withStart: startOfDay,
    end: Date(),
    options: []  // Sample overlaps [startOfDay, now]
)
```

**Handling midnight transitions in widgets:**

```swift
// From DailyActiveEnergyWidget.swift:138-162
// Problem: Widget needs to show zero-state at midnight without querying HealthKit
// Solution: Create deterministic midnight entry

let midnight = calendar.nextDate(after: currentDate, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)

if midnight < next15MinUpdate {
    // Create zero-state entry - we KNOW today resets to 0
    let midnightEntry = EnergyWidgetEntry(
        date: midnight,
        todayTotal: 0,  // Known state!
        averageAtCurrentHour: 0,
        projectedTotal: currentEntry.projectedTotal,  // Keep for reference
        moveGoal: currentEntry.moveGoal,
        todayHourlyData: [HourlyEnergyData(hour: midnight, calories: 0)],
        averageHourlyData: currentEntry.averageHourlyData
    )

    // Schedule reload 1 minute after midnight for fresh data
    let reloadTime = calendar.date(byAdding: .minute, value: 1, to: midnight)!
    return Timeline(entries: [currentEntry, midnightEntry], policy: .after(reloadTime))
}
```

### DST & Timezone Handling

**Always use `Calendar.current` for date arithmetic:**

```swift
// ✅ CORRECT: Respects DST and timezone
let hourStart = calendar.dateInterval(of: .hour, for: date)?.start

// ❌ WRONG: Breaks during DST transitions
let hourStart = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
```

**DST Edge Case - Hour 2 AM doesn't exist on spring forward:**

```swift
// Spring forward: 2 AM doesn't exist, jumps to 3 AM
let march12_2023 = Date(/* 2023-03-12 */)

// Query from midnight to 3 AM - will miss the "missing" hour
// HealthKit handles this correctly, but your aggregation might not!

// ✅ CORRECT: Let Calendar handle it
for hour in 0..<24 {
    if let hourDate = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
        // This will skip 2 AM on spring forward
    }
}
```

### Cumulative Data Across Days

**Pattern for averaging cumulative patterns across multiple days:**

```swift
// From HealthKitManager.swift:366-459
private func fetchCumulativeAverageHourlyPattern(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [HourlyEnergyData] {
    let samples = /* fetch all samples in range */

    // Step 1: Group by day and hour
    var dailyCumulativeData: [Date: [Int: Double]] = [:]  // [dayStart: [hour: calories]]

    for sample in samples {
        let dayStart = calendar.startOfDay(for: sample.startDate)
        let hour = calendar.component(.hour, from: sample.startDate)
        let calories = sample.quantity.doubleValue(for: .kilocalorie())

        if dailyCumulativeData[dayStart] == nil {
            dailyCumulativeData[dayStart] = [:]
        }
        dailyCumulativeData[dayStart]![hour, default: 0] += calories
    }

    // Step 2: Convert each day to cumulative
    var dailyCumulative: [Date: [Int: Double]] = [:]

    for (dayStart, hourlyData) in dailyCumulativeData {
        var runningTotal: Double = 0
        var cumulativeByHour: [Int: Double] = [:]

        for hour in 0..<24 {
            runningTotal += hourlyData[hour] ?? 0
            cumulativeByHour[hour] = runningTotal
        }

        dailyCumulative[dayStart] = cumulativeByHour
    }

    // Step 3: Average across days for each hour
    var averageCumulativeByHour: [Int: Double] = [:]

    for hour in 0..<24 {
        var totalForHour: Double = 0
        var count = 0

        for (_, cumulativeByHour) in dailyCumulative {
            if let cumulativeAtHour = cumulativeByHour[hour], cumulativeAtHour > 0 {
                totalForHour += cumulativeAtHour
                count += 1
            }
        }

        averageCumulativeByHour[hour] = count > 0 ? totalForHour / Double(count) : 0
    }

    // Step 4: Convert to timeline data with timestamps at END of each hour
    let startOfToday = calendar.startOfDay(for: Date())
    var hourlyData: [HourlyEnergyData] = []

    hourlyData.append(HourlyEnergyData(hour: startOfToday, calories: 0))  // Midnight = 0

    for hour in 0..<24 {
        let timestamp = calendar.date(byAdding: .hour, value: hour + 1, to: startOfToday)!
        let avgCumulative = averageCumulativeByHour[hour] ?? 0
        hourlyData.append(HourlyEnergyData(hour: timestamp, calories: avgCumulative))
    }

    return hourlyData
}
```

**Why this matters:**
- Averaging NON-cumulative hourly data gives you "average hourly burn"
- Averaging CUMULATIVE hourly data gives you "typical progress throughout day"
- HealthTrends needs the latter for "are you ahead or behind?" comparisons

## Observer Queries & Background Delivery

### Setting Up Observer Queries

```swift
// Register for background delivery (call once at app launch)
func enableBackgroundDelivery() async throws {
    try await healthStore.enableBackgroundDelivery(
        for: activeEnergyType,
        frequency: .hourly  // .immediate, .hourly, .daily, .weekly
    )
}

// Create observer query (call in application(_:didFinishLaunchingWithOptions:))
let observerQuery = HKObserverQuery(
    sampleType: activeEnergyType,
    predicate: nil
) { query, completionHandler, error in
    guard error == nil else {
        print("Observer query failed: \(error!)")
        completionHandler()  // MUST call even on error
        return
    }

    // Fetch new data
    Task {
        try? await fetchEnergyData()

        // Reload widget
        WidgetCenter.shared.reloadAllTimelines()

        // MUST call completion handler
        completionHandler()
    }
}

healthStore.execute(observerQuery)
```

**Critical:**
- Call `completionHandler()` even on errors
- Set up observer queries in `application(_:didFinishLaunchingWithOptions:)`
- Background delivery wakes your app, runs observer handler, then suspends

### Disabling Background Delivery

```swift
// Call when user disables feature or revokes permissions
func disableBackgroundDelivery() async throws {
    try await healthStore.disableBackgroundDelivery(for: activeEnergyType)
}
```

## Performance Optimization

### Caching Strategies

**Pattern from HealthTrends:** Cache slow queries (average data), refresh fast queries (today)

```swift
// Widget: Hybrid approach - query today, cache average
// From DailyActiveEnergyWidget.swift:192-293

// Today's data: Fast, changes frequently → always query
let todayData = try await healthKit.fetchTodayHourlyTotals()

// Average data: Slow, changes rarely → cache for 6 hours
if cacheManager.shouldRefresh() {
    let (total, hourlyData) = try await healthKit.fetchAverageData()
    let cache = AverageDataCache(
        averageHourlyPattern: hourlyData,
        projectedTotal: total,
        cachedAt: Date(),
        cacheVersion: 1
    )
    try? cacheManager.save(cache)
} else {
    // Use cached average data
    let cache = cacheManager.load()
}
```

**Why this works:**
- Today's total changes every few minutes → must be fresh
- 30-day average changes minimally → safe to cache
- Widgets have strict time limits (~30 seconds)

### Predicate Optimization

```swift
// ✅ EFFICIENT: Filter at query time
let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
    HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
    HKQuery.predicateForObjects(from: [HKSource.default()])  // Only our app's data
])

// ❌ INEFFICIENT: Filter after fetching
let samples = try await fetchAllSamples()
let filtered = samples.filter { $0.sourceRevision.source == HKSource.default() }
```

### Batch Queries for Multiple Metrics

```swift
// ✅ EFFICIENT: Parallel queries with async let
async let activeEnergy = fetchActiveEnergy()
async let heartRate = fetchHeartRate()
async let steps = fetchSteps()

let (energy, hr, stepCount) = try await (activeEnergy, heartRate, steps)

// ❌ INEFFICIENT: Sequential queries
let energy = try await fetchActiveEnergy()
let hr = try await fetchHeartRate()
let steps = try await fetchSteps()
```

## Debugging Common Issues

### "My data is off by one hour"

**Cause:** Confusing hour START vs hour END timestamps

```swift
// Problem: What timestamp represents "calories burned during hour 7-8 AM"?

// ❌ Hour START (7 AM): Ambiguous - is this cumulative up to 7 AM or during 7-8 AM?
HourlyEnergyData(hour: sevenAM, calories: 250)

// ✅ Hour END (8 AM): Clear - cumulative total AT 8 AM
HourlyEnergyData(hour: eightAM, calories: 250)

// From HealthKitManager.swift:268-269
let timestamp = calendar.date(byAdding: .hour, value: 1, to: data.hour)!
cumulativeData.append(HourlyEnergyData(hour: timestamp, calories: runningTotal))
```

### "Widget shows stale data after midnight"

**Cause:** Cached data from previous day

```swift
// ✅ Check if cached data is from different day
let calendar = Calendar.current
let cachedEntry = loadCachedEntry(forDate: date)

if let lastDataPoint = cachedEntry.todayHourlyData.last,
   !calendar.isDate(lastDataPoint.hour, inSameDayAs: date) {
    // Return zero-state for new day
    return EnergyWidgetEntry(
        date: date,
        todayTotal: 0,
        todayHourlyData: [HourlyEnergyData(hour: calendar.startOfDay(for: date), calories: 0)],
        // ... keep average data
    )
}
```

### "Query returns no data but I know there are samples"

**Debug steps:**

1. **Check authorization:**
```swift
let status = healthStore.authorizationStatus(for: quantityType)
print("Auth status: \(status)")  // Should be .sharingAuthorized for writes
```

2. **Verify date range:**
```swift
print("Query range: \(startDate) to \(endDate)")
print("Sample dates: \(samples.map { $0.startDate })")
```

3. **Check predicate options:**
```swift
// .strictStartDate: Sample starts in range
// []: Sample overlaps range (start OR end in range)
let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
```

4. **Inspect sample sources:**
```swift
for sample in samples {
    print("\(sample.startDate): \(sample.quantity) from \(sample.sourceRevision.source.name)")
}
```

### "Average calculation seems wrong at late hours (11 PM - midnight)"

**Cause:** Incomplete days, zero-value filtering

```swift
// Problem: At 11 PM on Nov 26, averaging "cumulative by 11 PM" across last 30 days
// But some days might not have data at 11 PM yet, or have zero

// ✅ Filter out zero values to avoid skewing average
for (_, cumulativeByHour) in dailyCumulative {
    if let cumulativeAtHour = cumulativeByHour[hour], cumulativeAtHour > 0 {
        totalForHour += cumulativeAtHour
        count += 1
    }
}
averageCumulativeByHour[hour] = count > 0 ? totalForHour / Double(count) : 0
```

See: HealthKitManager.swift:420-427

### "Widget fails to load with database inaccessible error"

**Cause:** Device locked, HealthKit protected

```swift
do {
    let samples = try await healthStore.execute(query)
} catch let error as HKError where error.code == .errorDatabaseInaccessible {
    // Device is locked - use cached data
    return loadCachedEntry()
}
```

## Activity Summary Queries

**For fetching Move goals:**

```swift
func fetchMoveGoal() async throws -> Double {
    let calendar = Calendar.current
    let now = Date()

    // Create predicate for today
    var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
    dateComponents.calendar = calendar
    let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

    let activitySummary = try await withCheckedThrowingContinuation { continuation in
        let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: summaries?.first)
        }
        healthStore.execute(query)
    }

    if let summary = activitySummary {
        let goal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
        // Only update if valid (goal might be 0 if Fitness app not set up)
        return goal > 0 ? goal : cachedGoal
    }

    return cachedGoal  // Fallback
}
```

## Widget-Specific Patterns

### Timeline Generation with Midnight Handling

```swift
func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    Task {
        let currentEntry = await loadFreshEntry()
        var entries = [currentEntry]

        let calendar = Calendar.current
        let next15Min = calendar.date(byAdding: .minute, value: 15, to: Date())!
        let midnight = calendar.nextDate(after: Date(), matching: DateComponents(hour: 0), matchingPolicy: .nextTime)!

        if midnight < next15Min {
            // Midnight coming soon - add zero-state entry
            let midnightEntry = createMidnightEntry(/* ... */)
            entries.append(midnightEntry)

            // Reload 1 minute after midnight
            let reloadTime = calendar.date(byAdding: .minute, value: 1, to: midnight)!
            completion(Timeline(entries: entries, policy: .after(reloadTime)))
        } else {
            // Normal 15-minute refresh
            completion(Timeline(entries: entries, policy: .after(next15Min)))
        }
    }
}
```

### Fallback Strategy for Failed Queries

```swift
// From DailyActiveEnergyWidget.swift:200-228
do {
    todayData = try await healthKit.fetchTodayHourlyTotals()
} catch {
    // Check if cached data is stale (from previous day)
    let cachedEntry = loadCachedEntry()

    if isFromPreviousDay(cachedEntry) {
        // Return zero-state instead of stale data
        return EnergyWidgetEntry(/* zero state */)
    }

    // Same day - safe to use cached data
    return cachedEntry
}
```

## Testing Strategies

### Preview Data Generation

```swift
// Generate realistic preview data
static func generateSampleTodayData() -> [HourlyEnergyData] {
    let calendar = Calendar.current
    let now = Date()
    let startOfDay = calendar.startOfDay(for: now)
    let currentHour = calendar.component(.hour, from: now)

    var data: [HourlyEnergyData] = []
    var cumulative: Double = 0

    // Midnight point
    data.append(HourlyEnergyData(hour: startOfDay, calories: 0))

    // Completed hours with realistic burn patterns
    for hour in 0..<currentHour {
        let calories = generateRealisticCalories(for: hour)
        cumulative += calories
        let timestamp = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!
        data.append(HourlyEnergyData(hour: timestamp, calories: cumulative))
    }

    return data
}

private static func generateRealisticCalories(for hour: Int) -> Double {
    switch hour {
    case 0..<6:   return Double.random(in: 5...15)     // Sleep
    case 7:       return Double.random(in: 150...250)  // Morning workout
    case 9..<12:  return Double.random(in: 25...50)    // Morning activity
    case 12..<14: return Double.random(in: 30...60)    // Lunch/midday
    default:      return Double.random(in: 20...40)
    }
}
```

### Testing with Sample Data

```swift
// Generate sample HealthKit data for development
func generateSampleData() async throws {
    let calendar = Calendar.current
    let now = Date()
    var samples: [HKQuantitySample] = []

    // Generate 60 days of data
    for dayOffset in 0..<60 {
        guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)) else {
            continue
        }

        // For today, only generate up to current hour
        let maxHour = dayOffset == 0 ? calendar.component(.hour, from: now) : 23

        for hour in 0...maxHour {
            guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart),
                  hourStart <= now else {
                continue
            }

            let calories = generateRealisticCalories(for: hour)
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            let sample = HKQuantitySample(
                type: activeEnergyType,
                quantity: quantity,
                start: hourStart,
                end: calendar.date(byAdding: .hour, value: 1, to: hourStart)!
            )
            samples.append(sample)
        }
    }

    try await healthStore.save(samples)
}
```

## Best Practices Summary

1. **Always use `Calendar.current`** for date arithmetic (handles DST/timezones)
2. **Use `.strictStartDate`** for daily queries (samples that START in range)
3. **Cache slow queries** (30-day averages), refresh fast queries (today)
4. **Handle midnight boundaries** explicitly in widgets (create zero-state entries)
5. **Filter zero values** when averaging to avoid skewing results
6. **Check cached data dates** before using (might be from previous day)
7. **Use `async let`** for parallel queries (activeEnergy, heartRate, steps)
8. **Call completion handlers** in observer queries, even on errors
9. **Validate date ranges** when debugging (print start/end, sample dates)
10. **Use HKSampleQuery in widgets** (not long-running statistics queries)

## References

- Apple Docs: [Executing Statistics Collection Queries](https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries/)
- Apple Docs: [Authorizing Access to Health Data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data/)
- Apple Docs: [Executing Observer Queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries/)
- HealthTrends: `HealthKitManager.swift`, `HealthKitQueryService.swift`, `DailyActiveEnergyWidget.swift`

## See Also

- **swiftui-advanced skill**: For SwiftUI performance optimization, state management patterns, scene phase handling
- **swift-charts-advanced skill**: For visualizing HealthKit data with Swift Charts, including data preparation and chart composition
