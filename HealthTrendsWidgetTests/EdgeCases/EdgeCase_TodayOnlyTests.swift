import HealthKit
import Testing

@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Edge case tests for today-only view (average query fails)
/// Tests graceful degradation when today data succeeds but average data unavailable
@Suite("Edge Case: Today Only (No Average Data)")
struct TodayOnlyTests {

	@Test("Today-only view when average query fails and no cache")
	@MainActor
	func testTodayOnlyNoAverage() async throws {
		// GIVEN: Today query succeeds, but average query fails with no cache fallback
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		// Use scenario 1 data for today's query
		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)
		mockQueryService.configureAuthorization(true)

		// Configure average query to fail
		mockQueryService.configureAverageError(HKError(.errorDatabaseInaccessible))

		// No average cache exists (mockAverageCache is empty)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache,
			notificationScheduler: NoopNotificationScheduler(),
			projectionStateManager: makeTestProjectionStateManager()
		)

		// WHEN: Generate entry (today succeeds, average fails)
		let entry = await provider.loadFreshEntry(
			forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Entry shows today-only state (graceful degradation)
		#expect(entry.isAuthorized == true)

		// Today data should be available
		#expect(entry.todayTotal > 0)
		#expect(entry.todayHourlyData.count > 0)

		// Average data should be missing (query failed, no cache)
		#expect(entry.averageAtCurrentHour == 0.0)
		#expect(entry.averageTotal == 0.0)
		#expect(entry.averageHourlyData.isEmpty)

		// Move goal still available
		#expect(entry.moveGoal == moveGoal)
	}

	@Test("Widget remains functional with partial data")
	@MainActor
	func testPartialDataFunctionality() async throws {
		// GIVEN: Setup for today-only scenario
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureAverageError(HKError(.errorDatabaseInaccessible))

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache,
			notificationScheduler: NoopNotificationScheduler(),
			projectionStateManager: makeTestProjectionStateManager()
		)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(
			forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Widget can still answer "How much have I burned?"
		#expect(entry.todayTotal > 0)

		// But cannot answer "Am I on pace?" or "Where will I end up?"
		#expect(entry.averageAtCurrentHour == 0.0)
		#expect(entry.averageTotal == 0.0)

		// Today data should be cumulative
		let todayData = entry.todayHourlyData
		for i in 1..<todayData.count {
			#expect(todayData[i].calories >= todayData[i - 1].calories)
		}
	}
}
