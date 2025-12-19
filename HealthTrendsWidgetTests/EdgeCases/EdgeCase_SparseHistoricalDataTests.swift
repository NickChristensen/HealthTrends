import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Edge case tests for sparse historical data (only 2 Saturdays available)
///
/// Tests that the widget handles limited historical data gracefully when:
/// - User just installed the app (only 1-2 weeks of data)
/// - Historical data is sparse (gaps due to device not worn)
/// - Only 2 historical Saturdays available instead of 10
@Suite("Edge Case: Sparse Historical Data (2 Saturdays)")
struct SparseHistoricalDataTests {

	@Test("Widget handles sparse historical data without crashing or NaN")
	@MainActor
	func testSparseHistoricalData() async throws {
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Mock HealthKit with only 2 historical Saturdays
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.edgeCase_sparseHistoricalData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)
		let config = EnergyWidgetConfigurationIntent()

		// WHEN: Timeline provider generates entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: config)

		// THEN: Entry should be valid with no NaN or crashes
		#expect(entry.isAuthorized == true)

		// Validate Today total is a valid number
		#expect(!entry.todayTotal.isNaN)
		#expect(!entry.todayTotal.isInfinite)
		#expect(entry.todayTotal > 0)

		// Validate Average at current hour is a valid number
		#expect(!entry.averageAtCurrentHour.isNaN)
		#expect(!entry.averageAtCurrentHour.isInfinite)
		#expect(entry.averageAtCurrentHour > 0)

		// Validate Projected Total is a valid number
		#expect(!entry.projectedTotal.isNaN)
		#expect(!entry.projectedTotal.isInfinite)
		#expect(entry.projectedTotal > 0)

		// Validate data arrays are populated
		#expect(entry.todayHourlyData.count >= 3)
		#expect(entry.averageHourlyData.count > 0)
	}

	@Test("Sparse historical data produces same values as full dataset")
	@MainActor
	func testSparseDataMatchesExpectedValues() async throws {
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Mock HealthKit with only 2 historical Saturdays
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.edgeCase_sparseHistoricalData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Values should match expected (same pattern used, so same averages)
		// Today total should be ~550 cal (exact same as Scenario 1)
		#expect(entry.todayTotal == 550.0)

		// Average at 3:40 PM should be ~510 cal (same deterministic pattern)
		#expect(entry.averageAtCurrentHour == 510.0)

		// Projected total should be ~1013 cal (same deterministic pattern)
		#expect(entry.projectedTotal == 1013.0)

		// Move Goal
		#expect(entry.moveGoal == 900.0)
	}

	@Test("Average data structure is valid with sparse historical data")
	@MainActor
	func testAverageDataStructure() async throws {
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Sparse historical data setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.edgeCase_sparseHistoricalData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Average data should be cumulative and increasing
		let averageData = entry.averageHourlyData

		#expect(averageData.count > 0)

		// Validate all values are valid numbers (no NaN)
		for point in averageData {
			#expect(!point.calories.isNaN)
			#expect(!point.calories.isInfinite)
			#expect(point.calories >= 0)
		}

		// Validate cumulative property: each value should be >= previous
		for i in 1..<averageData.count {
			let previous = averageData[i - 1].calories
			let current = averageData[i].calories

			#expect(current >= previous)
		}

		// Should extend to or near midnight (end of day)
		if let lastPoint = averageData.last {
			let calendar = Calendar.current
			let lastHour = calendar.component(.hour, from: lastPoint.hour)

			// Last point should be late in the day (hour 23 or beyond into next day)
			#expect(lastHour >= 22 || lastHour == 0)
		}
	}
}
