---
name: swift-charts-advanced
description: Expert Swift Charts patterns including custom axis marks, label positioning and collision detection, @ChartContentBuilder composition, GeometryReader integration, and chart performance optimization. Use when building complex charts beyond basic bar/line marks.
---

# Swift Charts - Advanced Patterns

Expert guidance for building sophisticated charts with Swift Charts framework, including custom axis customization, label collision detection, and performance optimization.

## When to Use This Skill

- Building charts with custom axis labels and tick marks
- Implementing label collision detection to prevent overlap
- Using GeometryReader for chart positioning and layout calculations
- Creating conditional chart marks with @ChartContentBuilder
- Composing complex charts from multiple mark types (LineMark, RuleMark, PointMark)
- Customizing chart axes with @AxisMarkBuilder
- Performance optimization for charts with many data points
- Implementing "now" indicators or reference lines

## Chart Basics - Composition with @ChartContentBuilder

### Understanding @ChartContentBuilder

**From Apple Docs:**
> A result builder that creates chart content from closures. Use this to compose multiple chart marks into a single chart.

### Pattern: Extract Chart Marks into Computed Properties

**From HealthTrends:** Composing chart marks for clean, maintainable code

```swift
// From EnergyChartView.swift:239-318
@ChartContentBuilder
private var averageLines: some ChartContent {
    let darkGray = Color(.systemGray4)
    let lightGray = Color(.systemGray6)

    // BEFORE NOW: darker gray line (past data → NOW)
    ForEach(averageDataBeforeNow) { data in
        LineMark(
            x: .value("Hour", data.hour),
            y: .value("Calories", data.calories),
            series: .value("Series", "AverageUpToNow")
        )
        .foregroundStyle(darkGray)
        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    // AFTER NOW: lighter gray line (NOW → future data)
    ForEach(averageDataAfterNow) { data in
        LineMark(
            x: .value("Hour", data.hour),
            y: .value("Calories", data.calories),
            series: .value("Series", "AverageRestOfDay")
        )
        .foregroundStyle(lightGray)
        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

@ChartContentBuilder
private var todayLine: some ChartContent {
    // Single continuous line including current hour progress
    ForEach(todayHourlyData) { data in
        LineMark(
            x: .value("Hour", data.hour),
            y: .value("Calories", data.calories),
            series: .value("Series", "Today")
        )
        .foregroundStyle(activeEnergyColor)
        .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

@ChartContentBuilder
private var goalLine: some ChartContent {
    if moveGoal > 0 {
        RuleMark(y: .value("Goal", moveGoal))
            .foregroundStyle(goalColor.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

@ChartContentBuilder
private var nowLine: some ChartContent {
    RuleMark(x: .value("Now", now))
        .foregroundStyle(Color(.systemGray5))
        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
}

// Composition in body
Chart {
    nowLine       // Vertical line at NOW
    goalLine      // Horizontal line at goal
    averageLines  // Two-tone average line (past/future)
    averagePoint  // Dot at NOW on average line
    todayLine     // Today's progress line
    todayPoint    // Dot at NOW on today line
}
```

**Benefits:**
- Clear separation of concerns (each line type is isolated)
- Easy to reorder marks (layering is explicit)
- Business logic stays in computed properties
- Chart composition reads like a table of contents

### Mark Types and Layering

**Key insight:** Order matters! Marks are drawn in order, so background marks first, foreground last.

```swift
Chart {
    // 1. Background reference lines
    goalLine      // Draw goal first (background)
    nowLine       // Draw "now" indicator (background)

    // 2. Data lines
    averageLines  // Draw average pattern
    todayLine     // Draw today's progress

    // 3. Foreground points (drawn last so they're on top)
    averagePoint  // Dots appear above lines
    todayPoint
}
```

**Common Mark Types:**
- `LineMark`: Continuous data (trends, cumulative values)
- `BarMark`: Discrete comparisons (daily totals, categories)
- `PointMark`: Individual data points, current value indicators
- `RuleMark`: Reference lines (goals, averages, thresholds)
- `AreaMark`: Filled regions (confidence intervals, ranges)

## GeometryReader for Chart Positioning

### Using GeometryReader for Chart Layout

**Pattern:** Wrap chart in GeometryReader to access dimensions for calculations

```swift
// From EnergyChartView.swift:312-377
GeometryReader { geometry in
    let chartWidth = geometry.size.width
    let chartHeight = geometry.size.height
    let maxValue = chartMaxValue(chartHeight: chartHeight)

    VStack(spacing: 0) {
        Chart {
            // Chart marks...
        }
        .frame(maxHeight: .infinity)
        .chartXScale(domain: startOfDay...endOfDay)
        .chartYScale(domain: 0...maxValue)
        .overlay {
            // Position goal label using geometry
            if moveGoal > 0 {
                let goalYPosition = chartHeight * (1 - moveGoal / maxValue)

                Text("\(Int(moveGoal)) cal")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(goalColor)
                    .padding(2)
                    .background(.background.opacity(0.5))
                    .cornerRadius(4)
                    .offset(x: -2, y: goalYPosition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }

        // Pass chartWidth to custom axis labels
        ChartXAxisLabels(chartWidth: chartWidth)
            .padding(.top, 8)
    }
}
```

**Key technique:** Calculate positions as proportions of chart dimensions, then overlay labels

### Custom X-Axis Labels with GeometryReader

**From HealthTrends:** Smart label positioning that adapts to current time

```swift
// From EnergyChartView.swift:65-144
private struct ChartXAxisLabels: View {
    let chartWidth: CGFloat

    private var calendar: Calendar { Calendar.current }
    private var now: Date { Date() }

    var body: some View {
        ZStack(alignment: .bottom) {
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let collisions = calculateLabelCollisions(chartWidth: chartWidth, now: now)

            // Start of day - left aligned (hide if collides with NOW)
            if !collisions.hidesStart {
                Text(startOfDay, format: .dateTime.hour())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // NOW - centered at natural position
            Text(now, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: /* calculated */)
                .offset(x: /* calculated */)

            // End of day - right aligned (hide if collides with NOW)
            if !collisions.hidesEnd {
                Text(endOfDay, format: .dateTime.hour())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 20, alignment: .bottom)
    }
}
```

**Pattern:** Use ZStack with calculated alignments and offsets for precise label positioning

## Label Collision Detection

### Algorithm: Detect Overlapping Labels

**From HealthTrends:** Prevent label overlap on time-based charts

```swift
// From EnergyChartView.swift:32-60
private func calculateLabelCollisions(chartWidth: CGFloat, now: Date) -> (hidesStart: Bool, hidesEnd: Bool) {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: now)
    let nowOffset = now.timeIntervalSince(startOfDay)
    let dayDuration = TimeInterval(24 * 60 * 60)
    let nowPosition = chartWidth * (nowOffset / dayDuration)

    // Measure actual text widths for accurate collision detection
    let nowFormatter = Date.FormatStyle().hour().minute()
    let nowLabelText = now.formatted(nowFormatter)
    let nowLabelWidth = measureTextWidth(nowLabelText, textStyle: .caption1)

    let hourFormatter = Date.FormatStyle().hour()
    let startLabelText = startOfDay.formatted(hourFormatter)
    let startEndLabelWidth = measureTextWidth(startLabelText, textStyle: .caption1)

    let minSeparation: CGFloat = 4

    let nowLeft = nowPosition - nowLabelWidth / 2
    let nowRight = nowPosition + nowLabelWidth / 2

    let startLabelRight = startEndLabelWidth
    let hidesStart = nowLeft < (startLabelRight + minSeparation)

    let endLabelLeft = chartWidth - startEndLabelWidth
    let hidesEnd = nowRight > (endLabelLeft - minSeparation)

    return (hidesStart, hidesEnd)
}
```

**Algorithm steps:**
1. Calculate NOW position as proportion of day progress
2. Measure actual text widths of all labels
3. Calculate left/right edges of NOW label (considering center alignment)
4. Check if NOW label edges overlap with start/end labels (+ minimum separation)
5. Return flags indicating which labels should be hidden

**Helper: Measure Text Width**

```swift
// Measure text width for collision detection
func measureTextWidth(_ text: String, textStyle: UIFont.TextStyle) -> CGFloat {
    let font = UIFont.preferredFont(forTextStyle: textStyle)
    let attributes = [NSAttributedString.Key.font: font]
    let size = (text as NSString).size(withAttributes: attributes)
    return size.width
}
```

### Edge Case: NOW Label Near Edges

**Problem:** Centered label can overflow chart edges when NOW is very early or late in the day

**Solution:** Dynamically adjust alignment and offset

```swift
// From EnergyChartView.swift:86-132
Text(now, format: .dateTime.hour().minute())
    .font(.caption)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: {
        let startOfDay = calendar.startOfDay(for: now)
        let nowOffset = now.timeIntervalSince(startOfDay)
        let dayDuration = TimeInterval(24 * 60 * 60)
        let nowPosition = chartWidth * (nowOffset / dayDuration)

        let nowLabelWidth = measureTextWidth(nowLabelText, textStyle: .caption1)

        // Check if centering would put label out of bounds
        let centeredLeft = nowPosition - nowLabelWidth / 2
        let centeredRight = nowPosition + nowLabelWidth / 2

        if centeredLeft < 0 {
            return .leading  // Too close to left edge
        } else if centeredRight > chartWidth {
            return .trailing  // Too close to right edge
        } else {
            return .center  // Safe to center
        }
    }())
    .offset(x: {
        // Calculate offset for centering (or 0 for edge alignment)
        let nowPosition = chartWidth * (nowOffset / dayDuration)
        let centeredLeft = nowPosition - nowLabelWidth / 2
        let centeredRight = nowPosition + nowLabelWidth / 2

        if centeredLeft < 0 || centeredRight > chartWidth {
            return 0  // Edge-aligned, no offset needed
        } else {
            return nowPosition - chartWidth / 2  // Centered with offset
        }
    }())
```

**Key insight:** Use both `.frame(alignment:)` and `.offset(x:)` together for precise positioning

## Custom Axis Marks with @AxisMarkBuilder

### Understanding @AxisMarkBuilder

**Pattern:** Conditionally render axis marks based on business logic

```swift
// From EnergyChartView.swift:163-181
@AxisMarkBuilder
private func hourlyTickMark(
    for date: Date,
    startOfDay: Date,
    endOfDay: Date,
    collisions: (hidesStart: Bool, hidesEnd: Bool),
    now: Date
) -> some AxisMark {
    let minutesFromNow = abs(date.timeIntervalSince(now)) / 60

    // Don't show tick if too close to NOW (within 20 minutes)
    if minutesFromNow >= 20 {
        let isStartOfDay = abs(date.timeIntervalSince(startOfDay)) < 60
        let isEndOfDay = abs(date.timeIntervalSince(endOfDay)) < 60
        let showTickLine = (isStartOfDay && !collisions.hidesStart)
                        || (isEndOfDay && !collisions.hidesEnd)

        if showTickLine {
            // Visible labeled hours: tick line
            AxisTick(centered: true, length: 6, stroke: StrokeStyle(lineWidth: 2, lineCap: .round))
                .offset(CGSize(width: 0, height: 8))
        } else {
            // Unlabeled hours or hidden labels: dot
            AxisTick(centered: true, length: 0, stroke: StrokeStyle(lineWidth: 2, lineCap: .round))
                .offset(CGSize(width: 0, height: 11))
        }
    }
}
```

### Using Custom Axis Marks in Chart

```swift
// From EnergyChartView.swift:330-347
.chartXAxis {
    // Calculate constants once (not 24 times per render!)
    let startOfDay = calendar.startOfDay(for: Date())
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
    let collisions = calculateLabelCollisions(chartWidth: chartWidth, now: now)

    // Hourly tick marks
    AxisMarks(values: .stride(by: .hour, count: 1)) { value in
        if let date = value.as(Date.self) {
            hourlyTickMark(
                for: date,
                startOfDay: startOfDay,
                endOfDay: endOfDay,
                collisions: collisions,
                now: now
            )
        }
    }

    // NOW tick mark (matches labeled hour styling)
    AxisMarks(values: [now]) { _ in
        AxisTick(centered: true, length: 6, stroke: StrokeStyle(lineWidth: 2, lineCap: .round))
            .offset(CGSize(width: 0, height: 8))
    }
}
```

**Key technique:** Pre-calculate constants outside of `AxisMarks` iteration for performance

## Chart Scales and Domains

### Setting Chart Scales

**Pattern:** Control axis ranges for consistent visualization

```swift
Chart {
    // Chart marks...
}
.chartXScale(domain: Calendar.current.startOfDay(for: Date())...endOfDay)
.chartYScale(domain: 0...maxValue)
```

**Why set domains explicitly:**
- Prevent chart from auto-scaling to extreme outliers
- Ensure consistent visualization across updates
- Control what data ranges are visible

### Dynamic Y-Scale Based on Data

```swift
// From EnergyChartView.swift:184-191
private func chartMaxValue(chartHeight: CGFloat) -> Double {
    return max(
        todayHourlyData.last?.calories ?? 0,
        averageHourlyData.last?.calories ?? 0,
        moveGoal,
        projectedTotal
    )
}
```

**Pattern:** Set Y-scale to the maximum of all visible data + reference lines

## Chart Performance Optimization

### Key Principle: Calculate Constants Outside Loops

**From Apple Docs - Understanding and Improving SwiftUI Performance:**
> Layout readers, including chart axes, observe layout changes in their parent views to recalculate layouts. Reduce simultaneous layout and state updates by calculating constants once.

**Anti-pattern:**
```swift
// ❌ BAD: Recalculates 24 times per render
.chartXAxis {
    AxisMarks(values: .stride(by: .hour, count: 1)) { value in
        if let date = value.as(Date.self) {
            // These run 24 times!
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let collisions = calculateLabelCollisions(chartWidth: chartWidth, now: now)

            hourlyTickMark(for: date, /* ... */)
        }
    }
}
```

**Better pattern:**
```swift
// ✅ GOOD: Calculate once, use many times
.chartXAxis {
    // Calculate constants once (not 24 times per render!)
    let startOfDay = calendar.startOfDay(for: Date())
    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
    let collisions = calculateLabelCollisions(chartWidth: chartWidth, now: now)

    // Now use these in iteration
    AxisMarks(values: .stride(by: .hour, count: 1)) { value in
        if let date = value.as(Date.self) {
            hourlyTickMark(for: date, startOfDay: startOfDay, endOfDay: endOfDay,
                          collisions: collisions, now: now)
        }
    }
}
```

**From HealthTrends:** See EnergyChartView.swift:331-341

### Limit Data Points for Large Datasets

**Strategy:** Aggregate or sample data before charting

```swift
// For very large datasets, downsample before rendering
func downsampleData(_ data: [DataPoint], maxPoints: Int) -> [DataPoint] {
    guard data.count > maxPoints else { return data }

    let stride = data.count / maxPoints
    return stride(from: 0, to: data.count, by: stride).map { data[$0] }
}

// Usage
let chartData = downsampleData(allData, maxPoints: 100)
```

**When to use:**
- Datasets with hundreds or thousands of points
- Chart performance is noticeably slow
- Visual fidelity isn't compromised by aggregation

### Minimize Chart Updates

**Pattern:** Only update chart when meaningful data changes

```swift
// From ContentView.swift (adapted for charts)
@State private var lastRefreshMinute: Int = Calendar.current.component(.minute, from: Date())

.onReceive(timer) { _ in
    // Only refresh when we cross a minute boundary
    let currentMinute = Calendar.current.component(.minute, from: Date())
    guard currentMinute != lastRefreshMinute else { return }
    lastRefreshMinute = currentMinute

    // Now update chart data
    updateChartData()
}
```

**Key insight:** Check frequently (every second), but only trigger expensive updates when necessary (every minute)

## Data Preparation for Charts

### Computing Cumulative Data

**Pattern:** Transform raw data into cumulative values for line charts

```swift
// Example: Convert hourly calories to cumulative total
func toCumulativeData(_ hourlyData: [HourlyData]) -> [HourlyData] {
    var cumulative: Double = 0
    return hourlyData.map { data in
        cumulative += data.calories
        return HourlyData(hour: data.hour, calories: cumulative)
    }
}
```

### Interpolating Data Points

**Pattern:** Calculate intermediate values for smooth visualizations

```swift
// From HealthTrends: Interpolate average value at current time
extension Array where Element == HourlyEnergyData {
    func interpolatedValue(at date: Date) -> Double? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        // Find bounding data points
        guard let currentHourData = self.first(where: { calendar.component(.hour, from: $0.hour) == hour }),
              let nextHourData = self.first(where: { calendar.component(.hour, from: $0.hour) == hour + 1 })
        else {
            return self.last?.calories
        }

        // Linear interpolation
        let interpolationFactor = Double(minute) / 60.0
        return currentHourData.calories + (nextHourData.calories - currentHourData.calories) * interpolationFactor
    }
}
```

### Filtering and Cleaning Data

**Pattern:** Remove stale or invalid data points before charting

```swift
// From EnergyChartView.swift:196-202
private var cleanedAverageData: [HourlyEnergyData] {
    averageHourlyData.filter { data in
        let minute = calendar.component(.minute, from: data.hour)
        return minute == 0  // Only keep on-the-hour data points
    }
}
```

**Use cases:**
- Remove interpolated points from cached data
- Filter out zero-value artifacts
- Exclude outliers that would skew the chart

## Styling Charts

### Colors and Visual Hierarchy

**Pattern:** Use color to convey meaning and hierarchy

```swift
// From EnergyChartView.swift
private let activeEnergyColor: Color = Color(red: 254/255, green: 73/255, blue: 1/255)  // Bright pink
private let goalColor: Color = Color(.systemGray)  // Neutral gray
private let lineWidth: CGFloat = 4

// Visual hierarchy through color and style
@ChartContentBuilder
private var averageLines: some ChartContent {
    let darkGray = Color(.systemGray4)   // Past: more prominent
    let lightGray = Color(.systemGray6)  // Future: less prominent

    // Past data is darker, future data is lighter
    ForEach(averageDataBeforeNow) { data in
        LineMark(/* ... */).foregroundStyle(darkGray)
    }
    ForEach(averageDataAfterNow) { data in
        LineMark(/* ... */).foregroundStyle(lightGray)
    }
}
```

**Semantic colors:**
- Use system colors (`.primary`, `.secondary`) for adaptability
- Use semantic colors (`.red` for errors, `.green` for success)
- Test in both light and dark mode

### Line Styles

```swift
// Solid line
.lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

// Dashed line (for goals, projections)
.lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
```

### Point Styles

```swift
// From EnergyChartView.swift:281-283
PointMark(x: .value("Hour", interpolated.hour), y: .value("Calories", interpolated.calories))
    .foregroundStyle(.background)  // White halo
    .symbolSize(256)

PointMark(x: .value("Hour", interpolated.hour), y: .value("Calories", interpolated.calories))
    .foregroundStyle(Color(.systemGray4))  // Colored center
    .symbolSize(100)
```

**Pattern:** Layer two PointMarks (large background + smaller foreground) for a halo effect

## Common Pitfalls & Solutions

### Issue: Labels Overlap at Chart Edges

**Problem:** Centered labels can overflow chart bounds when data is at extremes

**Solution:** Use edge alignment when center alignment would overflow (see "Edge Case: NOW Label Near Edges")

### Issue: Chart Marks Appear in Wrong Order

**Problem:** Background elements drawn on top of data

**Solution:** Order matters! Draw marks from background to foreground:

```swift
Chart {
    // 1. Background (reference lines)
    nowLine
    goalLine

    // 2. Data lines
    averageLines
    todayLine

    // 3. Foreground (points on top)
    averagePoint
    todayPoint
}
```

### Issue: Axis Marks Perform Poorly

**Problem:** Calculating constants inside `AxisMarks` iteration causes performance hitches

**Solution:** Calculate constants once outside the iteration (see "Chart Performance Optimization")

### Issue: Chart Doesn't Update When Data Changes

**Problem:** Chart data not marked as `@State` or `@Observable`

**Solution:** Ensure data source is observable:

```swift
@Observable
class ChartDataManager {
    var todayData: [DataPoint] = []
    var averageData: [DataPoint] = []
}

struct MyChartView: View {
    var dataManager: ChartDataManager  // Automatically observed

    var body: some View {
        Chart {
            ForEach(dataManager.todayData) { data in
                LineMark(/* ... */)
            }
        }
    }
}
```

## Best Practices Summary

1. **Chart Composition:** Extract marks into `@ChartContentBuilder` computed properties for clean composition
2. **Collision Detection:** Measure actual text widths, calculate positions mathematically, handle edge cases
3. **GeometryReader:** Use for positioning calculations, pass dimensions to child views, avoid nesting
4. **Custom Axis Marks:** Use `@AxisMarkBuilder` for conditional rendering, calculate constants once
5. **Performance:** Calculate outside loops, limit data points, minimize updates
6. **Data Preparation:** Transform to cumulative, interpolate for smoothness, filter/clean before charting
7. **Styling:** Use semantic colors, test light/dark mode, create visual hierarchy through color/weight
8. **Layering:** Order marks from background to foreground for correct visual hierarchy

## See Also

- **swiftui-advanced skill**: For GeometryReader patterns, result builders, performance profiling with Instruments
- **healthkit-queries skill**: For preparing HealthKit data for charting (cumulative patterns, date/time handling)

## References

- Apple Docs: [Chart](https://developer.apple.com/documentation/charts/chart/)
- Apple Docs: [ChartContentBuilder](https://developer.apple.com/documentation/charts/chartcontentbuilder/)
- Apple Docs: [AxisMark](https://developer.apple.com/documentation/charts/axismark/)
- Apple Docs: [LineMark](https://developer.apple.com/documentation/charts/linemark/)
- Apple Docs: [RuleMark](https://developer.apple.com/documentation/charts/rulemark/)
- Apple Docs: [PointMark](https://developer.apple.com/documentation/charts/pointmark/)
- HealthTrends: `EnergyChartView.swift` (377 lines of advanced Swift Charts patterns)
