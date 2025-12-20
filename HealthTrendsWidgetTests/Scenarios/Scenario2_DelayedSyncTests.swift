import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Integration tests for PRD Scenario 2: Delayed Sync
///
/// Scenario: Saturday, 3:43 PM but data only current to 2:15 PM (88 minutes stale)
/// Expected: Data Time shows staleness, Today line stops at 2:15 PM, Average continues projecting
@Suite("Scenario 2: Delayed Sync")
struct DelayedSyncTests {

	@Test("Data time reflects staleness when HealthKit data is 88 minutes old")
	@MainActor
	func testDelayedSync() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario2_delayedSync()
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

		// THEN: Entry reflects stale data state
		#expect(entry.isAuthorized == true)

		// Data time should be 2:15 PM (when data last updated)
		let calendar = Calendar.current
		let dataHour = calendar.component(.hour, from: entry.date)
		let dataMinute = calendar.component(.minute, from: entry.date)
		#expect(dataHour == 14)
		#expect(dataMinute == 15)

		// Today total should stop at 2:15 PM (not include 2:15-3:43 PM activity)
		// This will be less than Scenario 1's 550 cal
		#expect(entry.todayTotal < 550.0)

		// Average should still project to midnight
		#expect(entry.projectedTotal == 1013.0)

		// Move goal unchanged
		#expect(entry.moveGoal == 900.0)
	}

	@Test("Today line stops at data time, not current time")
	@MainActor
	func testTodayLineStopsAtDataTime() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario2_delayedSync()
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

		// THEN: Today's data should stop at 2:15 PM
		let calendar = Calendar.current
		if let lastPoint = entry.todayHourlyData.last {
			let lastHour = calendar.component(.hour, from: lastPoint.hour)
			let lastMinute = calendar.component(.minute, from: lastPoint.hour)

			// Last data point should be at or before 2:15 PM
			#expect(lastHour <= 14)
			if lastHour == 14 {
				#expect(lastMinute <= 15)
			}
		}
	}

	@Test("Average line continues to project despite stale today data")
	@MainActor
	func testAverageProjectsIndependently() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario2_delayedSync()
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

		// THEN: Average data should still project to end of day
		let averageData = entry.averageHourlyData
		#expect(averageData.count > 0)

		// Should be cumulative
		for i in 1..<averageData.count {
			let previous = averageData[i - 1].calories
			let current = averageData[i].calories
			#expect(current >= previous)
		}

		// Should extend to late in the day
		if let lastPoint = averageData.last {
			let calendar = Calendar.current
			let lastHour = calendar.component(.hour, from: lastPoint.hour)
			#expect(lastHour >= 22 || lastHour == 0)
		}
	}

	@Test("Cache fallback when HealthKit query fails (device locked)")
	@MainActor
	func testCacheFallbackDeviceLocked() async throws {
		// GIVEN: Set up mock services
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario2_delayedSync()

		// STEP 1: Generate average cache data (before device locks)
		// Use scenario 1's samples to build average pattern
		let (scenario1Samples, _, _, _) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(scenario1Samples)
		mockQueryService.configureCurrentTime(currentTime)
		mockQueryService.configureAuthorization(true)
		let (projectedTotal, averageHourlyData) = try await mockQueryService.fetchAverageData(for: 7)  // Saturday

		// Save average to cache
		let avgCache = AverageDataCache(
			averageHourlyPattern: averageHourlyData,
			projectedTotal: projectedTotal,
			cachedAt: dataTime,
			cacheVersion: 1
		)
		try mockAverageCache.save(avgCache, for: Weekday(date: currentTime)!)

		// STEP 2: Generate today cache data (data from 2:15 PM)
		let calendar = Calendar.current
		let startOfDay = calendar.startOfDay(for: dataTime)
		let cachedHourlyData = [
			HourlyEnergyData(hour: calendar.date(byAdding: .hour, value: 9, to: startOfDay)!, calories: 120.0),
			HourlyEnergyData(hour: calendar.date(byAdding: .hour, value: 10, to: startOfDay)!, calories: 210.0),
			HourlyEnergyData(hour: calendar.date(byAdding: .hour, value: 14, to: startOfDay)!, calories: 480.0)
		]
		try mockTodayCache.writeEnergyData(
			todayTotal: 480.0,
			moveGoal: moveGoal,
			todayHourlyData: cachedHourlyData,
			latestSampleTimestamp: dataTime
		)

		// STEP 3: Now device locks - HealthKit queries will fail
		mockQueryService.configureTodayError(HKError(.errorDatabaseInaccessible))

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)
		let config = EnergyWidgetConfigurationIntent()

		// WHEN: Timeline provider generates entry (HealthKit fails, uses cache)
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: config)

		// THEN: Entry should use cached data
		#expect(entry.isAuthorized == true)  // Cache exists = authorized

		// Should show cached today total (480 cal at 2:15 PM)
		#expect(entry.todayTotal == 480.0)

		// Data time should reflect cached data timestamp (2:15 PM)
		let dataHour = calendar.component(.hour, from: entry.date)
		let dataMinute = calendar.component(.minute, from: entry.date)
		#expect(dataHour == 14)
		#expect(dataMinute == 15)

		// Should still have average projection (from cache)
		#expect(entry.projectedTotal > 0)

		// Move goal from cache
		#expect(entry.moveGoal == 900.0)

		// Today data should match cached data
		#expect(entry.todayHourlyData.count > 0)
		#expect(entry.todayHourlyData.last?.calories == 480.0)
	}
}
