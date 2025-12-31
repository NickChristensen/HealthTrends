import HealthTrendsShared
import SwiftUI
import WidgetKit

/// Reusable view combining statistics header and energy chart
/// Can be used in both main app and widgets
/// Uses flexible height layout to adapt to container size
struct EnergyTrendView: View {
	let todayTotal: Double
	let averageAtCurrentHour: Double
	let todayHourlyData: [HourlyEnergyData]
	let averageHourlyData: [HourlyEnergyData]
	let moveGoal: Double
	let averageTotal: Double
	let dataTime: Date  // Timestamp of most recent HealthKit data sample
	let chartStartHour: Int  // Hour to start the chart X-axis (0-12)
	let accentColor: Color  // Dynamic accent color from widget configuration

	@Environment(\.widgetRenderingMode) var widgetRenderingMode
	@Environment(\.widgetFamily) var widgetFamily

	private var chartBackgroundColor: Color {
		widgetRenderingMode == .accented ? .clear : Color("WidgetBackground")
	}

	/// User's projected end-of-day total based on current pace
	private var projectedTotal: Double {
		// todayTotal + remaining average calories for the day
		todayTotal + (averageTotal - averageAtCurrentHour)
	}

	private var todayStatistic: some View {
		HeaderStatistic { circle in
			circle.fill(accentColor)
		} label: {
			Text("Today").foregroundStyle(accentColor)
		} statistic: { format in
			format(todayTotal)
		}
		.opacity(widgetRenderingMode.primaryOpacity)
	}

	private var averageStatistic: some View {
		HeaderStatistic { circle in
			circle.fill(Color("AverageColor"))
		} label: {
			Text("Average").foregroundStyle(Color("AverageColor"))
		} statistic: { format in
			format(averageAtCurrentHour)
		}
		.opacity(widgetRenderingMode.tertiaryOpacity)
	}

	private var projectedStatistic: some View {
		HeaderStatistic { circle in
			circle.strokeBorder(
				accentColor, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
		} label: {
			Text("Projected").foregroundStyle(accentColor)
		} statistic: { format in
			format(projectedTotal)
		}
		.opacity(widgetRenderingMode.secondaryOpacity)
	}

	var body: some View {
		if widgetFamily == .systemMedium {
			// Medium widget: horizontal layout
			let spacing = 16.0
			HStack(spacing: spacing * 1.5) {
				// Header
				VStack {
					todayStatistic
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					averageStatistic
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					projectedStatistic
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
				}
				.fixedSize(horizontal: true, vertical: false)

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					dataTime: dataTime,
					chartStartHour: chartStartHour,
					accentColor: accentColor
				)
				.frame(maxWidth: .infinity)
			}
			.padding(spacing)
			.background(chartBackgroundColor)
		} else {
			// Large/ExtraLarge widgets: vertical layout (stats on top, chart below)
			let spacing = 16.0
			VStack(spacing: spacing) {
				// Header
				HStack {
					todayStatistic
						.frame(maxWidth: .infinity, alignment: .leading)
					averageStatistic
						.frame(maxWidth: .infinity, alignment: .center)
					projectedStatistic
						.frame(maxWidth: .infinity, alignment: .trailing)
				}
				.fixedSize(horizontal: false, vertical: true)

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					dataTime: dataTime,
					chartStartHour: chartStartHour,
					accentColor: accentColor
				)
				.frame(maxHeight: .infinity)
			}
			.padding(spacing)
			.background(chartBackgroundColor)
		}
	}
}
