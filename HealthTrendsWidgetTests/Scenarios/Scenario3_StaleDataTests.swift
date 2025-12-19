import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Integration tests for PRD Scenario 3: Stale Data (Previous Day)
///
/// Scenario: Saturday, 10:00 AM but last HealthKit data is from Friday 11 PM (11 hours old, different day)
/// Expected: No "Today" line shown, Average-only display for Saturday
@Suite("Scenario 3: Stale Data (Previous Day)")
struct StaleDataTests {

	@Test("No today line when data is from previous day")
	@MainActor
	func testStaleDataFromPreviousDay() async throws {
		// Clear cache
		AverageDataCacheManager().clearCache()

		// GIVEN: Mock HealthKit with Scenario 3 data (Friday data on Saturday)
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario3_staleData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)
		let config = EnergyWidgetConfigurationIntent()

		// WHEN: Timeline provider generates entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: config)

		// THEN: Entry shows average-only state
		#expect(entry.isAuthorized == true)

		// No today data (empty or zero total)
		#expect(entry.todayTotal == 0.0)
		#expect(entry.todayHourlyData.count == 0)

		// Average data should still be available for Saturday
		#expect(entry.averageHourlyData.count > 0)

		// Projected total should be Saturday's average (1013 cal)
		#expect(entry.projectedTotal == 1013.0)

		// Move goal unchanged
		#expect(entry.moveGoal == 900.0)
	}

	@Test("Data time reflects last available data (previous day)")
	@MainActor
	func testDataTimeFromPreviousDay() async throws {
		// Clear cache
		AverageDataCacheManager().clearCache()

		// GIVEN: Scenario 3 setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario3_staleData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Data time should be Friday 11 PM
		let calendar = Calendar.current
		let entryWeekday = calendar.component(.weekday, from: entry.date)
		let currentWeekday = calendar.component(.weekday, from: currentTime)

		// Entry date should be from Friday (weekday 6), not Saturday (weekday 7)
		// OR entry date should be significantly before current time
		let timeDifference = currentTime.timeIntervalSince(entry.date)
		#expect(timeDifference >= 10 * 3600)  // At least 10 hours old
	}

	@Test("Average line shows Saturday pattern despite Friday data")
	@MainActor
	func testAverageForCorrectWeekday() async throws {
		// Clear cache
		AverageDataCacheManager().clearCache()

		// GIVEN: Scenario 3 setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario3_staleData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Average should be calculated for Saturday, not Friday
		let averageData = entry.averageHourlyData

		// Should have Saturday's average pattern
		#expect(averageData.count > 0)

		// Projected total should be Saturday's average (1013 cal)
		#expect(entry.projectedTotal == 1013.0)

		// Last point should project to end of Saturday
		if let lastPoint = averageData.last {
			let calendar = Calendar.current
			let lastHour = calendar.component(.hour, from: lastPoint.hour)
			#expect(lastHour >= 22 || lastHour == 0)
		}
	}
}
