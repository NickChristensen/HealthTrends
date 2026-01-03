import Foundation
import HealthTrendsShared
import UserNotifications
import os

/// Concrete notification scheduler using UNUserNotificationCenter
/// Schedules local notifications for projection goal crossings
final class UserNotificationScheduler: NotificationScheduler, Sendable {
	private let notificationCenter: UNUserNotificationCenter
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "UserNotificationScheduler"
	)

	public init(notificationCenter: UNUserNotificationCenter = .current()) {
		self.notificationCenter = notificationCenter
	}

	public func scheduleNotification(for event: GoalCrossingEvent) async throws {
		// Check authorization first
		let settings = await notificationCenter.notificationSettings()
		guard settings.authorizationStatus == .authorized else {
			Self.logger.warning("Notification permission not granted - skipping notification")
			return
		}

		// Create content
		let content = UNMutableNotificationContent()
		content.title = formatTitle(for: event)
		content.body = formatBody(for: event)
		content.sound = .default
		content.categoryIdentifier = "GOAL_CROSSING"

		// Create request (use constant identifier to replace previous notifications)
		let request = UNNotificationRequest(
			identifier: "projection-goal-crossing",
			content: content,
			trigger: nil  // Deliver immediately
		)

		// Schedule
		try await notificationCenter.add(request)
		Self.logger.info("Scheduled goal crossing notification: \(String(describing: event.direction))")
	}

	private func formatTitle(for event: GoalCrossingEvent) -> String {
		switch event.direction {
		case .belowToAbove:
			return "On Track! 🎯"
		case .aboveToBelow:
			return "Falling Behind 📉"
		}
	}

	private func formatBody(for event: GoalCrossingEvent) -> String {
		let projected = Int(event.projectedTotal)
		let goal = Int(event.moveGoal)

		switch event.direction {
		case .belowToAbove:
			return
				"You're now projected to reach your goal! Projected: \(projected) cal / Goal: \(goal) cal"
		case .aboveToBelow:
			return "Your pace has slowed. Projected: \(projected) cal / Goal: \(goal) cal"
		}
	}
}
