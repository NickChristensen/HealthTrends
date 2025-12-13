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
	let projectedTotal: Double
	let dataTime: Date  // Timestamp of most recent HealthKit data sample

	@Environment(\.widgetRenderingMode) var widgetRenderingMode
	@Environment(\.widgetFamily) var widgetFamily

	private var chartBackgroundColor: Color {
		widgetRenderingMode == .accented ? .clear : Color("AppBackground")
	}

	var body: some View {
		if widgetFamily == .systemMedium {
			// Medium widget: horizontal layout
			HStack(spacing: 0) {
				// Header
				VStack(spacing: 8) {
					HeaderStatistic(
						label: "Today", statistic: todayTotal, color: Color("AccentColor")
					)
					.frame(maxWidth: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.primaryOpacity)

					HeaderStatistic(
						label: "Average", statistic: averageAtCurrentHour,
						color: Color("AverageStatisticColor")
					)
					.frame(maxWidth: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.secondaryOpacity)

					HeaderStatistic(
						label: "Total", statistic: projectedTotal,
						color: Color("TotalStatisticTextColor"),
						circleColor: Color("TotalStatisticCircleColor")
					)
					.frame(maxWidth: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.tertiaryOpacity)
				}
				.fixedSize(horizontal: true, vertical: true)
				.padding(16)
				//                Removing this in favor of fixed size above. Pick one.
				//                .containerRelativeFrame(.horizontal) { length, _ in
				//                    return length * 0.333
				//                }

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					projectedTotal: projectedTotal,
					dataTime: dataTime
				)
				.padding(16)
				.background(chartBackgroundColor)
				.frame(maxWidth: .infinity)
			}
		} else {
			// Large/ExtraLarge widgets: vertical layout (stats on top, chart below)
			let spacing = 16.0
			VStack(spacing: spacing) {
				// Header
				HStack(spacing: 0) {
					HeaderStatistic(
						label: "Today", statistic: todayTotal, color: Color("AccentColor")
					)
					.frame(maxWidth: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.primaryOpacity)

					HeaderStatistic(
						label: "Average", statistic: averageAtCurrentHour,
						color: Color("AverageStatisticColor")
					)
					.frame(maxWidth: .infinity, alignment: .center)
					.opacity(widgetRenderingMode.secondaryOpacity)

					HeaderStatistic(
						label: "Total", statistic: projectedTotal,
						color: Color("TotalStatisticTextColor"),
						circleColor: Color("TotalStatisticCircleColor")
					)
					.frame(maxWidth: .infinity, alignment: .trailing)
					.opacity(widgetRenderingMode.tertiaryOpacity)
				}
				.padding(.horizontal, 16)
				.fixedSize(horizontal: false, vertical: true)

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					projectedTotal: projectedTotal,
					dataTime: dataTime
				)
				.padding(.horizontal, 16)
				.padding(.top, spacing)
				.background(chartBackgroundColor)
				.frame(maxHeight: .infinity)
			}
			.padding(.vertical, spacing)
		}
	}
}
