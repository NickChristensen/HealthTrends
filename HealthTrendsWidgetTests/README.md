# Widget Integration Tests

Integration test suite for the Daily Active Energy Widget, ensuring product requirements from `documentation/PRD.md` are fulfilled.

## Overview

This test suite validates the widget's behavior across all PRD scenarios using **deterministic fixtures** and **exact assertions**. Tests run from HealthKit data → widget entry properties, ensuring the full pipeline works correctly.

## Test Structure

```
HealthTrendsWidgetTests/
├── Fixtures/
│   ├── DateHelpers.swift          # Deterministic date creation
│   ├── SampleHelpers.swift        # HKQuantitySample factory methods
│   └── HealthKitFixtures.swift    # Complete scenario data (samples + goals + dates)
├── Mocks/
│   └── MockHealthKitQueryService.swift  # Testable HealthKit service
└── Scenarios/
    ├── Scenario1_NormalOperationTests.swift  # Fresh data (Saturday 3 PM)
    ├── Scenario2_DelayedSyncTests.swift      # Stale data (45 min delay)
    ├── Scenario3_StaleDataTests.swift        # Previous day data
    └── Scenario4_UnauthorizedTests.swift     # No HealthKit permission
```

## Running Tests

### Xcode (Recommended for Development)

1. Open `HealthTrends.xcodeproj`
2. Select the **HealthTrendsWidgetTests** scheme
3. Press `Cmd+U` to run all tests
4. Or click the diamond icon next to individual `@Test` functions

### Command Line (CI/Automation)

**Recommended approach:**

```bash
# Run widget integration tests (fast, clean output)
xcodebuild test -quiet \
  -scheme HealthTrendsWidgetTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -enableCodeCoverage YES
```

**Why `-quiet`?**
- Suppresses verbose build output
- Shows only test results (pass/fail per test)
- Fast feedback: ~48 seconds for full suite
- Clean, readable output perfect for CI/CD

**Note:** `swift test` doesn't work for iOS-only packages that require iOS frameworks (HealthKit, WidgetKit). Use `xcodebuild test` for all tests in this project.

## Test Scenarios

### Scenario 1: Normal Operation (Fresh Data)

**When:** Saturday, 3:00 PM with up-to-date HealthKit data
**Expected:**
- Today: 550 cal (exact)
- Average at 3 PM: 510 cal (exact)
- Projected Total: 1013 cal (exact)
- Move Goal: 900 cal

**Tests:**
- `testNormalOperation()` - Validates all metrics match PRD
- `testTodayDataStructure()` - Today line is cumulative and stops at 3 PM
- `testAverageProjection()` - Average line projects to midnight

### Scenario 2: Delayed Sync

**When:** Saturday, 3:00 PM but data only current to 2:15 PM (45 min stale)
**Expected:**
- Data Time: 2:15 PM (shows staleness)
- Today: < 550 cal (stops at 2:15 PM)
- Average: Still projects to midnight

**Tests:**
- `testDelayedSync()` - Data time reflects staleness
- `testTodayLineStopsAtDataTime()` - Today data ends at 2:15 PM
- `testAverageProjectsIndependently()` - Average continues projecting

### Scenario 3: Stale Data (Previous Day)

**When:** Saturday, 10:00 AM but last data is from Friday 11 PM
**Expected:**
- No "Today" line (data from wrong day)
- Average-only display for Saturday
- Projected Total: Saturday's average (1013 cal)

**Tests:**
- `testStaleDataFromPreviousDay()` - No today data shown
- `testDataTimeFromPreviousDay()` - Data time is from Friday
- `testAverageForCorrectWeekday()` - Shows Saturday average, not Friday

### Scenario 4: No Authorization

**When:** User hasn't granted HealthKit permission
**Expected:**
- All metrics: 0.0
- `isAuthorized`: false
- Empty data arrays

**Tests:**
- `testUnauthorizedState()` - All metrics zero when unauthorized
- `testAuthorizationGating()` - Early return on auth failure
- `testEntryDateWhenUnauthorized()` - Entry date still reflects current time

## Fixture Philosophy

### Deterministic, No Randomness

All fixtures use **exact, hardcoded values** with **zero variation**:

```swift
// ✅ CORRECT: Deterministic pattern
let basePattern: [Double] = [
    5, 5, 5, 5, 5, 5,      // Midnight-6 AM: 30 cal
    25, 30, 35, 40, 45, 50, // 6 AM-Noon: 225 cal
    75, 85, 95,             // Noon-3 PM: 255 cal (total: 510)
    88, 82, 78, ...         // Rest of day: 503 cal (total: 1013)
]

// ❌ WRONG: Randomness or variation
let variation = (seed + index) % 11 - 5  // Don't do this!
```

### Exact Assertions

Tests use **exact equality**, not ranges:

```swift
// ✅ CORRECT: Exact assertion
#expect(entry.todayTotal == 550.0)
#expect(entry.projectedTotal == 1013.0)

// ❌ WRONG: Ranges or tolerances
#expect(entry.todayTotal >= 540.0 && entry.todayTotal <= 560.0)
```

### No Assertion Messages

Swift Testing explains failures automatically:

```swift
// ✅ CORRECT: Clean assertion
#expect(entry.moveGoal == 900.0)

// ❌ WRONG: Redundant message
#expect(entry.moveGoal == 900.0, "Move goal should be 900 cal")
```

## Adding New Tests

### 1. Create Fixture Data

Add factory method to `HealthKitFixtures.swift`:

```swift
static func scenarioX_myNewScenario() -> (samples: [HKQuantitySample], goal: Double, currentTime: Date) {
    let currentTime = DateHelpers.createSaturday(hour: 15, minute: 0)

    let todayCalories: [Double] = [
        // Exact hourly values (no randomness!)
        5, 5, 5, 5, 5, 5,  // 0-6 AM
        // ... rest of day
    ]

    let todaySamples = SampleHelpers.createDailySamples(
        date: currentTime,
        caloriesPerHour: todayCalories
    )

    // Historical data if needed
    let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
        weekday: 7,
        occurrences: 10,
        endDate: currentTime
    )

    return (todaySamples + historicalSamples, 900.0, currentTime)
}
```

### 2. Create Test File

Create `ScenarioX_MyNewScenarioTests.swift`:

```swift
import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

@Suite("Scenario X: My New Scenario")
struct MyNewScenarioTests {

    @Test("Description of what this tests")
    @MainActor
    func testMyNewScenario() async throws {
        // Clear cache
        AverageDataCacheManager().clearCache()

        // GIVEN: Mock setup
        let mockQueryService = MockHealthKitQueryService()
        let (samples, moveGoal, currentTime) = HealthKitFixtures.scenarioX_myNewScenario()
        mockQueryService.configureSamples(samples)
        mockQueryService.configureMoveGoal(moveGoal)
        mockQueryService.configureAuthorization(true)
        mockQueryService.configureCurrentTime(currentTime)

        let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

        // WHEN: Generate entry
        let entry = await provider.loadFreshEntry(
            forDate: currentTime,
            configuration: EnergyWidgetConfigurationIntent()
        )

        // THEN: Exact assertions
        #expect(entry.todayTotal == 550.0)
        #expect(entry.projectedTotal == 1013.0)
    }
}
```

### 3. Add to Test Target

In Xcode:
1. Select the new test file
2. Open File Inspector (Cmd+Option+1)
3. Check **HealthTrendsWidgetTests** under Target Membership

## Shared Package Unit Tests

Location: `HealthTrendsShared/Tests/HealthTrendsSharedTests/`

### HourlyEnergyDataTests

Tests interpolation logic:
- Exact hour matches
- Midpoint interpolation
- Quarter-hour increments
- Before/after data edge cases
- Non-hour data point filtering

### AverageDataCacheTests

Tests cache structures:
- Weekday enum from dates
- Cache staleness detection
- Weekday-specific cache storage
- Serialization roundtrip
- Multi-weekday cache management

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run Widget Integration Tests
  run: |
    xcodebuild test \
      -scheme HealthTrendsWidgetTests \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults

- name: Run Shared Package Tests
  run: swift test --package-path HealthTrendsShared
```

## Troubleshooting

### Tests Fail with "Module not found"

**Solution:** Ensure all widget source files are added to test target's Compile Sources:
- DailyActiveEnergyWidget.swift
- EnergyTrendView.swift
- EnergyChartView.swift
- HeaderStatistic.swift
- TextMeasurement.swift
- WidgetConfigurationIntent.swift
- RefreshWidgetIntent.swift

### Tests Fail with "Undefined symbols"

**Solution:** Link HealthTrendsShared framework in test target:
1. Select HealthTrendsWidgetTests target
2. Build Phases → Link Binary With Libraries
3. Add HealthTrendsShared

### Values Don't Match Expected

**Check:**
1. Fixture pattern sums to exactly 510 by hour 15 and 1013 total
2. No randomness in historical data generation
3. Mock is configured with correct current time
4. Cache is cleared at test start

### Tests Pass Locally but Fail in CI

**Common causes:**
- Date/timezone differences (use deterministic dates, not `Date()`)
- Simulator version mismatch (pin simulator in CI config)
- Cache pollution between test runs (always clear cache in test setup)

## Performance

Target performance (on iPhone 17 Pro simulator):
- Single test: < 1 second
- Full scenario suite: < 5 seconds
- All tests (including shared): < 10 seconds

If tests run slower, check:
- Excessive HealthKit query simulation
- Large fixture datasets
- Missing parallelization

## Future Enhancements

Potential additions tracked in beads:
- Performance benchmarks (widget load time < 1s)
- Snapshot testing for chart rendering
- Accessibility testing (VoiceOver labels)
- Memory leak detection
- Additional edge case scenarios
