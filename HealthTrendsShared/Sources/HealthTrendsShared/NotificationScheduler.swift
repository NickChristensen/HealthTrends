import Foundation

/// Protocol for scheduling user notifications
/// Abstraction enables testing without triggering actual system notifications
public protocol NotificationScheduler: Sendable {
	/// Schedule a notification for a goal crossing event
	/// - Parameter event: The crossing event to notify about
	/// - Throws: If notification scheduling fails
	func scheduleNotification(for event: GoalCrossingEvent) async throws
}
