import HealthKit
import Testing

@testable import DailyActiveEnergyWidgetExtension
@testable import HealthTrendsShared

/// Tests to verify that average and projected lines extend to midnight endpoint
@Suite("Edge Case: Midnight Endpoint")
struct MidnightEndpointTests {

	@Test("Average data includes midnight endpoint (hour 0 of next day)")
	@MainActor
	func testAverageIncludesMidnightEndpoint() async throws {
		// GIVEN: Mock dependencies
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

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

		// THEN: Average data should include end-of-day midnight point
		let averageData = entry.averageHourlyData

		#expect(averageData.count > 0, "Average data should not be empty")

		let calendar = Calendar.current
		let startOfToday = calendar.startOfDay(for: currentTime)
		let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

		// Filter to end-of-day midnight points (hour 0 of tomorrow with calories > 0)
		let endOfDayMidnightPoints = averageData.filter { point in
			let hour = calendar.component(.hour, from: point.hour)
			let minute = calendar.component(.minute, from: point.hour)
			return hour == 0 && minute == 0
				&& calendar.isDate(point.hour, inSameDayAs: startOfTomorrow)
				&& point.calories > 0
		}

		// Verify exactly ONE end-of-day midnight endpoint (no duplicates)
		#expect(
			endOfDayMidnightPoints.count == 1,
			"Should have exactly one end-of-day midnight point, found \(endOfDayMidnightPoints.count)"
		)

		// Verify it has the projected total value
		if let endOfDayPoint = endOfDayMidnightPoints.first {
			#expect(
				endOfDayPoint.calories > 0,
				"End-of-day midnight should have projected total (calories > 0)")
			#expect(
				endOfDayPoint.calories == entry.averageTotal,
				"End-of-day midnight calories (\(endOfDayPoint.calories)) should match projected total (\(entry.averageTotal))"
			)
		}

		// Verify start-of-day midnight (if present) has 0 calories
		let startOfDayMidnightPoints = averageData.filter { point in
			let hour = calendar.component(.hour, from: point.hour)
			let minute = calendar.component(.minute, from: point.hour)
			return hour == 0 && minute == 0
				&& calendar.isDate(point.hour, inSameDayAs: startOfToday)
		}

		for point in startOfDayMidnightPoints {
			#expect(
				point.calories == 0,
				"Start-of-day midnight should have 0 calories, found \(point.calories)")
		}
	}

	@Test("Projected data includes midnight endpoint")
	@MainActor
	func testProjectedIncludesMidnightEndpoint() async throws {
		// GIVEN: Mock dependencies
		let mockQueryService = MockHealthKitQueryService()
		let mockAverageCache = MockAverageDataCacheManager()
		let mockTodayCache = MockTodayEnergyCacheManager()

		let (samples, moveGoal, currentTime, _) = HealthKitFixtures.scenario1_normalOperation()
		mockQueryService.configureSamples(samples)
		mockQueryService.configureMoveGoal(moveGoal)
		mockQueryService.configureAuthorization(true)
		mockQueryService.configureCurrentTime(currentTime)

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

		// THEN: Verify average data includes the midnight endpoint
		let averageData = entry.averageHourlyData
		let calendar = Calendar.current
		let startOfToday = calendar.startOfDay(for: currentTime)
		let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

		// Verify last point is at midnight of next day
		guard let lastPoint = averageData.last else {
			Issue.record("Average data has no last point")
			return
		}

		let lastHour = calendar.component(.hour, from: lastPoint.hour)
		let lastMinute = calendar.component(.minute, from: lastPoint.hour)
		let isTomorrow = calendar.isDate(lastPoint.hour, inSameDayAs: startOfTomorrow)

		// Last point should be hour 0 of tomorrow (midnight)
		#expect(lastHour == 0, "Last point should be at hour 0 (midnight), found hour \(lastHour)")
		#expect(lastMinute == 0, "Last point should be at minute 0, found minute \(lastMinute)")
		#expect(isTomorrow, "Last point should be on tomorrow's date")
		#expect(
			lastPoint.calories > 0,
			"Last point should have projected total (calories > 0), found \(lastPoint.calories)")
		#expect(
			lastPoint.calories == entry.averageTotal,
			"Last point calories (\(lastPoint.calories)) should match projected total (\(entry.averageTotal))"
		)
	}
}
