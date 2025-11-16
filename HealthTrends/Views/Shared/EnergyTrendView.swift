import SwiftUI

private let activeEnergyColor: Color = Color(red: 254/255, green: 73/255, blue: 1/255)

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

    var body: some View {
        GeometryReader { geometry in
            let spacing = geometry.size.height > 300 ? 16.0 : 8.0

            VStack(spacing: spacing) {
                // Header with statistics (fixed height)
                HStack(spacing: 0) {
                    HeaderStatistic(label: "Today", statistic: todayTotal, color: activeEnergyColor)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HeaderStatistic(label: "Average", statistic: averageAtCurrentHour, color: Color(.systemGray))
                        .frame(maxWidth: .infinity, alignment: .center)

                    HeaderStatistic(label: "Total", statistic: projectedTotal, color: Color(.systemGray2), circleColor: Color(.systemGray4))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Energy Trend Chart (flexible height - takes remaining space)
                EnergyChartView(
                    todayHourlyData: todayHourlyData,
                    averageHourlyData: averageHourlyData,
                    moveGoal: moveGoal,
                    projectedTotal: projectedTotal
                )
                .frame(maxHeight: .infinity)
            }
        }
    }
}
