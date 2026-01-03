import Foundation

@testable import HealthTrendsShared

// MARK: - Mock Cache Managers

/// In-memory mock for AverageDataCacheManager that doesn't touch the filesystem
public final class MockAverageDataCacheManager: AverageDataCacheManager, @unchecked Sendable {
	private var weekdayData: [Weekday: AverageDataCache] = [:]
	private var refreshFlags: [Weekday: Bool] = [:]

	public override init(appGroupIdentifier: String = "", fileName: String = "") {
		// Use empty strings to prevent filesystem access
		super.init(appGroupIdentifier: "", fileName: "")
	}

	public override func load(for weekday: Weekday) -> AverageDataCache? {
		return weekdayData[weekday]
	}

	public override func save(_ cache: AverageDataCache, for weekday: Weekday) throws {
		weekdayData[weekday] = cache
	}

	public override func shouldRefresh(for weekday: Weekday) -> Bool {
		return refreshFlags[weekday] ?? (weekdayData[weekday] == nil)
	}

	public override func clearCache() {
		weekdayData.removeAll()
		refreshFlags.removeAll()
	}

	/// Configure whether shouldRefresh returns true/false for a weekday
	public func configureRefresh(_ shouldRefresh: Bool, for weekday: Weekday) {
		refreshFlags[weekday] = shouldRefresh
	}
}

struct NoopNotificationScheduler: NotificationScheduler {
	func scheduleNotification(for event: GoalCrossingEvent) async throws {}
}

func makeTestProjectionStateManager() -> ProjectionStateCacheManager {
	let fileName = "projection-state-\(UUID().uuidString).json"
	return ProjectionStateCacheManager(
		containerURLProvider: { FileManager.default.temporaryDirectory },
		fileName: fileName
	)
}

/// In-memory mock for TodayEnergyCacheManager that doesn't touch the filesystem
public final class MockTodayEnergyCacheManager: TodayEnergyCacheManager {
	private var cache: TodayEnergyCache?

	// Not a singleton - each test gets its own instance
	public init() {}

	public override func writeEnergyData(
		todayTotal: Double,
		moveGoal: Double,
		todayHourlyData: [HourlyEnergyData],
		latestSampleTimestamp: Date? = nil
	) throws {
		cache = TodayEnergyCache(
			todayTotal: todayTotal,
			moveGoal: moveGoal,
			todayHourlyData: todayHourlyData.map { .init(from: $0) },
			latestSampleTimestamp: latestSampleTimestamp
		)
	}

	public override func readEnergyData() throws -> TodayEnergyCache {
		guard let cache = cache else {
			throw TodayEnergyCacheError.fileNotFound
		}
		return cache
	}

	public override func clearCache() {
		cache = nil
	}
}
