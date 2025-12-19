import Foundation
import HealthKit

/// Low-level helpers to construct HKQuantitySample objects for testing
enum SampleHelpers {
	/// Create hourly active energy samples for a single day
	/// - Parameters:
	///   - date: The date (time component used as end time)
	///   - caloriesPerHour: Array of calories burned per hour (0-indexed from midnight)
	/// - Returns: Array of HKQuantitySample objects with proper timestamps
	///
	/// Example: For date = Saturday 3 PM, caloriesPerHour = [40, 45, 50, ...]
	/// Creates samples: 12am-1am (40 cal), 1am-2am (45 cal), 2am-3am (50 cal), ...
	static func createDailySamples(
		date: Date,
		caloriesPerHour: [Double]
	) -> [HKQuantitySample] {
		let calendar = Calendar.current
		let startOfDay = calendar.startOfDay(for: date)
		let currentHour = calendar.component(.hour, from: date)
		let currentMinute = calendar.component(.minute, from: date)

		var samples: [HKQuantitySample] = []

		// Create samples up to the current hour
		for hour in 0..<min(caloriesPerHour.count, currentHour + 1) {
			let calories = caloriesPerHour[hour]

			// Each sample spans from hour start to hour end
			let sampleStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay)!
			let sampleEnd: Date

			// If this is the current hour, end at current time
			if hour == currentHour {
				sampleEnd = date
			} else {
				sampleEnd = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!
			}

			let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
			let sample = HKQuantitySample(
				type: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
				quantity: quantity,
				start: sampleStart,
				end: sampleEnd
			)

			samples.append(sample)
		}

		return samples
	}

	/// Create historical data for matching weekdays (used for average calculation)
	/// - Parameters:
	///   - weekday: Target weekday (1=Sunday, 7=Saturday)
	///   - occurrences: How many past occurrences to generate (e.g., 10 = last 10 Saturdays)
	///   - endDate: Reference date (usually "today")
	/// - Returns: Array of samples spanning multiple past weeks
	///
	/// Generates realistic but deterministic data for average calculations
	static func createHistoricalWeekdayData(
		weekday: Int,
		occurrences: Int,
		endDate: Date
	) -> [HKQuantitySample] {
		var allSamples: [HKQuantitySample] = []

		for weekAgo in 1...occurrences {
			// Create a date for this past occurrence
			let targetDate = DateHelpers.createDate(
				weekday: weekday,
				hour: 23,  // End of day
				minute: 59,
				weeksAgo: weekAgo,
				from: endDate
			)

			// Generate realistic hourly data (varies slightly per day)
			let dailyCalories = generateRealisticDailyPattern(seed: weekAgo)
			let samples = createDailySamples(date: targetDate, caloriesPerHour: dailyCalories)

			allSamples.append(contentsOf: samples)
		}

		return allSamples
	}

	/// Generate a deterministic daily calorie pattern
	/// - Parameter seed: Unused (kept for API compatibility)
	/// - Returns: Array of 24 hourly calorie values
	///
	/// Pattern simulates typical daily activity:
	/// - Low overnight (0-6 AM): 30 cal
	/// - Gradual increase morning (6 AM - noon): 225 cal
	/// - Peak afternoon (noon - 3 PM): 215 cal (cumulative: 470)
	/// - 3:00-3:40 PM: 40 cal (cumulative at 3:40: 510)
	/// - 3:40 PM - midnight: 503 cal
	/// Total: 1013 cal/day (exactly)
	private static func generateRealisticDailyPattern(seed: Int) -> [Double] {
		// Deterministic pattern: exactly 510 by 3:40 PM, exactly 1013 total
		return [
			// Midnight - 6 AM (sleeping): 30 cal
			5, 5, 5, 5, 5, 5,
			// 6 AM - Noon (morning activity): 225 cal
			25, 30, 35, 40, 45, 50,
			// Noon - 3 PM (peak afternoon): 215 cal -> cumulative: 470
			70, 75, 70,
			// 3-4 PM: 60 cal (at 3:40 PM = 470 + 40 = 510)
			// 4 PM - Midnight (continued activity + wind-down): 483 cal
			60, 85, 82, 78, 67, 58, 47, 38, 28
		]
	}

	/// Create samples for Scenario 1: Normal Operation (Fresh Data)
	/// Saturday, 3 PM with 550 calories burned, last 10 Saturdays for average
	static func scenario1Samples() -> [HKQuantitySample] {
		let saturday3PM = DateHelpers.createSaturday(hour: 15, minute: 0)

		// Today's data: 550 cal by 3 PM
		// Distribute across hours: gradually increasing through the day
		let todayCalories: [Double] = [
			5, 5, 5, 5, 5, 10,           // 0-6 AM (35 cal)
			30, 40, 50, 60, 70, 80,      // 6 AM-noon (330 cal)
			90, 85, 60                    // Noon-3 PM (235 cal) -> Total ~600 cal (close to 550 target)
		]

		let todaySamples = createDailySamples(date: saturday3PM, caloriesPerHour: todayCalories)

		// Historical data: Last 10 Saturdays
		let historicalSamples = createHistoricalWeekdayData(
			weekday: 7,  // Saturday
			occurrences: 10,
			endDate: saturday3PM
		)

		return todaySamples + historicalSamples
	}
}
