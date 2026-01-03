import Foundation
import HealthTrendsShared
import UserNotifications
import os

/// Concrete notification permission provider using UNUserNotificationCenter
/// Requests notification permissions from the user in the main app
final class UserNotificationPermissionProvider: NotificationPermissionProvider, Sendable {
	private let notificationCenter: UNUserNotificationCenter
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "UserNotificationPermissionProvider"
	)

	init(notificationCenter: UNUserNotificationCenter = .current()) {
		self.notificationCenter = notificationCenter
	}

	func requestPermission() async throws -> Bool {
		let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
		if granted {
			Self.logger.info("Notification permission granted")
		} else {
			Self.logger.warning("Notification permission denied")
		}
		return granted
	}
}
