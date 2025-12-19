import Foundation
import HealthKit

/// Protocol for providing HealthKit data to the app and widget
/// Enables protocol-based dependency injection for testing without exposing implementation details
public protocol HealthDataProvider: Sendable {
	/// Check if HealthKit read authorization is likely granted
	/// Returns true if samples found (permission likely granted), false if no samples (permission likely denied or no data)
	func checkReadAuthorization() async -> Bool

	/// Fetch today's hourly energy breakdown
	/// Returns tuple of:
	/// - data: Cumulative calories at each hour boundary
	/// - latestSampleTimestamp: Timestamp of most recent HealthKit sample (nil if no samples)
	func fetchTodayHourlyTotals() async throws -> (data: [HourlyEnergyData], latestSampleTimestamp: Date?)

	/// Fetch average Active Energy data from past occurrences of the current weekday
	/// Returns "Total" and "Average" (see CLAUDE.md)
	/// Uses last 10 occurrences of today's weekday (e.g., if today is Saturday, uses last 10 Saturdays)
	/// - Parameter weekday: Optional weekday override (1=Sunday, 7=Saturday). If nil, uses current weekday.
	func fetchAverageData(for weekday: Int?) async throws -> (total: Double, hourlyData: [HourlyEnergyData])

	/// Fetch today's active energy goal from Activity Summary
	/// iOS supports weekday-specific goals, so this must be queried fresh each day
	/// Returns 0 if no goal is set or if running on simulator
	func fetchMoveGoal() async throws -> Double
}
