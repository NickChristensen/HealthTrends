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
		widgetRenderingMode == .accented ? .clear : Color("WidgetBackground")
	}

	var body: some View {
		if widgetFamily == .systemMedium {
			// Medium widget: horizontal layout
            let spacing = 16.0
			HStack(spacing: spacing) {
				// Header
                VStack {
					HeaderStatistic(
						label: "Today", statistic: todayTotal, color: Color("AccentColor")
					)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.primaryOpacity)

					HeaderStatistic(
						label: "Average", statistic: averageAtCurrentHour,
						color: Color("AverageStatisticColor")
					)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.secondaryOpacity)

					HeaderStatistic(
						label: "Total", statistic: projectedTotal,
						color: Color("TotalStatisticTextColor"),
						circleColor: Color("TotalStatisticCircleColor")
					)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.tertiaryOpacity)
				}
                .fixedSize(horizontal: true, vertical: false)

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					projectedTotal: projectedTotal,
					dataTime: dataTime
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
				.fixedSize(horizontal: false, vertical: true)

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					projectedTotal: projectedTotal,
					dataTime: dataTime
				)
				.frame(maxHeight: .infinity)
			}
			.padding(spacing)
            .background(chartBackgroundColor)
		}
	}
}
