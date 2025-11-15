import SwiftUI
import Charts

// MARK: - Constants

private let activeEnergyColor: Color = Color(red: 254/255, green: 73/255, blue: 1/255)
private let goalColor: Color = Color(.systemGray)
private let lineWidth: CGFloat = 4

/// Debug: Override current time for testing. Set to nil to use real time.
/// Examples:
/// - Calendar.current.date(from: DateComponents(hour: 2, minute: 10))  // 2:10 AM
/// - Calendar.current.date(from: DateComponents(hour: 4, minute: 30))  // 4:30 AM
/// - Calendar.current.date(from: DateComponents(hour: 13, minute: 40)) // 1:40 PM
private let debugNowOverride: Date? = nil

// MARK: - Helper Functions

/// Helper to get current time (or debug override)
private func getCurrentTime() -> Date {
    if let override = debugNowOverride {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.hour, .minute], from: override)
        return calendar.date(byAdding: components, to: today) ?? Date()
    }
    return Date()
}

/// Helper to determine if NOW label collides with start/end of day labels
private func calculateLabelCollisions(chartWidth: CGFloat, now: Date) -> (hidesStart: Bool, hidesEnd: Bool) {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: now)
    let nowOffset = now.timeIntervalSince(startOfDay)
    let dayDuration = TimeInterval(24 * 60 * 60)
    let nowPosition = chartWidth * (nowOffset / dayDuration)

    let nowLabelWidth: CGFloat = 50  // "6:10 AM" with minutes
    let startEndLabelWidth: CGFloat = 35  // "12 AM" without minutes
    let minSeparation: CGFloat = 4

    let nowLeft = nowPosition - nowLabelWidth / 2
    let nowRight = nowPosition + nowLabelWidth / 2

    let startLabelRight = startEndLabelWidth
    let hidesStart = nowLeft < (startLabelRight + minSeparation)

    let endLabelLeft = chartWidth - startEndLabelWidth
    let hidesEnd = nowRight > (endLabelLeft - minSeparation)

    return (hidesStart, hidesEnd)
}

// MARK: - X-Axis Labels

/// X-axis labels component (start of day, current hour, end of day)
private struct ChartXAxisLabels: View {
    let chartWidth: CGFloat

    private var calendar: Calendar { Calendar.current }
    private var now: Date { getCurrentTime() }

    var body: some View {
        ZStack(alignment: .bottom) {
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let collisions = calculateLabelCollisions(chartWidth: chartWidth, now: now)

            // Start of day - left aligned (hide if collides with current hour)
            if !collisions.hidesStart {
                Text(startOfDay, format: .dateTime.hour())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // NOW - centered at natural position, but edge-aligned if that would go out of bounds
            Text(now, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: {
                    let startOfDay = calendar.startOfDay(for: now)
                    let nowOffset = now.timeIntervalSince(startOfDay)
                    let dayDuration = TimeInterval(24 * 60 * 60)
                    let nowPosition = chartWidth * (nowOffset / dayDuration)
                    let nowLabelWidth: CGFloat = 50

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
                    let startOfDay = calendar.startOfDay(for: now)
                    let nowOffset = now.timeIntervalSince(startOfDay)
                    let dayDuration = TimeInterval(24 * 60 * 60)
                    let nowPosition = chartWidth * (nowOffset / dayDuration)
                    let nowLabelWidth: CGFloat = 50

                    // Check if centering would put label out of bounds
                    let centeredLeft = nowPosition - nowLabelWidth / 2
                    let centeredRight = nowPosition + nowLabelWidth / 2

                    if centeredLeft < 0 || centeredRight > chartWidth {
                        return 0  // Edge-aligned, no offset needed
                    } else {
                        return nowPosition - chartWidth / 2  // Centered with offset
                    }
                }())

            // End of day - right aligned (hide if collides with current hour)
            if !collisions.hidesEnd {
                Text(endOfDay, format: .dateTime.hour())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 20, alignment: .bottom) // Fixed height for labels
    }
}

// MARK: - Energy Chart View

struct EnergyChartView: View {
    let todayHourlyData: [HourlyEnergyData]
    let averageHourlyData: [HourlyEnergyData]
    let moveGoal: Double
    let projectedTotal: Double

    private var calendar: Calendar { Calendar.current }
    private var now: Date { getCurrentTime() }
    private var currentHour: Int { calendar.component(.hour, from: now) }
    private var startOfCurrentHour: Date {
        calendar.dateInterval(of: .hour, for: now)!.start
    }

    /// Renders an hourly tick mark with appropriate styling
    /// Returns nothing if the hour is too close to NOW (within 20 minutes)
    @AxisMarkBuilder
    private func hourlyTickMark(for date: Date, startOfDay: Date, endOfDay: Date, collisions: (hidesStart: Bool, hidesEnd: Bool), now: Date) -> some AxisMark {
        let minutesFromNow = abs(date.timeIntervalSince(now)) / 60
        if minutesFromNow >= 20 {
            let isStartOfDay = abs(date.timeIntervalSince(startOfDay)) < 60
            let isEndOfDay = abs(date.timeIntervalSince(endOfDay)) < 60
            let showTickLine = (isStartOfDay && !collisions.hidesStart) || (isEndOfDay && !collisions.hidesEnd)

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

    /// Calculate max value for chart Y-axis
    private func chartMaxValue(chartHeight: CGFloat) -> Double {
        return max(
            todayHourlyData.last?.calories ?? 0,
            averageHourlyData.last?.calories ?? 0,
            moveGoal,
            projectedTotal
        )
    }

    /// Calculate interpolated average value at current time
    private var interpolatedAverageAtNow: (hour: Date, calories: Double)? {
        guard let interpolatedCalories = averageHourlyData.interpolatedValue(at: now) else {
            return nil
        }
        return (now, interpolatedCalories)
    }

    @ChartContentBuilder
    private var averageLines: some ChartContent {
        let interpolated = interpolatedAverageAtNow

        // Average data - up to current hour (darker gray)
        ForEach(averageHourlyData.filter { $0.hour < startOfCurrentHour }) { data in
            LineMark(x: .value("Hour", data.hour), y: .value("Calories", data.calories), series: .value("Series", "AverageUpToNow"))
                .foregroundStyle(Color(.systemGray4))
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        // Current hour start to NOW (interpolated)
        if let interpolated = interpolated,
           let currentHourData = averageHourlyData.first(where: { $0.hour == startOfCurrentHour }) {
            LineMark(x: .value("Hour", currentHourData.hour), y: .value("Calories", currentHourData.calories), series: .value("Series", "AverageUpToNow"))
                .foregroundStyle(Color(.systemGray4))
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            LineMark(x: .value("Hour", interpolated.hour), y: .value("Calories", interpolated.calories), series: .value("Series", "AverageUpToNow"))
                .foregroundStyle(Color(.systemGray4))
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        // NOW (interpolated) to rest of day (lighter gray)
        if let interpolated = interpolated {
            // Add interpolated point and explicitly connect to next hour to form first segment
            let nextHourStart = calendar.date(byAdding: .hour, value: 1, to: startOfCurrentHour)!
            if let nextHourData = averageHourlyData.first(where: { $0.hour == nextHourStart }) {
                LineMark(x: .value("Hour", interpolated.hour), y: .value("Calories", interpolated.calories), series: .value("Series", "AverageRestOfDay"))
                    .foregroundStyle(Color(.systemGray6))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                LineMark(x: .value("Hour", nextHourData.hour), y: .value("Calories", nextHourData.calories), series: .value("Series", "AverageRestOfDay"))
                    .foregroundStyle(Color(.systemGray6))
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        // Continue with remaining hours (skip next hour since we already added it above)
        let nextHourStart = calendar.date(byAdding: .hour, value: 1, to: startOfCurrentHour)!
        ForEach(averageHourlyData.filter { $0.hour > nextHourStart }) { data in
            LineMark(x: .value("Hour", data.hour), y: .value("Calories", data.calories), series: .value("Series", "AverageRestOfDay"))
                .foregroundStyle(Color(.systemGray6))
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    @ChartContentBuilder
    private var todayLine: some ChartContent {
        // Single continuous line including current hour progress
        ForEach(todayHourlyData) { data in
            LineMark(x: .value("Hour", data.hour), y: .value("Calories", data.calories), series: .value("Series", "Today"))
                .foregroundStyle(activeEnergyColor)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    @ChartContentBuilder
    private var averagePoint: some ChartContent {
        // Show average point at NOW (interpolated value)
        if let interpolated = interpolatedAverageAtNow {
            PointMark(x: .value("Hour", now), y: .value("Calories", interpolated.calories)).foregroundStyle(.background).symbolSize(256)
            PointMark(x: .value("Hour", now), y: .value("Calories", interpolated.calories)).foregroundStyle(Color(.systemGray4)).symbolSize(100)
        }
    }

    @ChartContentBuilder
    private var todayPoint: some ChartContent {
        if let last = todayHourlyData.last {
            // Use NOW for x-position to align with average point and now line
            PointMark(x: .value("Hour", now), y: .value("Calories", last.calories)).foregroundStyle(.background).symbolSize(256)
            PointMark(x: .value("Hour", now), y: .value("Calories", last.calories)).foregroundStyle(activeEnergyColor).symbolSize(100)
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

    var body: some View {
        GeometryReader { geometry in
            let chartWidth = geometry.size.width
            let chartHeight = geometry.size.height
            let maxValue = chartMaxValue(chartHeight: chartHeight)

            VStack(spacing: 0) {
                // Chart with flexible height
                Chart {
                    nowLine
                    goalLine
                    averageLines
                    averagePoint
                    todayLine
                    todayPoint
                }
                .frame(maxHeight: .infinity)
                .chartXScale(domain: Calendar.current.startOfDay(for: Date())...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!)
                .chartYScale(domain: 0...maxValue)
                .chartXAxis {
                    // Calculate constants once (not 24 times per render!)
                    let startOfDay = calendar.startOfDay(for: Date())
                    let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
                    let collisions = calculateLabelCollisions(chartWidth: chartWidth, now: now)

                    // Hourly tick marks
                    AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                        if let date = value.as(Date.self) {
                            hourlyTickMark(for: date, startOfDay: startOfDay, endOfDay: endOfDay, collisions: collisions, now: now)
                        }
                    }

                    // NOW tick mark (matches labeled hour styling)
                    AxisMarks(values: [now]) { _ in
                        AxisTick(centered: true, length: 6, stroke: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .offset(CGSize(width: 0, height: 8))
                    }
                }
                .chartYAxis {
                    AxisMarks {}
                }
                .overlay {
                    // Goal label
                    if moveGoal > 0 {
                        let goalYPosition = chartHeight * (1 - moveGoal / maxValue)

                        Text("\(Int(moveGoal)) cal")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(goalColor)
                            .padding(2)
                            .background(.background.opacity(0.5))
                            .cornerRadius(4)
                            .offset(
                                x: -2 /* padding */,
                                y: goalYPosition
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }

                // X-axis labels below chart (fixed height)
                ChartXAxisLabels(chartWidth: chartWidth)
                    .padding(.top, 8)
            }
        }
    }
}
