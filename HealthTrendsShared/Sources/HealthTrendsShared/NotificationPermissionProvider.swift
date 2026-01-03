import Foundation

/// Protocol for requesting notification permissions
/// Abstraction enables testing without triggering actual permission prompts
public protocol NotificationPermissionProvider: Sendable {
	/// Request notification permission from the user
	/// - Returns: true if granted, false if denied
	/// - Throws: If permission request fails
	func requestPermission() async throws -> Bool
}
