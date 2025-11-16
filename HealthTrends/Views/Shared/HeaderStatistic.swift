import SwiftUI

/// Single statistic display with colored indicator and value
struct HeaderStatistic: View {
    let label: String
    let statistic: Double
    let color: Color
    let circleColor: Color

    init(label: String, statistic: Double, color: Color, circleColor: Color? = nil) {
        self.label = label
        self.statistic = statistic
        self.color = color
        self.circleColor = circleColor ?? color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle()
                    .fill(circleColor)
                    .frame(width: 10, height: 10)
                Text(label)
                    .font(.caption)
                    .fontDesign(.rounded)
                    .foregroundStyle(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Int(statistic), format: .number)
                    .font(.title2)
                    .fontDesign(.rounded)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text("cal")
                    .font(.caption)
                    .fontDesign(.rounded)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }
        }
    }
}
