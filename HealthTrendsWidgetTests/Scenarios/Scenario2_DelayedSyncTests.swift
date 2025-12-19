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
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Mock HealthKit with Scenario 2 data (stale by 88 min)
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario2_delayedSync()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)
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
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Scenario 2 setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario2_delayedSync()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

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
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Scenario 2 setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario2_delayedSync()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

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
}
