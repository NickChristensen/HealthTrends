import Testing
import HealthKit
@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Integration tests for PRD Scenario 4: No Authorization
///
/// Scenario: User has added widget but hasn't granted HealthKit permissions
/// Expected: No data shown, authorization state = false
@Suite("Scenario 4: No Authorization")
struct UnauthorizedTests {

	@Test("Widget shows unauthorized state when HealthKit permission denied")
	@MainActor
	func testUnauthorizedState() async throws {
		// Clear cache
		AverageDataCacheManager().clearCache()

		// GIVEN: Mock HealthKit with no authorization
		let mockQueryService = MockHealthKitQueryService()
		let (samples, moveGoal, currentTime) = HealthKitFixtures.scenario4_unauthorized()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(false)  // NOT authorized
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)
		let config = EnergyWidgetConfigurationIntent()

		// WHEN: Timeline provider generates entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: config)

		// THEN: Entry shows unauthorized state
		#expect(entry.isAuthorized == false)

		// No data should be available
		#expect(entry.todayTotal == 0.0)
		#expect(entry.averageAtCurrentHour == 0.0)
		#expect(entry.projectedTotal == 0.0)
		#expect(entry.moveGoal == 0.0)

		// No hourly data arrays
		#expect(entry.todayHourlyData.count == 0)
		#expect(entry.averageHourlyData.count == 0)
	}

	@Test("Authorization check happens before data queries")
	@MainActor
	func testAuthorizationGating() async throws {
		// Clear cache
		AverageDataCacheManager().clearCache()

		// GIVEN: Unauthorized state with empty samples
		let mockQueryService = MockHealthKitQueryService()
		mockQueryService.configureSamples([])
		mockQueryService.configureMoveGoal(0.0)
		mockQueryService.configureAuthorization(false)
		mockQueryService.configureCurrentTime(Date())

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: Date(), configuration: EnergyWidgetConfigurationIntent())

		// THEN: Should return early with unauthorized state
		#expect(entry.isAuthorized == false)

		// All metrics should be zero
		#expect(entry.todayTotal == 0.0)
		#expect(entry.projectedTotal == 0.0)
	}

	@Test("Entry date still reflects current time when unauthorized")
	@MainActor
	func testEntryDateWhenUnauthorized() async throws {
		// Clear cache
		AverageDataCacheManager().clearCache()

		// GIVEN: Unauthorized state
		let mockQueryService = MockHealthKitQueryService()
		let now = Date()
		mockQueryService.configureSamples([])
		mockQueryService.configureMoveGoal(0.0)
		mockQueryService.configureAuthorization(false)
		mockQueryService.configureCurrentTime(now)

		let provider = EnergyWidgetProvider(healthKitService: mockQueryService)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(forDate: now, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Entry date should still be current time
		let calendar = Calendar.current
		#expect(calendar.isDate(entry.date, inSameDayAs: now))
	}
}
