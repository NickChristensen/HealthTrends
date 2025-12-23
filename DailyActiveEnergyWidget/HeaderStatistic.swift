import SwiftUI

/// Single statistic display with colored indicator and value
struct HeaderStatistic<Indicator: View, Label: View, Statistic: View, Unit: View>: View {
	let indicator: Indicator
	let label: Label
    let statistic: Statistic
    let unit: Unit

	init(
		@ViewBuilder indicator: (Circle) -> Indicator,
		@ViewBuilder label: () -> Label,
		@ViewBuilder statistic: (@escaping (Double) -> Text) -> Statistic,
		@ViewBuilder unit: (Text) -> Unit = { $0 }
	) {
		self.indicator = indicator(Circle())
		self.label = label()
		self.statistic = statistic { value in Text(Int(value), format: .number) }
		self.unit = unit(Text("cal"))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(spacing: 4) {
				indicator
					.frame(width: 10, height: 10)
				label
                    .font(.system(.caption, design: .rounded))
			}
			HStack(alignment: .firstTextBaseline, spacing: 0) {
				statistic
                    .font(.system(.title2, design: .rounded))
					.fontWeight(.bold)
                    .foregroundStyle(Color("StatisticColor"))
                Text(" ").font(.caption2)
				unit
                    .font(.system(.caption, design: .rounded))
					.fontWeight(.bold)
                    .foregroundStyle(Color("StatisticColor"))
			}
		}
	}
}
