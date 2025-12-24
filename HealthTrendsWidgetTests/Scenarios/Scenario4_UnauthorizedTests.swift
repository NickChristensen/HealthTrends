import HealthKit
import Testing

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
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime) = HealthKitFixtures.scenario4_unauthorized()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(false)  // NOT authorized
		mockQueryService.configureCurrentTime(currentTime)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)
		let config = EnergyWidgetConfigurationIntent()

		// WHEN: Timeline provider generates entry
		let entry = await provider.loadFreshEntry(forDate: currentTime, configuration: config)

		// Calculate expected move goal (mimics loadCachedMoveGoal() behavior)
		let expectedMoveGoal: Double
		do {
			let cachedData = try mockTodayCache.readEnergyData()
			expectedMoveGoal = cachedData.moveGoal
		} catch {
			expectedMoveGoal = 800.0  // Default fallback
		}

		// THEN: Entry shows unauthorized state
		#expect(entry.isAuthorized == false)

		// No data should be available
		#expect(entry.todayTotal == 0.0)
		#expect(entry.averageAtCurrentHour == 0.0)
		#expect(entry.averageTotal == 0.0)
		#expect(entry.moveGoal == expectedMoveGoal)  // Uses fallback logic

		// No hourly data arrays
		#expect(entry.todayHourlyData.count == 0)
		#expect(entry.averageHourlyData.count == 0)
	}

	@Test("Authorization check happens before data queries")
	@MainActor
	func testAuthorizationGating() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		mockQueryService.configureSamples([])
		mockQueryService.configureMoveGoal(0.0)
		mockQueryService.configureAuthorization(false)
		mockQueryService.configureCurrentTime(Date())

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(
			forDate: Date(), configuration: EnergyWidgetConfigurationIntent())

		// THEN: Should return early with unauthorized state
		#expect(entry.isAuthorized == false)

		// All metrics should be zero
		#expect(entry.todayTotal == 0.0)
		#expect(entry.averageTotal == 0.0)
	}

	@Test("Entry date still reflects current time when unauthorized")
	@MainActor
	func testEntryDateWhenUnauthorized() async throws {
		// GIVEN: Mock dependencies (no filesystem I/O)
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let now = Date()
		mockQueryService.configureSamples([])
		mockQueryService.configureMoveGoal(0.0)
		mockQueryService.configureAuthorization(false)
		mockQueryService.configureCurrentTime(now)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)

		// WHEN: Generate entry
		let entry = await provider.loadFreshEntry(
			forDate: now, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Entry date should still be current time
		let calendar = Calendar.current
		#expect(calendar.isDate(entry.date, inSameDayAs: now))
	}

	@Test("createErrorEntry() triggered when no cache available")
	@MainActor
	func testCreateErrorEntry() async throws {
		// GIVEN: HealthKit query will fail AND no cache exists
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()  // No cache written

		let now = Date()

		// Configure HealthKit to throw error (device locked, etc.)
		mockQueryService.configureTodayError(HKError(.errorDatabaseInaccessible))
		mockQueryService.configureCurrentTime(now)

		let provider = EnergyWidgetProvider(
			healthKitService: mockQueryService,
			averageCacheManager: mockAverageCache,
			todayCacheManager: mockTodayCache
		)

		// WHEN: Generate entry (HealthKit fails, no cache)
		let entry = await provider.loadFreshEntry(
			forDate: now, configuration: EnergyWidgetConfigurationIntent())

		// THEN: Entry should be unauthorized/error state (calls createErrorEntry)
		#expect(entry.isAuthorized == false)

		// All metrics should be zero
		#expect(entry.todayTotal == 0.0)
		#expect(entry.averageAtCurrentHour == 0.0)
		#expect(entry.averageTotal == 0.0)

		// Empty data arrays
		#expect(entry.todayHourlyData.isEmpty)
		#expect(entry.averageHourlyData.isEmpty)

		// Move goal is still loaded from UserDefaults fallback
		#expect(entry.moveGoal >= 0.0)
	}
}
