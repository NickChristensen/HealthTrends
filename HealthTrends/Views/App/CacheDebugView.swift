import HealthTrendsShared
import SwiftUI

/// Toggleable timestamp display that shows relative time by default and absolute time on tap
struct ToggleableTimestamp: View {
	let date: Date
	@State private var showAbsolute = false

	var body: some View {
		Button(action: {
			showAbsolute.toggle()
		}) {
			Text(showAbsolute ? formatAbsolute(date) : formatRelative(date))
				.font(.caption)
				.foregroundStyle(.primary)
		}
		.buttonStyle(.plain)
	}

	private func formatRelative(_ date: Date) -> String {
		let formatter = RelativeDateTimeFormatter()
		formatter.unitsStyle = .abbreviated
		return formatter.localizedString(for: date, relativeTo: Date())
	}

	private func formatAbsolute(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .short
		formatter.timeStyle = .medium
		return formatter.string(from: date)
	}
}

/// Displays cache state for debugging
struct CacheDebugView: View {
	@State private var todayCache: TodayEnergyCache?
	@State private var weekdayCache: WeekdayAverageCache?

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			// Today Data Cache Section
			VStack(alignment: .leading, spacing: 8) {
				Text("Today Data Cache")
					.font(.headline)

				if let cache = todayCache {
					Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
						GridRow {
							Text("Latest Sample:")
								.foregroundStyle(.secondary)
								.font(.caption)
							if let timestamp = cache.latestSampleTimestamp {
								ToggleableTimestamp(date: timestamp)
							} else {
								Text("No samples")
									.foregroundStyle(.tertiary)
									.font(.caption)
							}
						}
					}
				} else {
					Text("No cache found")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Divider()

			// Average Data Cache Section
			VStack(alignment: .leading, spacing: 8) {
				Text("Average Data Cache")
					.font(.headline)

				if let cache = weekdayCache {
					Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
						GridRow {
							Text("Weekday")
								.font(.caption)
								.foregroundStyle(.secondary)
							Text("Last Update")
								.font(.caption)
								.foregroundStyle(.secondary)
							Text("Projected Total")
								.font(.caption)
								.foregroundStyle(.secondary)
						}

						ForEach(Weekday.allCases, id: \.rawValue) { weekday in
							if let weekdayData = cache.cache(for: weekday) {
								GridRow {
									Text(weekdayName(for: weekday))
										.font(.caption)
									ToggleableTimestamp(date: weekdayData.cachedAt)
									Text(formatCalories(weekdayData.projectedTotal))
										.font(.caption)
								}
							} else {
								GridRow {
									Text(weekdayName(for: weekday))
										.font(.caption)
										.foregroundStyle(.secondary)
									Text("—")
										.font(.caption)
										.foregroundStyle(.tertiary)
									Text("—")
										.font(.caption)
										.foregroundStyle(.tertiary)
								}
							}
						}
					}
				} else {
					Text("No cache found")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.onAppear {
			loadCacheData()
		}
	}

	private func loadCacheData() {
		// Load today's data cache
		todayCache = try? TodayEnergyCacheManager.shared.readEnergyData()

		// Load weekday average cache
		let cacheManager = AverageDataCacheManager()
		weekdayCache = cacheManager.loadContainer()
	}

	private func formatCalories(_ calories: Double) -> String {
		String(format: "%.0f kcal", calories)
	}

	private func weekdayName(for weekday: Weekday) -> String {
		switch weekday {
		case .sunday: return "Sun"
		case .monday: return "Mon"
		case .tuesday: return "Tue"
		case .wednesday: return "Wed"
		case .thursday: return "Thu"
		case .friday: return "Fri"
		case .saturday: return "Sat"
		}
	}
}
