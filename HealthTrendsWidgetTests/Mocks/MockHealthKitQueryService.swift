import Foundation
import HealthKit
@testable import HealthTrendsShared

/// Mock implementation of HealthKitQueryService for testing
/// Returns deterministic data without requiring actual HealthKit access
class MockHealthKitQueryService: HealthKitQueryService, @unchecked Sendable {
	private var mockSamples: [HKQuantitySample] = []
	private var mockMoveGoal: Double = 0
	private var mockAuthorized: Bool = true
	private var mockCurrentTime: Date = Date()

	/// Configure samples that will be returned by queries
	func configureSamples(_ samples: [HKQuantitySample]) {
		self.mockSamples = samples
	}

	/// Configure move goal
	func configureMoveGoal(_ goal: Double) {
		self.mockMoveGoal = goal
	}

	/// Configure authorization status
	func configureAuthorization(_ authorized: Bool) {
		self.mockAuthorized = authorized
	}

	/// Configure what "now" should be for testing
	func configureCurrentTime(_ time: Date) {
		self.mockCurrentTime = time
	}

	// MARK: - Override HealthKitQueryService Methods

	override open func checkReadAuthorization() async -> Bool {
		return mockAuthorized
	}

	override open func fetchTodayHourlyTotals() async throws -> (data: [HourlyEnergyData], latestSampleTimestamp: Date?) {
		// Filter samples to only today
		let calendar = Calendar.current
		let now = mockCurrentTime
		let startOfToday = calendar.startOfDay(for: now)

		let todaySamples = mockSamples.filter { sample in
			calendar.isDate(sample.startDate, inSameDayAs: now)
		}

		// Convert samples to hourly cumulative data
		var hourlyData: [HourlyEnergyData] = []
		var cumulative: Double = 0

		// Group by hour and calculate cumulative totals
		let groupedByHour = Dictionary(grouping: todaySamples) { sample -> Int in
			calendar.component(.hour, from: sample.endDate)
		}

		for hour in 0...23 {
			if let samplesInHour = groupedByHour[hour] {
				let hourTotal = samplesInHour.reduce(0.0) { sum, sample in
					sum + sample.quantity.doubleValue(for: HKUnit.kilocalorie())
				}
				cumulative += hourTotal

				// Use end of hour as timestamp
				if let hourEnd = samplesInHour.map({ $0.endDate }).max() {
					hourlyData.append(HourlyEnergyData(hour: hourEnd, calories: cumulative))
				}
			}
		}

		// Sort by time
		hourlyData.sort { $0.hour < $1.hour }

		// Find latest sample timestamp
		let latestTimestamp = todaySamples.map { $0.endDate }.max()

		return (hourlyData, latestTimestamp)
	}

	override open func fetchMoveGoal() async throws -> Double {
		return mockMoveGoal
	}

	override open func fetchAverageData(for weekday: Int? = nil) async throws -> (total: Double, hourlyData: [HourlyEnergyData]) {
		// Get matching weekday from historical data
		let calendar = Calendar.current
		let now = mockCurrentTime
		let targetWeekday = weekday ?? calendar.component(.weekday, from: now)

		// Filter to only matching weekday samples from past weeks
		let matchingWeekdaySamples = mockSamples.filter { sample in
			let sampleWeekday = calendar.component(.weekday, from: sample.startDate)
			return sampleWeekday == targetWeekday && !calendar.isDate(sample.startDate, inSameDayAs: now)
		}

		// Group samples by day
		let samplesByDay = Dictionary(grouping: matchingWeekdaySamples) { sample in
			calendar.startOfDay(for: sample.startDate)
		}

		// Calculate average daily total (projectedTotal)
		let dailyTotals = samplesByDay.values.map { daySamples in
			daySamples.reduce(0.0) { sum, sample in
				sum + sample.quantity.doubleValue(for: HKUnit.kilocalorie())
			}
		}

		let projectedTotal = dailyTotals.isEmpty ? 0 : dailyTotals.reduce(0, +) / Double(dailyTotals.count)

		// Calculate average cumulative hourly pattern
		var hourlyPatterns: [[Double]] = Array(repeating: [], count: 24)

		for (dayStart, daySamples) in samplesByDay {
			var cumulativeForDay: Double = 0
			let sortedSamples = daySamples.sorted { $0.endDate < $1.endDate }

			for hour in 0...23 {
				let hourSamples = sortedSamples.filter {
					calendar.component(.hour, from: $0.endDate) <= hour
				}
				cumulativeForDay = hourSamples.reduce(0.0) { sum, sample in
					sum + sample.quantity.doubleValue(for: HKUnit.kilocalorie())
				}
				hourlyPatterns[hour].append(cumulativeForDay)
			}
		}

		// Average each hour's cumulative values
		var hourlyData: [HourlyEnergyData] = []
		let startOfDay = calendar.startOfDay(for: now)

		for hour in 0...23 {
			let values = hourlyPatterns[hour]
			let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

			if let hourTimestamp = calendar.date(byAdding: .hour, value: hour, to: startOfDay) {
				hourlyData.append(HourlyEnergyData(hour: hourTimestamp, calories: average))
			}
		}

		return (projectedTotal, hourlyData)
	}
}
