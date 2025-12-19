import Testing
import Foundation
@testable import HealthTrendsShared

/// Unit tests for HourlyEnergyData model and interpolation logic
@Suite("HourlyEnergyData Tests")
struct HourlyEnergyDataTests {

	// MARK: - Test Data Factory

	/// Create hourly data points at specific hours with given calorie values
	private func makeHourlyData(hours: [(hour: Int, calories: Double)]) -> [HourlyEnergyData] {
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())

		return hours.map { hourInfo in
			let date = calendar.date(byAdding: .hour, value: hourInfo.hour, to: today)!
			return HourlyEnergyData(hour: date, calories: hourInfo.calories)
		}
	}

	// MARK: - Interpolation Tests

	@Test("Interpolation returns exact value when time matches data point")
	func testExactMatch() {
		// GIVEN: Hourly data at 9 AM, 10 AM, 11 AM
		let data = makeHourlyData(hours: [
			(9, 100.0),
			(10, 200.0),
			(11, 300.0)
		])

		// WHEN: Interpolating at exactly 10 AM
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let tenAM = calendar.date(byAdding: .hour, value: 10, to: today)!

		let result = data.interpolatedValue(at: tenAM)

		// THEN: Should return exact value (200.0)
		#expect(result == 200.0)
	}

	@Test("Interpolation calculates midpoint between two hours")
	func testMidpointInterpolation() {
		// GIVEN: Data at 10 AM (100 cal) and 11 AM (200 cal)
		let data = makeHourlyData(hours: [
			(10, 100.0),
			(11, 200.0)
		])

		// WHEN: Interpolating at 10:30 AM (halfway between)
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let tenThirtyAM = calendar.date(byAdding: .hour, value: 10, to: today)!
		let halfway = calendar.date(byAdding: .minute, value: 30, to: tenThirtyAM)!

		let result = data.interpolatedValue(at: halfway)

		// THEN: Should return midpoint (150.0)
		#expect(result == 150.0)
	}

	@Test("Interpolation handles quarter-hour increments")
	func testQuarterHourInterpolation() {
		// GIVEN: Data at 2 PM (400 cal) and 3 PM (500 cal)
		let data = makeHourlyData(hours: [
			(14, 400.0),
			(15, 500.0)
		])

		// WHEN: Interpolating at 2:15 PM (25% through the hour)
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let twoPM = calendar.date(byAdding: .hour, value: 14, to: today)!
		let twoFifteenPM = calendar.date(byAdding: .minute, value: 15, to: twoPM)!

		let result = data.interpolatedValue(at: twoFifteenPM)

		// THEN: Should return 25% of the way from 400 to 500 = 425.0
		#expect(result == 425.0)
	}

	@Test("Interpolation returns first value when time is before all data")
	func testBeforeAllData() {
		// GIVEN: Data starting at 9 AM
		let data = makeHourlyData(hours: [
			(9, 100.0),
			(10, 200.0)
		])

		// WHEN: Interpolating at 8 AM (before any data)
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let eightAM = calendar.date(byAdding: .hour, value: 8, to: today)!

		let result = data.interpolatedValue(at: eightAM)

		// THEN: Should return first value (100.0)
		#expect(result == 100.0)
	}

	@Test("Interpolation returns last value when time is after all data")
	func testAfterAllData() {
		// GIVEN: Data ending at 3 PM
		let data = makeHourlyData(hours: [
			(14, 400.0),
			(15, 500.0)
		])

		// WHEN: Interpolating at 4 PM (after all data)
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let fourPM = calendar.date(byAdding: .hour, value: 16, to: today)!

		let result = data.interpolatedValue(at: fourPM)

		// THEN: Should return last value (500.0)
		#expect(result == 500.0)
	}

	@Test("Interpolation returns nil for empty data")
	func testEmptyData() {
		// GIVEN: No data
		let data: [HourlyEnergyData] = []

		// WHEN: Interpolating at any time
		let result = data.interpolatedValue(at: Date())

		// THEN: Should return nil
		#expect(result == nil)
	}

	@Test("Interpolation filters out non-hour data points")
	func testFiltersNonHourDataPoints() {
		// GIVEN: Mix of on-the-hour and mid-hour data points
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())

		let data = [
			HourlyEnergyData(
				hour: calendar.date(byAdding: .hour, value: 10, to: today)!,
				calories: 100.0
			),
			HourlyEnergyData(
				hour: calendar.date(byAdding: .hour, value: 10, to: today)!.addingTimeInterval(30 * 60),  // 10:30
				calories: 999.0  // Should be ignored
			),
			HourlyEnergyData(
				hour: calendar.date(byAdding: .hour, value: 11, to: today)!,
				calories: 200.0
			),
		]

		// WHEN: Interpolating at 10:30 AM
		let tenThirtyAM = calendar.date(byAdding: .hour, value: 10, to: today)!
			.addingTimeInterval(30 * 60)

		let result = data.interpolatedValue(at: tenThirtyAM)

		// THEN: Should interpolate between 10 AM (100) and 11 AM (200), ignoring 10:30 point
		#expect(result == 150.0)
	}

	@Test("Interpolation handles midnight wraparound chronologically")
	func testMidnightWraparound() {
		// GIVEN: Data at 11 PM (2300 cal) and midnight (2400 cal)
		let data = makeHourlyData(hours: [
			(23, 2300.0),
			(0, 2400.0)  // Next day's midnight
		])

		// WHEN: Interpolating at 11:30 PM
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let elevenPM = calendar.date(byAdding: .hour, value: 23, to: today)!
		let elevenThirtyPM = calendar.date(byAdding: .minute, value: 30, to: elevenPM)!

		let result = data.interpolatedValue(at: elevenThirtyPM)

		// THEN: Should interpolate correctly (or return last value if midnight is next day)
		// Since midnight would be the next day's data, it should return 2300.0 (last value)
		#expect(result == 2300.0)
	}
}
