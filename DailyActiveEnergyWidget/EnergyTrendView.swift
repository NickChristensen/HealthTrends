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
						color: Color("AverageColor")
					)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
					.opacity(widgetRenderingMode.secondaryOpacity)

                    HeaderStatistic(
                        label: "Projected",
                        statistic: projectedTotal,
                        color: Color("ProjectedColor")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .opacity(widgetRenderingMode.tertiaryOpacity)
				}
                .fixedSize(horizontal: true, vertical: false)

                EnergyChartView(
                    todayHourlyData: todayHourlyData,
                    averageHourlyData: averageHourlyData,
                    moveGoal: moveGoal,
                    dataTime: dataTime,
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
                        color: Color("AverageColor")
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .opacity(widgetRenderingMode.secondaryOpacity)
                    
                    HeaderStatistic(
                        label: "Projected",
                        statistic: projectedTotal,
                        color: Color("ProjectedColor")
                    )
                    .opacity(widgetRenderingMode.tertiaryOpacity)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
				.fixedSize(horizontal: false, vertical: true)

				EnergyChartView(
					todayHourlyData: todayHourlyData,
					averageHourlyData: averageHourlyData,
					moveGoal: moveGoal,
					dataTime: dataTime,
                )
				.frame(maxHeight: .infinity)
			}
			.padding(spacing)
            .background(chartBackgroundColor)
		}
	}
}
