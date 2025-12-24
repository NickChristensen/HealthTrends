import Foundation
import HealthKit

/// Factory methods that create realistic HealthKit data for each PRD scenario
/// These fixtures provide complete test data including today's samples, historical samples, and move goals
enum HealthKitFixtures {
	// MARK: - Scenario 1: Normal Operation (Fresh Data)

	/// Scenario 1: Normal Operation (Fresh Data)
	/// Saturday, 3:43 PM with HealthKit data current to 3:40 PM (3 minutes old)
	///
	/// Expected outcomes per PRD:
	/// - Data Time: 3:40 PM (most recent HealthKit sample)
	/// - Today: 550 cal (through 3:40 PM)
	/// - Average: 510 cal (average of last 10 Saturdays by 3:40 PM)
	/// - Total: 1,013 cal (average of full-day totals from last 10 Saturdays)
	/// - Move Goal: 900 cal
	static func scenario1_normalOperation() -> (
		samples: [HKQuantitySample], goal: Double, currentTime: Date, dataTime: Date
	) {
		let saturday343PM = DateHelpers.createSaturday(hour: 15, minute: 43)  // Current time
		let saturday340PM = DateHelpers.createSaturday(hour: 15, minute: 40)  // Data Time

		// Today's samples: Need to sum to ~550 cal by 3:40 PM
		let todayCalories: [Double] = [
			// 0-6 AM (sleeping): 30 cal
			5, 5, 5, 5, 5, 5,
			// 6 AM-noon (morning): 240 cal
			30, 35, 40, 45, 45, 45,
			// Noon-3 PM (afternoon): 220 cal
			75, 75, 70,
			// 3-3:40 PM (partial hour, ~40 min): 60 cal -> Total ~550 cal
			60,
		]

		let todaySamples = SampleHelpers.createDailySamples(
			date: saturday340PM,  // Samples end at 3:40 PM
			caloriesPerHour: todayCalories
		)

		// Last 10 Saturdays historical data
		// These should average to:
		// - ~510 cal by 3:40 PM (average at current hour)
		// - ~1013 cal for full day (projected total)
		let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
			weekday: 7,  // Saturday
			occurrences: 10,
			endDate: saturday343PM
		)

		return (todaySamples + historicalSamples, 900.0, saturday343PM, saturday340PM)
	}

	// MARK: - Scenario 2: Delayed Sync

	/// Scenario 2: Delayed Sync
	/// Saturday, 3:43 PM but data only current to 2:15 PM (88 minutes stale)
	///
	/// Expected outcomes per PRD:
	/// - Data Time: 2:15 PM (marker shows staleness)
	/// - Today: 480 cal (stops at 2:15 PM)
	/// - Average continues projecting forward from Data Time
	static func scenario2_delayedSync() -> (
		samples: [HKQuantitySample], goal: Double, currentTime: Date, dataTime: Date
	) {
		let saturday343PM = DateHelpers.createSaturday(hour: 15, minute: 43)  // Current time
		let saturday215PM = DateHelpers.createSaturday(hour: 14, minute: 15)  // Data Time

		// Today's samples: Only up to 2:15 PM, sum to ~480 cal
		let todayCalories: [Double] = [
			// 0-6 AM: 30 cal
			5, 5, 5, 5, 5, 5,
			// 6 AM-noon: 250 cal
			30, 35, 40, 45, 50, 50,
			// Noon-2 PM: 180 cal
			90, 90,
			// 2-2:15 PM (15 min): 20 cal
			20,
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
			endDate: saturday343PM
		)

		return (todaySamples + historicalSamples, 900.0, saturday343PM, saturday215PM)
	}

	// MARK: - Scenario 3: Stale Data (Previous Day)

	/// Scenario 3: Stale Data (Previous Day)
	/// Saturday, 10:23 AM but last HealthKit data is from Friday 10:47 PM (11 hours 36 min old, different day)
	///
	/// Expected outcomes per PRD:
	/// - No "Today" line shown (data from wrong day)
	/// - Average-only display for Saturday
	/// - Data Time marker at current clock time (10:23 AM) since showing projected average
	static func scenario3_staleData() -> (
		samples: [HKQuantitySample], goal: Double, currentTime: Date, dataTime: Date
	) {
		let saturday1023AM = DateHelpers.createSaturday(hour: 10, minute: 23)  // Current time
		let friday1047PM = DateHelpers.createFriday(hour: 22, minute: 47)  // Last data (previous day!)

		// Today's samples: NONE (all data is from Friday)
		// Create Friday's data through 10:47 PM
		let fridayCalories: [Double] = [
			// Full day pattern through 10:47 PM
			5, 5, 5, 5, 5, 10,  // 0-6 AM
			30, 40, 50, 60, 70, 80,  // 6 AM-noon
			90, 85, 80, 75, 70, 65,  // Noon-6 PM
			60, 50, 40, 30, 20,  // 6 PM-10:47 PM (last sample at 10:47 PM)
		]

		let fridaySamples = SampleHelpers.createDailySamples(
			date: friday1047PM,
			caloriesPerHour: fridayCalories
		)

		// Historical data: Last 10 Saturdays (for average calculation on Saturday)
		let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
			weekday: 7,  // Saturday
			occurrences: 10,
			endDate: saturday1023AM
		)

		return (fridaySamples + historicalSamples, 900.0, saturday1023AM, friday1047PM)
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

	// MARK: - Edge Cases

	/// Edge Case: Sparse Historical Data (Only 2 Saturdays)
	/// Saturday, 3:43 PM with fresh data but only 2 historical Saturdays available (new user or sparse data)
	///
	/// Tests that the widget handles limited historical data gracefully:
	/// - Data Time: 3:40 PM (fresh data)
	/// - Today: 550 cal (same as Scenario 1)
	/// - Average: 510 cal (average of only 2 Saturdays by 3:40 PM)
	/// - Total: 1,013 cal (average of full-day totals from only 2 Saturdays)
	/// - Move Goal: 900 cal
	/// - Widget should handle sparse data gracefully (no NaN, no crashes)
	static func edgeCase_sparseHistoricalData() -> (
		samples: [HKQuantitySample], goal: Double, currentTime: Date, dataTime: Date
	) {
		let saturday343PM = DateHelpers.createSaturday(hour: 15, minute: 43)  // Current time
		let saturday340PM = DateHelpers.createSaturday(hour: 15, minute: 40)  // Data Time

		// Today's samples: Same as Scenario 1 (~550 cal by 3:40 PM)
		let todayCalories: [Double] = [
			// 0-6 AM (sleeping): 30 cal
			5, 5, 5, 5, 5, 5,
			// 6 AM-noon (morning): 240 cal
			30, 35, 40, 45, 45, 45,
			// Noon-3 PM (afternoon): 220 cal
			75, 75, 70,
			// 3-3:40 PM (partial hour, ~40 min): 60 cal -> Total ~550 cal
			60,
		]

		let todaySamples = SampleHelpers.createDailySamples(
			date: saturday340PM,  // Samples end at 3:40 PM
			caloriesPerHour: todayCalories
		)

		// Only 2 Saturdays historical data (sparse data scenario)
		// Should still average to:
		// - ~510 cal by 3:40 PM (average at current hour)
		// - ~1013 cal for full day (projected total)
		let historicalSamples = SampleHelpers.createHistoricalWeekdayData(
			weekday: 7,  // Saturday
			occurrences: 2,  // Only 2 historical Saturdays instead of 10
			endDate: saturday343PM
		)

		return (todaySamples + historicalSamples, 900.0, saturday343PM, saturday340PM)
	}
}
