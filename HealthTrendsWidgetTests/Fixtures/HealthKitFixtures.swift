import Foundation
import HealthKit

/// Factory methods that create realistic HealthKit data for each PRD scenario
/// These fixtures provide complete test data including today's samples, historical samples, and move goals
enum HealthKitFixtures {
	// MARK: - Scenario 1: Normal Operation (Fresh Data)

	/// Scenario 1: Normal Operation (Fresh Data)
	/// Saturday, 3 PM with fresh HealthKit data
	///
	/// Expected outcomes per PRD:
	/// - Today: 550 cal
	/// - Average: 510 cal (average of last 10 Saturdays by 3 PM)
	/// - Total: 1,013 cal (average of full-day totals from last 10 Saturdays)
	/// - Move Goal: 900 cal
	static func scenario1_normalOperation() -> (samples: [HKQuantitySample], goal: Double, currentTime: Date) {
		let saturday3PM = DateHelpers.createSaturday(hour: 15, minute: 0)

		// Today's samples: Need to sum to ~550 cal by 3 PM
		let todayCalories: [Double] = [
			// 0-6 AM (sleeping): 30 cal
			5, 5, 5, 5, 5, 5,
			// 6 AM-noon (morning): 240 cal
			30, 35, 40, 45, 45, 45,
			// Noon-3 PM (afternoon): 280 cal -> Total ~550 cal
			90, 95, 95
		]

		let todaySamples = SampleHelpers.createDailySamples(
			date: saturday3PM,
			caloriesPerHour: todayCalories
		)

		// Last 10 Saturdays historical data
		// These should average to:
		// - ~510 cal by 3 PM (average at current hour)
		// - ~1013 cal for full day (projected total)
		let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
			weekday: 7,  // Saturday
			occurrences: 10,
			endDate: saturday3PM
		)

		return (todaySamples + historicalSamples, 900.0, saturday3PM)
	}

	// MARK: - Scenario 2: Delayed Sync

	/// Scenario 2: Delayed Sync
	/// Saturday, 3 PM but data only current to 2:15 PM (45 minutes stale)
	///
	/// Expected outcomes per PRD:
	/// - Data Time: 2:15 PM (marker shows staleness)
	/// - Today: 480 cal (stops at 2:15 PM)
	/// - Average continues projecting forward from Data Time
	static func scenario2_delayedSync() -> (samples: [HKQuantitySample], goal: Double, currentTime: Date, dataTime: Date) {
		let saturday3PM = DateHelpers.createSaturday(hour: 15, minute: 0)  // Current time
		let saturday215PM = DateHelpers.createSaturday(hour: 14, minute: 15)  // Data Time (45 min stale)

		// Today's samples: Only up to 2:15 PM, sum to ~480 cal
		let todayCalories: [Double] = [
			// 0-6 AM: 35 cal
			5, 5, 5, 5, 5, 10,
			// 6 AM-noon: 270 cal
			30, 40, 50, 60, 70, 80,
			// Noon-2 PM: 175 cal
			90, 85,
			// 2-2:15 PM (partial hour): ~20 cal
			// Note: SampleHelpers will end this sample at 2:15 PM (dataTime)
		]

		// Create samples ending at 2:15 PM (not 3 PM)
		let todaySamples = SampleHelpers.createDailySamples(
			date: saturday215PM,  // Data ends at 2:15 PM
			caloriesPerHour: todayCalories
		)

		// Historical data (same as Scenario 1)
		let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
			weekday: 7,
			occurrences: 10,
			endDate: saturday3PM
		)

		return (todaySamples + historicalSamples, 900.0, saturday3PM, saturday215PM)
	}

	// MARK: - Scenario 3: Stale Data (Previous Day)

	/// Scenario 3: Stale Data (Previous Day)
	/// Saturday, 10 AM but last HealthKit data is from Friday 11 PM (11 hours old, different day)
	///
	/// Expected outcomes per PRD:
	/// - No "Today" line shown (data from wrong day)
	/// - Average-only display for Saturday
	/// - Total shows Saturday's projected average
	static func scenario3_staleData() -> (samples: [HKQuantitySample], goal: Double, currentTime: Date, dataTime: Date) {
		let saturday10AM = DateHelpers.createSaturday(hour: 10, minute: 0)  // Current time
		let friday11PM = DateHelpers.createFriday(hour: 23, minute: 0)  // Last data (previous day!)

		// Today's samples: NONE (all data is from Friday)
		// Create Friday's full day of data
		let fridayCalories: [Double] = [
			// Full day pattern
			5, 5, 5, 5, 5, 10,  // 0-6 AM
			30, 40, 50, 60, 70, 80,  // 6 AM-noon
			90, 85, 80, 75, 70, 65,  // Noon-6 PM
			60, 50, 40, 30, 20  // 6 PM-11 PM (11 PM is last sample)
		]

		let fridaySamples = SampleHelpers.createDailySamples(
			date: friday11PM,
			caloriesPerHour: fridayCalories
		)

		// Historical data: Last 10 Saturdays (for average calculation on Saturday)
		let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
			weekday: 7,  // Saturday
			occurrences: 10,
			endDate: saturday10AM
		)

		return (fridaySamples + historicalSamples, 900.0, saturday10AM, friday11PM)
	}

	// MARK: - Scenario 4: No Authorization

	/// Scenario 4: No Authorization
	/// User has added widget but hasn't granted HealthKit permissions
	///
	/// Expected outcomes per PRD:
	/// - No data shown
	/// - Authorization prompt displayed
	/// - "Tap to open app" call-to-action
	static func scenario4_unauthorized() -> (samples: [HKQuantitySample], goal: Double, currentTime: Date) {
		let now = Date()

		// Empty samples (simulates denied/not granted permission)
		return ([], 0.0, now)
	}
}
