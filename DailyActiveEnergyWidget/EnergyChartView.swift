import Charts
import HealthTrendsShared
import SwiftUI
import WidgetKit

// MARK: - Constants

private let lineWidth: CGFloat = 4

// MARK: - Helper Functions

/// Encapsulates Data Time label positioning calculations
private struct DataTimeLabelPosition {
	let position: CGFloat  // Natural x-position on chart (0...chartWidth)
	let labelWidth: CGFloat
	let chartWidth: CGFloat

	init(dataTime: Date, chartWidth: CGFloat, chartStartHour: Int = 0) {
		let calendar = Calendar.current
		let startOfDay = calendar.startOfDay(for: dataTime)
		let chartStartDate = calendar.date(byAdding: .hour, value: chartStartHour, to: startOfDay)!
		let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

		let dataTimeOffset = dataTime.timeIntervalSince(chartStartDate)
		let chartDuration = endOfDay.timeIntervalSince(chartStartDate)

		self.position = chartWidth * max(0, dataTimeOffset / chartDuration)
		self.chartWidth = chartWidth

		let dataTimeFormatter = Date.FormatStyle().hour().minute()
		let dataTimeLabelText = dataTime.formatted(dataTimeFormatter)
		self.labelWidth = measureTextWidth(dataTimeLabelText, textStyle: .caption1)
	}

	var leftEdge: CGFloat { position - labelWidth / 2 }
	var rightEdge: CGFloat { position + labelWidth / 2 }

	var wouldOverflowLeft: Bool { leftEdge < 0 }
	var wouldOverflowRight: Bool { rightEdge > chartWidth }
	var wouldOverflow: Bool { wouldOverflowLeft || wouldOverflowRight }

	/// Alignment for the label text
	var alignment: Alignment {
		if wouldOverflowLeft {
			return .leading
		} else if wouldOverflowRight {
			return .trailing
		} else {
			return .center
		}
	}

	/// X-offset to position the label
	var offset: CGFloat {
		if wouldOverflow {
			return 0  // Edge-aligned, no offset needed
		} else {
			return position - chartWidth / 2  // Centered with offset
		}
	}
}

/// Helper to determine if Data Time label collides with start/end of day labels
private func calculateLabelCollisions(chartWidth: CGFloat, dataTime: Date, chartStartHour: Int = 0) -> (
	hidesStart: Bool, hidesEnd: Bool
) {
	let labelPos = DataTimeLabelPosition(dataTime: dataTime, chartWidth: chartWidth, chartStartHour: chartStartHour)

	let calendar = Calendar.current
	let startOfDay = calendar.startOfDay(for: dataTime)
	let chartStartDate = calendar.date(byAdding: .hour, value: chartStartHour, to: startOfDay)!
	let hourFormatter = Date.FormatStyle().hour()
	let startLabelText = chartStartDate.formatted(hourFormatter)
	let startEndLabelWidth = measureTextWidth(startLabelText, textStyle: .caption1)

	let minSeparation: CGFloat = 4

	let startLabelRight = startEndLabelWidth
	let hidesStart = labelPos.leftEdge < (startLabelRight + minSeparation)

	let endLabelLeft = chartWidth - startEndLabelWidth
	let hidesEnd = labelPos.rightEdge > (endLabelLeft - minSeparation)

	return (hidesStart, hidesEnd)
}

// MARK: - X-Axis Labels

/// X-axis labels component (start of day, current hour, end of day)
private struct ChartXAxisLabels: View {
	let chartWidth: CGFloat
	let dataTime: Date  // Timestamp of most recent HealthKit data sample
	let labelFont: Font  // Font size for labels
	let chartStartHour: Int  // Hour to start the chart X-axis (0-12)

	@Environment(\.widgetFamily) private var widgetFamily

	private var calendar: Calendar { Calendar.current }

	var body: some View {
		ZStack(alignment: .bottom) {
			let startOfDay = calendar.startOfDay(for: Date())
			let chartStartDate = calendar.date(byAdding: .hour, value: chartStartHour, to: startOfDay)!
			let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
			let dataTimeVisible = dataTime >= chartStartDate
			let collisions = calculateLabelCollisions(
				chartWidth: chartWidth, dataTime: dataTime, chartStartHour: chartStartHour)
			let labelPos = DataTimeLabelPosition(
				dataTime: dataTime, chartWidth: chartWidth, chartStartHour: chartStartHour)

			// Chart start time - left aligned (hide only if data time is visible AND collides)
			if !dataTimeVisible || !collisions.hidesStart {
				Text(chartStartDate, format: .dateTime.hour())
					.font(labelFont)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
			}

			// Data Time - centered at natural position, but edge-aligned if that would go out of bounds
			// Only show if data time is within chart bounds
			if dataTime >= chartStartDate {
				Text(dataTime, format: .dateTime.hour().minute())
					.font(labelFont)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: labelPos.alignment)
					.offset(x: labelPos.offset)
			}

			// End of day - right aligned (hide only if data time is visible AND collides)
			if !dataTimeVisible || !collisions.hidesEnd {
				Text(endOfDay, format: .dateTime.hour())
					.font(labelFont)
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}
		}
		.frame(height: 20, alignment: .bottom)  // Fixed height for labels
	}
}

// MARK: - Energy Chart View

struct EnergyChartView: View {
	let todayHourlyData: [HourlyEnergyData]
	let averageHourlyData: [HourlyEnergyData]
	let moveGoal: Double
	let dataTime: Date  // Timestamp of most recent HealthKit data sample
	let chartStartHour: Int  // Hour to start the chart X-axis (0-12)

	@Environment(\.widgetRenderingMode) var widgetRenderingMode
	@Environment(\.widgetFamily) var widgetFamily

	private var calendar: Calendar { Calendar.current }
	private var currentHour: Int { calendar.component(.hour, from: dataTime) }
	private var startOfCurrentHour: Date {
		calendar.dateInterval(of: .hour, for: dataTime)!.start
	}

	/// The start date for the chart X-axis
	private var chartStartDate: Date {
		let startOfDay = calendar.startOfDay(for: Date())
		return calendar.date(byAdding: .hour, value: chartStartHour, to: startOfDay)!
	}

	private var chartBackgroundColor: Color {
		widgetRenderingMode == .accented ? .clear : Color("WidgetBackground")
	}

	private var labelFont: Font {
		widgetFamily == .systemLarge || widgetFamily == .systemExtraLarge ? .caption : .caption2
	}

	/// Renders an hourly tick mark with appropriate styling
	/// Returns nothing if the hour is too close to Data Time (within 20 minutes)
	@AxisMarkBuilder
	private func hourlyTickMark(
		for date: Date, startOfDay: Date, endOfDay: Date, collisions: (hidesStart: Bool, hidesEnd: Bool),
		dataTime: Date, dataTimeVisible: Bool
	) -> some AxisMark {
		let minutesFromDataTime = abs(date.timeIntervalSince(dataTime)) / 60
		if minutesFromDataTime >= 20 {
			let isStartOfDay = abs(date.timeIntervalSince(startOfDay)) < 60
			let isEndOfDay = abs(date.timeIntervalSince(endOfDay)) < 60
			// Show tick line if: (1) data time hidden, OR (2) data time visible but no collision
			let showTickLine =
				(isStartOfDay && (!dataTimeVisible || !collisions.hidesStart))
				|| (isEndOfDay && (!dataTimeVisible || !collisions.hidesEnd))

			if showTickLine {
				// Visible labeled hours: tick line
				AxisTick(
					centered: true, length: 6,
					stroke: StrokeStyle(lineWidth: lineWidth / 2, lineCap: .round)
				)
				.offset(CGSize(width: 0, height: 8))
			} else {
				// Unlabeled hours or hidden labels: dot
				AxisTick(
					centered: true, length: 0,
					stroke: StrokeStyle(lineWidth: lineWidth / 2, lineCap: .round)
				)
				.offset(CGSize(width: 0, height: 11))
			}
		}
	}

	/// Calculate max value for chart Y-axis
	/// Adds padding for line stroke width so the top of lines aren't clipped
	private func chartMaxValue(chartHeight: CGFloat) -> Double {
		let maxDataValue = max(
			todayHourlyData.last?.calories ?? 0,
			interpolatedAverageAtDataTime?.calories ?? 0,
			projectedData.last?.calories ?? 0,
			moveGoal
		)
		// Add padding for line stroke: convert lineWidth/2 from points to calories
		let caloriesPerPoint = maxDataValue / chartHeight
		let strokePadding = (lineWidth / 2) * caloriesPerPoint
		return maxDataValue + strokePadding
	}

	// MARK: - Computed Data Properties

	/// Filter data to only include hours >= chartStartHour
	/// Preserves end-of-day midnight point (next day's midnight) for projected total
	private func filterByStartHour(_ data: [HourlyEnergyData]) -> [HourlyEnergyData] {
		guard chartStartHour > 0 else { return data }
		return data.filter { dataPoint in
			let hour = calendar.component(.hour, from: dataPoint.hour)

			// Keep if hour >= start hour
			if hour >= chartStartHour {
				return true
			}

			// Special case: keep end-of-day midnight (hour == 0, but date is tomorrow)
			if hour == 0 {
				let startOfToday = calendar.startOfDay(for: Date())
				let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
				return calendar.isDate(dataPoint.hour, inSameDayAs: startOfTomorrow)
			}

			return false
		}
	}

	/// Cleaned average data (removes stale Data Time points from cached data)
	/// Filters out interpolated points that may have been cached by widgets
	private var cleanedAverageData: [HourlyEnergyData] {
		averageHourlyData.filter { data in
			let minute = calendar.component(.minute, from: data.hour)
			return minute == 0
		}
	}

	/// Calculate interpolated average value at data time
	private var interpolatedAverageAtDataTime: HourlyEnergyData? {
		guard let interpolatedCalories = averageHourlyData.interpolatedValue(at: dataTime) else {
			return nil
		}
		return HourlyEnergyData(hour: dataTime, calories: interpolatedCalories)
	}

	/// Average data from start of day up to Data Time (includes interpolated Data Time point)
	private var averageDataBeforeDataTime: [HourlyEnergyData] {
		var data = cleanedAverageData.filter { $0.hour <= startOfCurrentHour }
		if let interpolated = interpolatedAverageAtDataTime {
			data.append(interpolated)
		}
		return filterByStartHour(data)
	}

	/// Average data from Data Time to end of day (includes interpolated Data Time point)
	private var averageDataAfterDataTime: [HourlyEnergyData] {
		var data: [HourlyEnergyData] = []

		// Start with interpolated Data Time point
		if let interpolated = interpolatedAverageAtDataTime {
			data.append(interpolated)
		}

		// Add all future hours
		guard let nextHourStart = calendar.date(byAdding: .hour, value: 1, to: startOfCurrentHour) else {
			return data  // Shouldn't happen, but gracefully return partial data
		}
		data.append(contentsOf: cleanedAverageData.filter { $0.hour >= nextHourStart })

		return filterByStartHour(data)
	}

	/// Projected data for rest of day (offset average to start from Today's current value)
	private var projectedData: [HourlyEnergyData] {
		// offset = Today at data time - Average at data time
		let todayAtDataTime = todayHourlyData.last?.calories ?? 0
		let averageAtDataTime = interpolatedAverageAtDataTime?.calories ?? 0
		let offset = todayAtDataTime - averageAtDataTime

		return averageDataAfterDataTime.map { data in
			HourlyEnergyData(hour: data.hour, calories: offset + data.calories)
		}
	}

	/// Today's data filtered by start hour
	private var filteredTodayData: [HourlyEnergyData] {
		filterByStartHour(todayHourlyData)
	}

	@ChartContentBuilder
	private var averageLine: some ChartContent {
		// BEFORE Data Time: darker gray line (past data → Data Time)
		ForEach(averageDataBeforeDataTime) { data in
			LineMark(
				x: .value("Hour", data.hour),
				y: .value("Calories", data.calories),
				series: .value("Series", "AverageUpToNow")
			)
			.foregroundStyle(Color("AverageColor"))
			.lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
			.opacity(widgetRenderingMode.secondaryOpacity)
		}
	}

	@ChartContentBuilder
	private var todayLine: some ChartContent {
		// Single continuous line including current hour progress
		ForEach(filteredTodayData) { data in
			LineMark(
				x: .value("Hour", data.hour), y: .value("Calories", data.calories),
				series: .value("Series", "Today")
			)
			.foregroundStyle(Color("AccentColor"))
			.lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
			.opacity(widgetRenderingMode.primaryOpacity)
		}
	}

	@ChartContentBuilder
	private var projectedLine: some ChartContent {
		ForEach(projectedData) { data in
			LineMark(
				x: .value("Hour", data.hour),
				y: .value("Calories", data.calories),
				series: .value("Series", "Projected")
			)
			.foregroundStyle(Color("AccentColor"))
			.lineStyle(
				StrokeStyle(
					lineWidth: lineWidth, lineJoin: .round,
					dash: [lineWidth * 2, lineWidth * 0.75], dashPhase: lineWidth)
			)
			.opacity(widgetRenderingMode.primaryOpacity)
		}
	}

	@ChartContentBuilder
	private var averagePoint: some ChartContent {
		// Show average point at Data Time (interpolated value)
		// Only show if data time is within chart bounds
		if let interpolated = interpolatedAverageAtDataTime, dataTime >= chartStartDate {
			PointMark(x: .value("Hour", interpolated.hour), y: .value("Calories", interpolated.calories))
				.foregroundStyle(chartBackgroundColor).symbolSize(256)
			PointMark(x: .value("Hour", interpolated.hour), y: .value("Calories", interpolated.calories))
				.foregroundStyle(Color("AverageColor")).symbolSize(100).opacity(
					widgetRenderingMode.secondaryOpacity)
		}
	}

	@ChartContentBuilder
	private var todayPoint: some ChartContent {
		// Only show if data time is within chart bounds
		if let last = todayHourlyData.last, dataTime >= chartStartDate {
			// Use Data Time for x-position to align with average point and data time line
			PointMark(x: .value("Hour", dataTime), y: .value("Calories", last.calories)).foregroundStyle(
				chartBackgroundColor
			).symbolSize(256)
			PointMark(x: .value("Hour", dataTime), y: .value("Calories", last.calories)).foregroundStyle(
				Color("AccentColor")
			).symbolSize(100).opacity(widgetRenderingMode.primaryOpacity)
		}
	}

	@ChartContentBuilder
	private var goalLine: some ChartContent {
		if moveGoal > 0 {
			RuleMark(y: .value("Goal", moveGoal))
				.foregroundStyle(Color("GoalLineColor").opacity(0.5))
				.lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
				.annotation(
					position: .bottom,
					alignment: .leading,
					spacing: 2
				) {
					Text("\(Int(moveGoal)) cal")
						.font(labelFont)
						.foregroundStyle(Color("GoalLineColor"))
						.offset(x: -2)
						.padding(1)
						.background(chartBackgroundColor.opacity(0.5))
						.cornerRadius(4)

				}
		}
	}

	@ChartContentBuilder
	private var dataTimeLine: some ChartContent {
		// Only show if data time is within chart bounds
		if dataTime >= chartStartDate {
			RuleMark(x: .value("Now", dataTime))
				.foregroundStyle(Color("NowLineColor"))
				.lineStyle(StrokeStyle(lineWidth: lineWidth / 2, lineCap: .round, lineJoin: .round))
				.opacity(widgetRenderingMode.tertiaryOpacity)
		}
	}

	var body: some View {
		GeometryReader { geometry in
			let chartWidth = geometry.size.width
			let chartHeight = geometry.size.height
			let maxValue = chartMaxValue(chartHeight: chartHeight)

			VStack(spacing: 0) {
				// Chart with flexible height
				let startOfDay = calendar.startOfDay(for: Date())
				let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

				Chart {
					dataTimeLine
					goalLine
					averageLine
					todayLine
					projectedLine
					averagePoint
					todayPoint
				}
				.frame(maxHeight: .infinity)
				.chartXScale(domain: chartStartDate...endOfDay)
				.chartYScale(domain: 0...maxValue)
				.chartXAxis {
					let dataTimeVisible = dataTime >= chartStartDate
					let collisions = calculateLabelCollisions(
						chartWidth: chartWidth, dataTime: dataTime,
						chartStartHour: chartStartHour)

					// Hourly tick marks
					AxisMarks(values: .stride(by: .hour, count: 1)) { value in
						if let date = value.as(Date.self) {
							hourlyTickMark(
								for: date, startOfDay: chartStartDate,
								endOfDay: endOfDay,
								collisions: collisions, dataTime: dataTime,
								dataTimeVisible: dataTimeVisible)
						}
					}

					// Data Time tick mark (matches labeled hour styling)
					// Only show if data time is within chart bounds
					if dataTimeVisible {
						AxisMarks(values: [dataTime]) { _ in
							AxisTick(
								centered: true, length: 6,
								stroke: StrokeStyle(
									lineWidth: lineWidth / 2, lineCap: .round)
							)
							.offset(CGSize(width: 0, height: 8))
						}
					}
				}
				.chartYAxis {
					AxisMarks {}
				}

				// X-axis labels below chart (fixed height)
				ChartXAxisLabels(
					chartWidth: chartWidth, dataTime: dataTime, labelFont: labelFont,
					chartStartHour: chartStartHour
				)
				.padding(.top, 8)
			}
		}
	}
}

// MARK: - WidgetRenderingMode Extension

extension WidgetRenderingMode {
	/// Primary content opacity (100% in all modes)
	var primaryOpacity: Double {
		self == .accented ? 1.0 : 1.0
	}

	/// Secondary content opacity (75% in accented/glass mode)
	var secondaryOpacity: Double {
		self == .accented ? 0.5 : 1.0
	}

	/// Tertiary content opacity (50% in accented/glass mode)
	var tertiaryOpacity: Double {
		self == .accented ? 0.25 : 1.0
	}
}
