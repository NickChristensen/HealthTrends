# Widget Data Lifecycle Documentation

This document traces the complete path of data from HealthKit to the widget UI for the Daily Active Energy widget. Each section follows a single data point through all transformation steps.

---

## 1. "Today" Header Statistic

### Step 1: HealthKit Query
- **Data Point**: Raw active energy samples from midnight to current time
- **File/Method**: `HealthKitQueryService.swift` → `fetchTodayHourlyTotals()`
- **Input**: Date range (start of today → now)
  ```swift
  // Example: Query from 12:00 AM to 1:30 PM
  startOfDay = 2025-11-26 00:00:00
  now = 2025-11-26 13:30:00
  ```
- **Output**: Array of `HKQuantitySample` objects
  ```swift
  // Example samples:
  [
    HKQuantitySample(startDate: 2025-11-26 00:15:00, calories: 5.2),
    HKQuantitySample(startDate: 2025-11-26 00:47:00, calories: 8.1),
    HKQuantitySample(startDate: 2025-11-26 01:12:00, calories: 12.3),
    // ... hundreds more samples
  ]
  ```
- **Explanation**: HealthKit stores individual activity samples throughout the day. This query retrieves all active energy samples since midnight using `HKSampleQuery`.

### Step 2: Group by Hour
- **Data Point**: Non-cumulative hourly totals
- **File/Method**: `HealthKitQueryService.swift` → `fetchHourlyData()`
- **Input**: Array of `HKQuantitySample` from Step 1
- **Output**: Array of `HourlyEnergyData` (non-cumulative)
  ```swift
  // Example: Grouped by hour start
  [
    HourlyEnergyData(hour: 2025-11-26 00:00:00, calories: 45.2),  // All samples 0:00-0:59
    HourlyEnergyData(hour: 2025-11-26 01:00:00, calories: 38.7),  // All samples 1:00-1:59
    HourlyEnergyData(hour: 2025-11-26 02:00:00, calories: 52.1),  // All samples 2:00-2:59
    // ... up to current hour
    HourlyEnergyData(hour: 2025-11-26 13:00:00, calories: 23.4),  // Current incomplete hour
  ]
  ```
- **Explanation**: Samples are grouped by the hour they occurred in. Each hour's calories are summed. The hour timestamp represents the start of that hour period.

### Step 3: Convert to Cumulative
- **Data Point**: Cumulative calories at each hour boundary + current progress
- **File/Method**: `HealthKitQueryService.swift` → `fetchTodayHourlyTotals()` (lines 34-55)
- **Input**: Non-cumulative hourly data from Step 2
- **Output**: Array of `HourlyEnergyData` (cumulative)
  ```swift
  // Example: Running sum with timestamps at hour boundaries
  [
    HourlyEnergyData(hour: 2025-11-26 00:00:00, calories: 0),      // Midnight baseline
    HourlyEnergyData(hour: 2025-11-26 01:00:00, calories: 45.2),   // 0 + 45.2
    HourlyEnergyData(hour: 2025-11-26 02:00:00, calories: 83.9),   // 45.2 + 38.7
    HourlyEnergyData(hour: 2025-11-26 03:00:00, calories: 136.0),  // 83.9 + 52.1
    // ... completed hours
    HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 467.0),  // Current time with latest total
  ]
  ```
- **Explanation**: Converts hourly totals into a running sum. Completed hours use the hour boundary timestamp (e.g., 1:00:00 for hour 0), but the current incomplete hour uses the actual current time for real-time display.

### Step 4: Extract Today Total
- **Data Point**: Single number representing total calories burned today
- **File/Method**: `DailyActiveEnergyWidget.swift` → `loadFreshEntry()` (line 203)
- **Input**: Cumulative array from Step 3
  ```swift
  todayHourlyData = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    // ...
    HourlyEnergyData(hour: 13:30, calories: 467.0),
  ]
  ```
- **Output**: `Double` - last value from array
  ```swift
  todayTotal = 467.0
  ```
- **Explanation**: The last element in the cumulative array represents the most current total. Uses `todayHourlyData.last?.calories ?? 0`.

### Step 5: Store in Widget Entry
- **Data Point**: Today total ready for UI consumption
- **File/Method**: `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (lines 15-35)
- **Input**: `todayTotal: Double` from Step 4
  ```swift
  todayTotal = 467.0
  ```
- **Output**: `EnergyWidgetEntry` struct field
  ```swift
  EnergyWidgetEntry(
    date: 2025-11-26 13:30:00,
    todayTotal: 467.0,  // ← Stored here
    // ... other fields
  )
  ```
- **Explanation**: The widget timeline entry bundles all data needed for display. This entry is provided to the widget view during timeline updates.

### Step 6: Pass to View
- **Data Point**: Today total parameter for trend view
- **File/Method**: `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (lines 331-338)
- **Input**: `entry.todayTotal` from widget entry
  ```swift
  entry.todayTotal = 467.0
  ```
- **Output**: View parameter
  ```swift
  EnergyTrendView(
    todayTotal: 467.0,  // ← Passed here
    // ... other parameters
  )
  ```
- **Explanation**: The entry view extracts the `todayTotal` field and passes it to the main trend view component.

### Step 7: Render Header Statistic
- **Data Point**: Displayed "Today" value in widget header
- **File/Method**: `EnergyTrendView.swift` → `HeaderStatistic` (line 23)
- **Input**: `todayTotal: Double` parameter
  ```swift
  todayTotal = 467.0
  ```
- **Output**: UI display
  ```
  ⚫ Today
  467 cal
  ```
- **Explanation**: `HeaderStatistic` formats the double as an integer and displays it with the "Today" label and active energy color (pink).

---

## 2. "Average" Header Statistic

### Step 1: HealthKit Query (30-Day Range)
- **Data Point**: Raw active energy samples from past 30 days (excluding today)
- **File/Method**: `HealthKitQueryService.swift` → `fetchAverageData()` (lines 60-80)
- **Input**: Date range (30 days ago → yesterday midnight)
  ```swift
  // Example: Query historical data
  thirtyDaysAgo = 2025-10-27 00:00:00
  yesterday = 2025-11-25 23:59:59
  ```
- **Output**: Array of `HKQuantitySample` objects
  ```swift
  // Example: ~30 days worth of samples
  [
    HKQuantitySample(startDate: 2025-10-27 00:15:00, calories: 6.1),
    HKQuantitySample(startDate: 2025-10-27 01:22:00, calories: 9.2),
    // ... thousands of samples across 30 days
    HKQuantitySample(startDate: 2025-11-25 23:45:00, calories: 7.8),
  ]
  ```
- **Explanation**: Retrieves historical samples to calculate average patterns. Excludes today to avoid skewing the average with incomplete data.

### Step 2: Group by Day and Hour
- **Data Point**: Daily hourly breakdowns
- **File/Method**: `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 155-167)
- **Input**: Array of `HKQuantitySample` from Step 1
- **Output**: Dictionary mapping days to hourly data
  ```swift
  // Example: Each day's hourly breakdown
  dailyCumulativeData = [
    2025-10-27: [0: 42.1, 1: 35.2, 2: 48.9, ..., 23: 51.2],
    2025-10-28: [0: 38.7, 1: 41.3, 2: 52.1, ..., 23: 49.8],
    // ... 30 entries
    2025-11-25: [0: 45.3, 1: 39.1, 2: 50.2, ..., 23: 47.6],
  ]
  ```
- **Explanation**: Samples are grouped first by day, then by hour within each day. This creates a matrix of [day][hour] = calories for that specific hour.

### Step 3: Calculate Daily Cumulative Totals
- **Data Point**: Running sum by hour for each day
- **File/Method**: `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 169-183)
- **Input**: Daily hourly data from Step 2
- **Output**: Dictionary mapping days to cumulative hourly totals
  ```swift
  // Example: Each day's cumulative pattern
  dailyCumulative = [
    2025-10-27: [0: 42.1, 1: 77.3, 2: 126.2, ..., 23: 1050.0],
    2025-10-28: [0: 38.7, 1: 80.0, 2: 132.1, ..., 23: 1020.0],
    // ... 30 entries
    2025-11-25: [0: 45.3, 1: 84.4, 2: 134.6, ..., 23: 1032.0],
  ]
  ```
- **Explanation**: For each day, converts hourly totals into a running sum. Hour 0 = first hour total, Hour 1 = hour 0 + hour 1, etc. This represents "how much burned by each hour" pattern.

### Step 4: Average Across Days by Hour
- **Data Point**: Average cumulative total at each hour across 30 days
- **File/Method**: `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 185-200)
- **Input**: Daily cumulative data from Step 3
- **Output**: Dictionary of hour → average cumulative calories
  ```swift
  // Example: Average pattern across all 30 days
  averageCumulativeByHour = [
    0: 40.5,    // Average of all days' totals by hour 0
    1: 80.2,    // Average of all days' totals by hour 1
    2: 130.1,   // Average of all days' totals by hour 2
    // ...
    13: 389.0,  // Average of all days' totals by 1 PM
    // ...
    23: 1034.0, // Average of all days' total daily calories
  ]
  ```
- **Explanation**: For each hour (0-23), averages the cumulative totals from all 30 days. Filters out zero values to avoid skewing from incomplete data. This represents the typical cumulative burn pattern.

### Step 5: Convert to HourlyEnergyData Array
- **Data Point**: Formatted average hourly data with timestamps
- **File/Method**: `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 202-217)
- **Input**: Average cumulative by hour from Step 4
- **Output**: Array of `HourlyEnergyData`
  ```swift
  // Example: Timestamped average pattern for today
  [
    HourlyEnergyData(hour: 2025-11-26 00:00:00, calories: 0),      // Midnight baseline
    HourlyEnergyData(hour: 2025-11-26 01:00:00, calories: 40.5),   // End of hour 0
    HourlyEnergyData(hour: 2025-11-26 02:00:00, calories: 80.2),   // End of hour 1
    HourlyEnergyData(hour: 2025-11-26 03:00:00, calories: 130.1),  // End of hour 2
    // ... all 24 hours
    HourlyEnergyData(hour: 2025-11-27 00:00:00, calories: 1034.0), // Midnight (hour 24)
  ]
  ```
- **Explanation**: Converts the hour → value dictionary into an array of `HourlyEnergyData` objects with proper timestamps. Uses today's date for timestamps since this represents "typical pattern on any given day."

### Step 6: Interpolate Current Time
- **Data Point**: Average value precisely at current moment
- **File/Method**: `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 219-227)
- **Input**: Average hourly data from Step 5, current time
  ```swift
  now = 2025-11-26 13:30:00
  currentHour = 13
  currentMinute = 30
  avgAtCurrentHour = 389.0   // Average by end of hour 13
  avgAtNextHour = 425.0      // Average by end of hour 14
  ```
- **Output**: Interpolated `HourlyEnergyData` point
  ```swift
  // Example: Linear interpolation between hours 13 and 14
  interpolationFactor = 30 / 60 = 0.5
  avgAtNow = 389.0 + (425.0 - 389.0) * 0.5 = 407.0

  HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 407.0)
  ```
- **Explanation**: Uses linear interpolation to estimate the average value at the exact current minute. This provides smooth real-time updates rather than jumping every hour.

### Step 7: Cache Average Data
- **Data Point**: Cached average pattern for fast widget loading
- **File/Method**: `AverageDataCache.swift` → `AverageDataCacheManager.save()` (lines 92-103)
- **Input**: Average hourly data array with interpolated NOW point
  ```swift
  averageHourlyPattern = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    // ... 24 hourly points
    HourlyEnergyData(hour: 13:30, calories: 407.0),  // Interpolated NOW
  ]
  projectedTotal = 1034.0
  ```
- **Output**: JSON file in App Group container
  ```json
  {
    "averageHourlyPattern": [
      {"hour": "2025-11-26T00:00:00Z", "calories": 0},
      {"hour": "2025-11-26T01:00:00Z", "calories": 40.5},
      ...
      {"hour": "2025-11-26T13:30:00Z", "calories": 407.0}
    ],
    "projectedTotal": 1034.0,
    "cachedAt": "2025-11-26T13:30:00Z",
    "cacheVersion": 1
  }
  ```
- **Explanation**: Saves the average pattern to disk so widgets can load it quickly without re-querying HealthKit (expensive). Cached once per day, refreshed in the morning.

### Step 8: Extract Interpolated Value
- **Data Point**: Average value at current hour for header display
- **File/Method**: `DailyActiveEnergyWidget.swift` → `loadFreshEntry()` (line 282)
- **Input**: Average hourly data array (may come from cache or fresh query)
  ```swift
  averageData = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    // ...
    HourlyEnergyData(hour: 13:30, calories: 407.0),  // Interpolated NOW point
  ]
  now = 2025-11-26 13:30:00
  ```
- **Output**: `Double` - interpolated value at current time
  ```swift
  averageAtCurrentHour = 407.0
  ```
- **Explanation**: Uses the `interpolatedValue(at:)` helper to find or calculate the average value at the current time. If cached data includes the NOW point, returns it; otherwise interpolates between hourly boundaries.

### Step 9: Store in Widget Entry
- **Data Point**: Average at current hour ready for UI consumption
- **File/Method**: `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (lines 15-35)
- **Input**: `averageAtCurrentHour: Double` from Step 8
  ```swift
  averageAtCurrentHour = 407.0
  ```
- **Output**: `EnergyWidgetEntry` struct field
  ```swift
  EnergyWidgetEntry(
    date: 2025-11-26 13:30:00,
    todayTotal: 467.0,
    averageAtCurrentHour: 407.0,  // ← Stored here
    // ... other fields
  )
  ```
- **Explanation**: The average value is bundled into the widget entry alongside other metrics.

### Step 10: Pass to View
- **Data Point**: Average at current hour parameter for trend view
- **File/Method**: `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (lines 331-338)
- **Input**: `entry.averageAtCurrentHour` from widget entry
  ```swift
  entry.averageAtCurrentHour = 407.0
  ```
- **Output**: View parameter
  ```swift
  EnergyTrendView(
    todayTotal: 467.0,
    averageAtCurrentHour: 407.0,  // ← Passed here
    // ... other parameters
  )
  ```
- **Explanation**: Extracts the field from the entry and passes to the view.

### Step 11: Render Header Statistic
- **Data Point**: Displayed "Average" value in widget header
- **File/Method**: `EnergyTrendView.swift` → `HeaderStatistic` (line 26)
- **Input**: `averageAtCurrentHour: Double` parameter
  ```swift
  averageAtCurrentHour = 407.0
  ```
- **Output**: UI display
  ```
  ⚫ Average
  407 cal
  ```
- **Explanation**: `HeaderStatistic` formats the interpolated average as an integer and displays with "Average" label in system gray color.

---

## 3. "Total" Header Statistic

### Step 1: HealthKit Query (Same as Average Step 1)
- **Data Point**: Raw active energy samples from past 30 days
- **File/Method**: `HealthKitQueryService.swift` → `fetchAverageData()` (lines 60-68)
- **Input**: Date range (30 days ago → yesterday)
- **Output**: Array of `HKQuantitySample` objects (same query as Average data)
- **Explanation**: Uses the same historical samples to calculate both hourly pattern (for Average) and daily totals (for Total).

### Step 2: Group by Day
- **Data Point**: Complete daily totals
- **File/Method**: `HealthKitQueryService.swift` → `fetchDailyTotals()` (lines 114-138)
- **Input**: Array of `HKQuantitySample` from Step 1
- **Output**: Array of daily total calories
  ```swift
  // Example: Total calories for each of 30 days
  [
    1050.0,  // 2025-10-27 total
    1020.0,  // 2025-10-28 total
    998.0,   // 2025-10-29 total
    // ... 27 more days
    1032.0,  // 2025-11-25 total
  ]
  ```
- **Explanation**: Samples are grouped by day and summed to get each day's complete total. Represents "how much was burned in a full day" for each of the 30 days.

### Step 3: Calculate Average Daily Total
- **Data Point**: Mean of all daily totals
- **File/Method**: `HealthKitQueryService.swift` → `fetchAverageData()` (line 74)
- **Input**: Daily totals array from Step 2
  ```swift
  dailyTotals = [1050.0, 1020.0, 998.0, ..., 1032.0]
  ```
- **Output**: `Double` - average total
  ```swift
  // Example: Average of 30 daily totals
  sum = 31020.0
  count = 30
  projectedTotal = 31020.0 / 30 = 1034.0
  ```
- **Explanation**: Sums all daily totals and divides by the count to get the average complete daily total. This represents "typical full-day burn" and is saved as `projectedTotal`.

### Step 4: Cache (Same as Average Step 7)
- **Data Point**: Projected total cached alongside hourly pattern
- **File/Method**: `AverageDataCache.swift` → `AverageDataCacheManager.save()`
- **Input**: `projectedTotal: Double` from Step 3
  ```swift
  projectedTotal = 1034.0
  ```
- **Output**: JSON field in cached file
  ```json
  {
    "averageHourlyPattern": [...],
    "projectedTotal": 1034.0,  // ← Cached here
    "cachedAt": "2025-11-26T13:30:00Z"
  }
  ```
- **Explanation**: The projected total is cached along with the hourly pattern since both are calculated from the same 30-day query.

### Step 5: Store in Widget Entry
- **Data Point**: Projected total ready for UI consumption
- **File/Method**: `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (lines 15-35)
- **Input**: `projectedTotal: Double` from cache or fresh query
  ```swift
  projectedTotal = 1034.0
  ```
- **Output**: `EnergyWidgetEntry` struct field
  ```swift
  EnergyWidgetEntry(
    date: 2025-11-26 13:30:00,
    todayTotal: 467.0,
    averageAtCurrentHour: 407.0,
    projectedTotal: 1034.0,  // ← Stored here
    // ... other fields
  )
  ```
- **Explanation**: Bundled into the widget entry for display.

### Step 6: Pass to View
- **Data Point**: Projected total parameter for trend view
- **File/Method**: `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (lines 331-338)
- **Input**: `entry.projectedTotal` from widget entry
  ```swift
  entry.projectedTotal = 1034.0
  ```
- **Output**: View parameter
  ```swift
  EnergyTrendView(
    todayTotal: 467.0,
    averageAtCurrentHour: 407.0,
    todayHourlyData: [...],
    averageHourlyData: [...],
    moveGoal: 800.0,
    projectedTotal: 1034.0  // ← Passed here
  )
  ```
- **Explanation**: Passed to the trend view for both header display and chart reference line.

### Step 7: Render Header Statistic
- **Data Point**: Displayed "Total" value in widget header
- **File/Method**: `EnergyTrendView.swift` → `HeaderStatistic` (line 29)
- **Input**: `projectedTotal: Double` parameter
  ```swift
  projectedTotal = 1034.0
  ```
- **Output**: UI display
  ```
  ⚫ Total
  1034 cal
  ```
- **Explanation**: `HeaderStatistic` formats the projected total with "Total" label in light gray color to differentiate from active metrics.

---

## 4. Today Line (Chart)

### Steps 1-3: Same as "Today" Header Steps 1-3
- **Data Point**: Cumulative hourly data for today
- **Result**: Array of `HourlyEnergyData` with running sum
  ```swift
  todayHourlyData = [
    HourlyEnergyData(hour: 2025-11-26 00:00:00, calories: 0),
    HourlyEnergyData(hour: 2025-11-26 01:00:00, calories: 45.2),
    // ...
    HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 467.0),
  ]
  ```
- **Explanation**: Same data source as the "Today" header statistic.

### Step 4: Store Array in Widget Entry
- **Data Point**: Complete today hourly array
- **File/Method**: `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (line 21)
- **Input**: `todayHourlyData: [HourlyEnergyData]` from query
- **Output**: `EnergyWidgetEntry` field
  ```swift
  EnergyWidgetEntry(
    // ...
    todayHourlyData: [
      HourlyEnergyData(hour: 00:00, calories: 0),
      HourlyEnergyData(hour: 01:00, calories: 45.2),
      // ...
      HourlyEnergyData(hour: 13:30, calories: 467.0),
    ],  // ← Full array stored
    // ...
  )
  ```
- **Explanation**: The entire array is stored in the entry, not just the total, because the chart needs all data points to render the line.

### Step 5: Pass Array to View
- **Data Point**: Today hourly data for chart rendering
- **File/Method**: `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 334)
- **Input**: `entry.todayHourlyData`
- **Output**: View parameter
  ```swift
  EnergyTrendView(
    todayTotal: 467.0,
    averageAtCurrentHour: 407.0,
    todayHourlyData: [...],  // ← Full array passed
    // ...
  )
  ```
- **Explanation**: The array is passed to the view component for chart construction.

### Step 6: Extract to Chart Component
- **Data Point**: Today data for chart marks
- **File/Method**: `EnergyTrendView.swift` → `EnergyChartView` (line 36)
- **Input**: `todayHourlyData` parameter
- **Output**: Chart component parameter
  ```swift
  EnergyChartView(
    todayHourlyData: [...],  // ← Passed to chart
    // ...
  )
  ```
- **Explanation**: The chart view receives the data for rendering.

### Step 7: Render Line Marks
- **Data Point**: Visual line on chart representing today's progress
- **File/Method**: `EnergyChartView.swift` → `todayLine` computed property (lines 267-275)
- **Input**: `todayHourlyData` array from component
  ```swift
  todayHourlyData = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    HourlyEnergyData(hour: 01:00, calories: 45.2),
    HourlyEnergyData(hour: 02:00, calories: 83.9),
    // ...
    HourlyEnergyData(hour: 13:30, calories: 467.0),
  ]
  ```
- **Output**: SwiftUI Chart `LineMark` views
  ```swift
  Chart {
    // Creates connected line segments:
    LineMark(x: 00:00, y: 0) → LineMark(x: 01:00, y: 45.2)
    LineMark(x: 01:00, y: 45.2) → LineMark(x: 02:00, y: 83.9)
    // ... continues to current time
    LineMark(x: 13:00, y: 443.6) → LineMark(x: 13:30, y: 467.0)
  }
  // Styled: pink color (#FE4901), 4pt width, round caps
  ```
- **Explanation**: `ForEach` over the data array creates a `LineMark` for each point. SwiftUI Charts automatically connects them into a continuous line. The line is styled with the active energy color (pink) and 4pt width.

---

## 5. Today Marker (Chart)

### Steps 1-3: Same as Today Line Steps 1-3
- **Data Point**: Same cumulative hourly array
- **Result**: Array ending with current total at current time

### Step 4: Extract Last Data Point
- **Data Point**: Most recent data point (current total)
- **File/Method**: `EnergyChartView.swift` → `todayPoint` computed property (line 288)
- **Input**: `todayHourlyData` array
  ```swift
  todayHourlyData = [
    // ...
    HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 467.0),  // Last element
  ]
  ```
- **Output**: Optional `HourlyEnergyData`
  ```swift
  last = HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 467.0)
  ```
- **Explanation**: Uses `.last` to get the final data point, which represents the current cumulative total at the current time.

### Step 5: Render Point Marks
- **Data Point**: Visual marker on chart at current position
- **File/Method**: `EnergyChartView.swift` → `todayPoint` computed property (lines 287-293)
- **Input**: Last data point from Step 4, current time
  ```swift
  last.calories = 467.0
  now = 2025-11-26 13:30:00
  ```
- **Output**: SwiftUI Chart `PointMark` views
  ```swift
  // Two layered circles for depth effect:
  PointMark(x: 13:30, y: 467.0)
    .foregroundStyle(.background)  // White/system background
    .symbolSize(256)               // Outer circle (halo)

  PointMark(x: 13:30, y: 467.0)
    .foregroundStyle(activeEnergyColor)  // Pink #FE4901
    .symbolSize(100)                     // Inner circle (dot)
  ```
- **Explanation**: Creates two overlapping circles: a larger background-colored circle for contrast/halo effect, and a smaller pink circle for the actual marker. X-position uses current time (`now`) rather than the data's timestamp to align precisely with the NOW vertical line.

---

## 6. Average Line (Chart)

### Steps 1-6: Same as "Average" Header Steps 1-6
- **Data Point**: Array of average cumulative pattern with interpolated NOW point
- **Result**: Array of `HourlyEnergyData` covering full 24-hour pattern
  ```swift
  averageHourlyData = [
    HourlyEnergyData(hour: 2025-11-26 00:00:00, calories: 0),
    HourlyEnergyData(hour: 2025-11-26 01:00:00, calories: 40.5),
    // ... 24 hourly points
    HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 407.0),  // Interpolated NOW
    // ... rest of day
    HourlyEnergyData(hour: 2025-11-27 00:00:00, calories: 1034.0),
  ]
  ```

### Step 7: Store Array in Widget Entry
- **Data Point**: Complete average hourly array
- **File/Method**: `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (line 22)
- **Input**: `averageHourlyData: [HourlyEnergyData]` from query/cache
- **Output**: `EnergyWidgetEntry` field
  ```swift
  EnergyWidgetEntry(
    // ...
    averageHourlyData: [...],  // ← Full array stored
    // ...
  )
  ```
- **Explanation**: The complete 24-hour average pattern is stored for chart rendering.

### Step 8: Pass Array to View
- **Data Point**: Average hourly data for chart rendering
- **File/Method**: `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 335)
- **Input**: `entry.averageHourlyData`
- **Output**: View parameter
  ```swift
  EnergyTrendView(
    // ...
    averageHourlyData: [...],  // ← Full array passed
    // ...
  )
  ```
- **Explanation**: Passed to the trend view for chart display.

### Step 9: Extract to Chart Component
- **Data Point**: Average data for chart marks
- **File/Method**: `EnergyTrendView.swift` → `EnergyChartView` (line 37)
- **Input**: `averageHourlyData` parameter
- **Output**: Chart component parameter
  ```swift
  EnergyChartView(
    todayHourlyData: [...],
    averageHourlyData: [...],  // ← Passed to chart
    // ...
  )
  ```
- **Explanation**: The chart view receives the average pattern.

### Step 10: Clean Cached NOW Points
- **Data Point**: On-the-hour data only (removes stale interpolated points)
- **File/Method**: `EnergyChartView.swift` → `cleanedAverageData` computed property (lines 197-202)
- **Input**: `averageHourlyData` array (may contain old interpolated NOW point)
  ```swift
  averageHourlyData = [
    HourlyEnergyData(hour: 00:00, calories: 0),      // minute = 0 ✓
    HourlyEnergyData(hour: 01:00, calories: 40.5),   // minute = 0 ✓
    // ...
    HourlyEnergyData(hour: 13:15, calories: 395.0),  // minute = 15 ✗ (stale cache)
    HourlyEnergyData(hour: 14:00, calories: 425.0),  // minute = 0 ✓
  ]
  ```
- **Output**: Filtered array
  ```swift
  cleanedAverageData = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    HourlyEnergyData(hour: 01:00, calories: 40.5),
    // ... only on-the-hour points
    HourlyEnergyData(hour: 14:00, calories: 425.0),
  ]
  ```
- **Explanation**: Filters out any points where `minute != 0`. This removes stale interpolated NOW points from cached data that may be from earlier in the day.

### Step 11: Recalculate Interpolated NOW
- **Data Point**: Fresh average value at current moment
- **File/Method**: `EnergyChartView.swift` → `interpolatedAverageAtNow` computed property (lines 205-210)
- **Input**: Cleaned average data from Step 10, current time
  ```swift
  cleanedAverageData = [hour 0, hour 1, ..., hour 13, hour 14, ...]
  now = 2025-11-26 13:30:00
  ```
- **Output**: Interpolated point
  ```swift
  // Uses interpolatedValue(at:) helper
  HourlyEnergyData(hour: 2025-11-26 13:30:00, calories: 407.0)
  ```
- **Explanation**: Uses the `interpolatedValue(at:)` extension method to calculate the average value at the exact current time using linear interpolation between the surrounding hourly points.

### Step 12: Split at NOW (Before)
- **Data Point**: Average data from midnight to NOW
- **File/Method**: `EnergyChartView.swift` → `averageDataBeforeNow` computed property (lines 213-219)
- **Input**: Cleaned data and interpolated NOW from Steps 10-11
  ```swift
  cleanedAverageData = [00:00, 01:00, ..., 13:00, 14:00, ...]
  startOfCurrentHour = 2025-11-26 13:00:00
  interpolatedAverageAtNow = HourlyEnergyData(hour: 13:30, calories: 407.0)
  ```
- **Output**: Array of past + NOW point
  ```swift
  averageDataBeforeNow = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    HourlyEnergyData(hour: 01:00, calories: 40.5),
    // ...
    HourlyEnergyData(hour: 13:00, calories: 389.0),
    HourlyEnergyData(hour: 13:30, calories: 407.0),  // Interpolated NOW
  ]
  ```
- **Explanation**: Filters cleaned data to include only points up to and including the current hour start, then appends the interpolated NOW point. This represents "past pattern up to now."

### Step 13: Split at NOW (After)
- **Data Point**: Average data from NOW to midnight
- **File/Method**: `EnergyChartView.swift` → `averageDataAfterNow` computed property (lines 221-237)
- **Input**: Cleaned data and interpolated NOW from Steps 10-11
  ```swift
  cleanedAverageData = [00:00, 01:00, ..., 13:00, 14:00, ..., 24:00]
  startOfCurrentHour = 2025-11-26 13:00:00
  interpolatedAverageAtNow = HourlyEnergyData(hour: 13:30, calories: 407.0)
  ```
- **Output**: Array of NOW + future points
  ```swift
  averageDataAfterNow = [
    HourlyEnergyData(hour: 13:30, calories: 407.0),  // Interpolated NOW
    HourlyEnergyData(hour: 14:00, calories: 425.0),
    HourlyEnergyData(hour: 15:00, calories: 458.0),
    // ...
    HourlyEnergyData(hour: 00:00, calories: 1034.0),  // Next midnight
  ]
  ```
- **Explanation**: Starts with the interpolated NOW point, then includes all hourly points from the next hour onward. This represents "projected pattern for rest of day."

### Step 14: Render Line Marks (Before NOW)
- **Data Point**: Darker gray line from midnight to NOW
- **File/Method**: `EnergyChartView.swift` → `averageLines` computed property (lines 240-253)
- **Input**: `averageDataBeforeNow` from Step 12
  ```swift
  averageDataBeforeNow = [
    HourlyEnergyData(hour: 00:00, calories: 0),
    // ...
    HourlyEnergyData(hour: 13:30, calories: 407.0),
  ]
  ```
- **Output**: SwiftUI Chart `LineMark` views
  ```swift
  Chart {
    // Creates connected segments with darker gray:
    LineMark(x: 00:00, y: 0) → LineMark(x: 01:00, y: 40.5)
    LineMark(x: 01:00, y: 40.5) → LineMark(x: 02:00, y: 80.2)
    // ... continues to NOW
    LineMark(x: 13:00, y: 389.0) → LineMark(x: 13:30, y: 407.0)
  }
  // Styled: dark gray (.systemGray4), 4pt width, series: "AverageUpToNow"
  ```
- **Explanation**: Creates line marks for the "past" portion of the average line, styled in darker gray to indicate actual historical average up to the current moment.

### Step 15: Render Line Marks (After NOW)
- **Data Point**: Lighter gray line from NOW to midnight
- **File/Method**: `EnergyChartView.swift` → `averageLines` computed property (lines 255-265)
- **Input**: `averageDataAfterNow` from Step 13
  ```swift
  averageDataAfterNow = [
    HourlyEnergyData(hour: 13:30, calories: 407.0),
    HourlyEnergyData(hour: 14:00, calories: 425.0),
    // ...
    HourlyEnergyData(hour: 00:00, calories: 1034.0),
  ]
  ```
- **Output**: SwiftUI Chart `LineMark` views
  ```swift
  Chart {
    // Creates connected segments with lighter gray:
    LineMark(x: 13:30, y: 407.0) → LineMark(x: 14:00, y: 425.0)
    LineMark(x: 14:00, y: 425.0) → LineMark(x: 15:00, y: 458.0)
    // ... continues to midnight
    LineMark(x: 23:00, y: 989.0) → LineMark(x: 00:00, y: 1034.0)
  }
  // Styled: light gray (.systemGray6), 4pt width, series: "AverageRestOfDay"
  ```
- **Explanation**: Creates line marks for the "future" portion, styled in lighter gray to indicate projected pattern for the rest of the day. The two series create a visual distinction between "what has typically happened by now" vs "what typically happens next."

---

## 7. Average Marker (Chart)

### Steps 1-11: Same as Average Line Steps 1-11
- **Data Point**: Interpolated average at current moment
- **Result**: `HourlyEnergyData(hour: 13:30, calories: 407.0)`

### Step 12: Render Point Marks
- **Data Point**: Visual marker on chart at average line's current position
- **File/Method**: `EnergyChartView.swift` → `averagePoint` computed property (lines 278-284)
- **Input**: Interpolated average from previous steps
  ```swift
  interpolatedAverageAtNow = HourlyEnergyData(
    hour: 2025-11-26 13:30:00,
    calories: 407.0
  )
  ```
- **Output**: SwiftUI Chart `PointMark` views
  ```swift
  // Two layered circles for depth effect:
  PointMark(x: 13:30, y: 407.0)
    .foregroundStyle(.background)       // White/system background
    .symbolSize(256)                    // Outer circle (halo)

  PointMark(x: 13:30, y: 407.0)
    .foregroundStyle(.systemGray4)      // Dark gray (matches "before NOW" line)
    .symbolSize(100)                    // Inner circle (dot)
  ```
- **Explanation**: Creates two overlapping circles similar to the Today marker, but using dark gray color to match the "past" portion of the average line. Positioned at the interpolated NOW point where the line color changes.

---

## Appendix: Data Flow Table

| Data Point | File + Method | Input (Example) | Output (Example) | Explanation |
|------------|---------------|-----------------|------------------|-------------|
| **TODAY HEADER** |
| Raw HealthKit samples (today) | `HealthKitQueryService.swift` → `fetchTodayHourlyTotals()` | Date range: `2025-11-26 00:00` to `13:30` | `[HKQuantitySample(00:15, 5.2 cal), HKQuantitySample(00:47, 8.1 cal), ...]` | Queries all active energy samples since midnight |
| Hourly totals (non-cumulative) | `HealthKitQueryService.swift` → `fetchHourlyData()` | Array of HKQuantitySample | `[HourlyEnergyData(hour: 00:00, calories: 45.2), HourlyEnergyData(hour: 01:00, calories: 38.7), ...]` | Groups samples by hour and sums |
| Cumulative hourly data | `HealthKitQueryService.swift` → `fetchTodayHourlyTotals()` (lines 34-55) | Non-cumulative hourly data | `[HourlyEnergyData(00:00, 0), HourlyEnergyData(01:00, 45.2), HourlyEnergyData(02:00, 83.9), ..., HourlyEnergyData(13:30, 467.0)]` | Converts to running sum with proper timestamps |
| Today total value | `DailyActiveEnergyWidget.swift` → `loadFreshEntry()` (line 203) | Cumulative array | `todayTotal = 467.0` | Extracts last element's calories value |
| Widget entry field | `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` | `todayTotal = 467.0` | `EnergyWidgetEntry(todayTotal: 467.0, ...)` | Bundles into timeline entry |
| View parameter | `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 332) | `entry.todayTotal` | `EnergyTrendView(todayTotal: 467.0, ...)` | Passes to view |
| UI display | `EnergyTrendView.swift` → `HeaderStatistic` (line 23) | `todayTotal = 467.0` | `⚫ Today\n467 cal` | Renders in pink with "Today" label |
| **AVERAGE HEADER** |
| Raw HealthKit samples (30 days) | `HealthKitQueryService.swift` → `fetchAverageData()` (lines 60-68) | Date range: `2025-10-27 00:00` to `2025-11-25 23:59` | `[HKQuantitySample(2025-10-27 00:15, 6.1), ..., thousands more]` | Queries historical data for pattern |
| Daily hourly breakdown | `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 155-167) | Array of HKQuantitySample | `{2025-10-27: [0: 42.1, 1: 35.2, ...], 2025-10-28: [0: 38.7, ...], ...}` | Groups by day, then hour within day |
| Daily cumulative patterns | `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 169-183) | Daily hourly breakdown | `{2025-10-27: [0: 42.1, 1: 77.3, 2: 126.2, ...], ...}` | Converts each day to running sum |
| Average cumulative by hour | `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 185-200) | Daily cumulative patterns | `{0: 40.5, 1: 80.2, 2: 130.1, ..., 13: 389.0, ...}` | Averages each hour across all 30 days |
| Hourly data array | `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 202-217) | Average by hour dict | `[HourlyEnergyData(00:00, 0), HourlyEnergyData(01:00, 40.5), ...]` | Converts to timestamped array |
| Interpolated NOW point | `HealthKitQueryService.swift` → `fetchCumulativeAverageHourlyPattern()` (lines 219-227) | Array + current time `13:30` | `HourlyEnergyData(13:30, 407.0)` where `407.0 = 389.0 + (425.0-389.0)*0.5` | Linear interpolation between hours |
| Cached data | `AverageDataCache.swift` → `AverageDataCacheManager.save()` | Array with NOW point + projected total | JSON file: `{"averageHourlyPattern": [...], "projectedTotal": 1034.0, ...}` | Saves to App Group for fast widget loading |
| Average at current hour | `DailyActiveEnergyWidget.swift` → `loadFreshEntry()` (line 282) | Average array | `averageAtCurrentHour = 407.0` | Extracts or interpolates value at NOW |
| Widget entry field | `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` | `averageAtCurrentHour = 407.0` | `EnergyWidgetEntry(averageAtCurrentHour: 407.0, ...)` | Bundles into entry |
| View parameter | `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 333) | `entry.averageAtCurrentHour` | `EnergyTrendView(averageAtCurrentHour: 407.0, ...)` | Passes to view |
| UI display | `EnergyTrendView.swift` → `HeaderStatistic` (line 26) | `averageAtCurrentHour = 407.0` | `⚫ Average\n407 cal` | Renders in gray with "Average" label |
| **TOTAL HEADER** |
| Raw HealthKit samples (reused) | `HealthKitQueryService.swift` → `fetchAverageData()` | Same 30-day samples as Average | Same sample array | Reuses same query for efficiency |
| Daily totals array | `HealthKitQueryService.swift` → `fetchDailyTotals()` (lines 114-138) | Array of HKQuantitySample | `[1050.0, 1020.0, 998.0, ..., 1032.0]` | Groups by day and sums to complete totals |
| Projected total | `HealthKitQueryService.swift` → `fetchAverageData()` (line 74) | Daily totals array | `projectedTotal = 31020.0 / 30 = 1034.0` | Averages all daily totals |
| Cached (reused) | `AverageDataCache.swift` → `AverageDataCacheManager.save()` | `projectedTotal = 1034.0` | JSON field: `"projectedTotal": 1034.0` | Cached with average pattern |
| Widget entry field | `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` | `projectedTotal = 1034.0` | `EnergyWidgetEntry(projectedTotal: 1034.0, ...)` | Bundles into entry |
| View parameter | `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 337) | `entry.projectedTotal` | `EnergyTrendView(projectedTotal: 1034.0, ...)` | Passes to view |
| UI display | `EnergyTrendView.swift` → `HeaderStatistic` (line 29) | `projectedTotal = 1034.0` | `⚫ Total\n1034 cal` | Renders in light gray with "Total" label |
| **TODAY LINE** |
| Cumulative array (reused) | From "Today Header" Steps 1-3 | Same query | `[HourlyEnergyData(00:00, 0), ..., HourlyEnergyData(13:30, 467.0)]` | Reuses today's cumulative data |
| Widget entry array field | `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (line 21) | Full array | `EnergyWidgetEntry(todayHourlyData: [...], ...)` | Stores entire array for chart |
| View parameter | `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 334) | `entry.todayHourlyData` | `EnergyTrendView(todayHourlyData: [...], ...)` | Passes array to view |
| Chart component | `EnergyTrendView.swift` → `EnergyChartView` (line 36) | Array parameter | `EnergyChartView(todayHourlyData: [...], ...)` | Passes to chart |
| Chart line marks | `EnergyChartView.swift` → `todayLine` (lines 267-275) | Array of data points | Pink line: `LineMark(00:00, 0) → LineMark(01:00, 45.2) → ... → LineMark(13:30, 467.0)` | Renders continuous pink line, 4pt width |
| **TODAY MARKER** |
| Last data point | `EnergyChartView.swift` → `todayPoint` (line 288) | `todayHourlyData` array | `last = HourlyEnergyData(13:30, 467.0)` | Extracts last element |
| Chart point marks | `EnergyChartView.swift` → `todayPoint` (lines 287-293) | Last point + NOW time | Two circles: `PointMark(x: 13:30, y: 467.0)` in background (256) + pink (100) | Renders layered circles at NOW position |
| **AVERAGE LINE** |
| Average array (reused) | From "Average Header" Steps 1-6 | Same query/cache | `[HourlyEnergyData(00:00, 0), ..., 24 hours + interpolated NOW]` | Reuses average pattern |
| Widget entry array field | `DailyActiveEnergyWidget.swift` → `EnergyWidgetEntry` (line 22) | Full array | `EnergyWidgetEntry(averageHourlyData: [...], ...)` | Stores entire 24-hour pattern |
| View parameter | `DailyActiveEnergyWidget.swift` → `DailyActiveEnergyWidgetEntryView` (line 335) | `entry.averageHourlyData` | `EnergyTrendView(averageHourlyData: [...], ...)` | Passes array to view |
| Chart component | `EnergyTrendView.swift` → `EnergyChartView` (line 37) | Array parameter | `EnergyChartView(averageHourlyData: [...], ...)` | Passes to chart |
| Cleaned data | `EnergyChartView.swift` → `cleanedAverageData` (lines 197-202) | Array with possible stale NOW | `[HourlyEnergyData(00:00, 0), HourlyEnergyData(01:00, 40.5), ...]` (only minute==0) | Filters out stale interpolated points |
| Fresh interpolated NOW | `EnergyChartView.swift` → `interpolatedAverageAtNow` (lines 205-210) | Cleaned data + current time | `HourlyEnergyData(13:30, 407.0)` | Recalculates current interpolation |
| Before NOW segment | `EnergyChartView.swift` → `averageDataBeforeNow` (lines 213-219) | Cleaned + NOW point | `[00:00→0, 01:00→40.5, ..., 13:00→389.0, 13:30→407.0]` | Past data up to NOW |
| After NOW segment | `EnergyChartView.swift` → `averageDataAfterNow` (lines 221-237) | Cleaned + NOW point | `[13:30→407.0, 14:00→425.0, ..., 00:00→1034.0]` | NOW to end of day |
| Chart line (before NOW) | `EnergyChartView.swift` → `averageLines` (lines 240-253) | Before NOW array | Dark gray line: `LineMark(00:00, 0) → ... → LineMark(13:30, 407.0)` | Darker gray (.systemGray4), series "AverageUpToNow" |
| Chart line (after NOW) | `EnergyChartView.swift` → `averageLines` (lines 255-265) | After NOW array | Light gray line: `LineMark(13:30, 407.0) → ... → LineMark(00:00, 1034.0)` | Lighter gray (.systemGray6), series "AverageRestOfDay" |
| **AVERAGE MARKER** |
| Interpolated NOW (reused) | From "Average Line" Step 11 | Same interpolation | `HourlyEnergyData(13:30, 407.0)` | Reuses interpolated point |
| Chart point marks | `EnergyChartView.swift` → `averagePoint` (lines 278-284) | Interpolated point | Two circles: `PointMark(x: 13:30, y: 407.0)` in background (256) + dark gray (100) | Renders layered circles at NOW, matches "before" line color |
