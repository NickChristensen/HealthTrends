import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Integration tests for PRD Scenario 1: Normal Operation (Fresh Data)
///
/// Scenario: Saturday, 3:43 PM with HealthKit data current to 3:40 PM (3 minutes old)
/// Expected: Today=550, Average=510, Total=1013, Move Goal=900, Data Time=3:40 PM
@Suite("Scenario 1: Normal Operation (Fresh Data)")
struct NormalOperationTests {

	@Test("Saturday 3:43 PM with data current to 3:40 PM produces correct entry")
	@MainActor
	func testNormalOperation() async throws {
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Mock HealthKit with Scenario 1 data
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)
		let config = EnergyWidgetConfigurationIntent()

		// WHEN: Timeline provider generates entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: config)

		// THEN: Entry matches PRD Scenario 1 expectations (exact values)
		#expect(entry.isAuthorized == true)

		// Validate Today total (exactly 550 cal)
		#expect(entry.todayTotal == 550.0)

		// Validate Average at current hour (exactly 510 cal)
		#expect(entry.averageAtCurrentHour == 510.0)

		// Validate Projected Total (exactly 1013 cal)
		#expect(entry.projectedTotal == 1013.0)

		// Validate Move Goal
		#expect(entry.moveGoal == 900.0)

		// Validate data arrays are populated
		#expect(entry.todayHourlyData.count >= 3)
		#expect(entry.averageHourlyData.count > 0)

		// Validate Data Time is at 3:40 PM Saturday
		let calendar = Calendar.current
		let dataHour = calendar.component(.hour, from: entry.date)
		let dataMinute = calendar.component(.minute, from: entry.date)

		#expect(dataHour == 15)
		#expect(dataMinute == 40)
	}

	@Test("Today line contains expected data structure")
	@MainActor
	func testTodayDataStructure() async throws {
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Scenario 1 setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Today's hourly data should be cumulative and increasing
		let todayData = entry.todayHourlyData

		#expect(todayData.count > 0)

		// Validate cumulative property: each value should be >= previous
		for i in 1..<todayData.count {
			let previous = todayData[i - 1].calories
			let current = todayData[i].calories

			#expect(current >= previous)
		}

		// Last data point should match todayTotal
		if let lastPoint = todayData.last {
			#expect(lastPoint.calories == entry.todayTotal)
		}

		// Data should stop at data time (3:40 PM)
		if let lastPoint = todayData.last {
			let calendar = Calendar.current
			let lastHour = calendar.component(.hour, from: lastPoint.hour)
			#expect(lastHour <= 15)
		}
	}

	@Test("Average line projects to midnight")
	@MainActor
	func testAverageProjection() async throws {
		// Clear all caches to ensure clean test state
		TestUtilities.clearAllCaches()

		// GIVEN: Scenario 1 setup
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime, dataTime) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Average data should project through end of day
		let averageData = entry.averageHourlyData

		#expect(averageData.count > 0)

		// Should be cumulative
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
