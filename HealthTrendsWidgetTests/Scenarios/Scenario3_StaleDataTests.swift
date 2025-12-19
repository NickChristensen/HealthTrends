import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Integration tests for PRD Scenario 3: Stale Data (Previous Day)
///
/// Scenario: Saturday, 10:23 AM but last HealthKit data is from Friday 10:47 PM (11 hours 36 min old, different day)
/// Expected: No "Today" line shown, Average-only display for Saturday
@Suite("Scenario 3: Stale Data (Previous Day)")
struct StaleDataTests {

	@Test("No today line when data is from previous day")
	@MainActor
	func testStaleDataFromPreviousDay() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario3_staleData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)
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

	@Test("Data time shows current clock time in average-only view")
	@MainActor
	func testDataTimeFromPreviousDay() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario3_staleData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Data time should be current clock time (Saturday 10:23 AM), not Friday's stale time
		// In average-only view, we show the current time as the data time marker
		let calendar = Calendar.current
		let entryHour = calendar.component(.hour, from: entry.date)
		let entryMinute = calendar.component(.minute, from: entry.date)
		let entryWeekday = calendar.component(.weekday, from: entry.date)

		#expect(entryWeekday == 7)  // Saturday
		#expect(entryHour == 10)
		#expect(entryMinute == 23)
	}

	@Test("Average line shows Saturday pattern despite Friday data")
	@MainActor
	func testAverageForCorrectWeekday() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario3_staleData()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)

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
