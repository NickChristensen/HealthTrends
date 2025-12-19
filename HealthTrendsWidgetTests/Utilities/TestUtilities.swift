import Foundation
@testable import HealthTrendsShared

/// Test utilities for widget integration tests
enum TestUtilities {
	/// Clear all caches to ensure clean test state
	/// Call this at the start of each test to prevent cross-test pollution
	static func clearAllCaches() {
		AverageDataCacheManager().clearCache()
		TodayEnergyCacheManager.shared.clearCache()
	}
}
