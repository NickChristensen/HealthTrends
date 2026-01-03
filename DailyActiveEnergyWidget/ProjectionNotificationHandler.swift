import Foundation
import HealthTrendsShared
import os

/// Handles projection goal crossing detection and notification scheduling
/// Extracted from the timeline provider to keep widget logic focused on data loading
final class ProjectionNotificationHandler: Sendable {
	private let detector: ProjectionGoalCrossingDetector
	private let notificationScheduler: NotificationScheduler
	private let projectionStateManager: ProjectionStateCacheManager
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "ProjectionNotificationHandler"
	)

	init(
		detector: ProjectionGoalCrossingDetector = ProjectionGoalCrossingDetector(),
		notificationScheduler: NotificationScheduler = UserNotificationScheduler(),
		projectionStateManager: ProjectionStateCacheManager = .shared
	) {
		self.detector = detector
		self.notificationScheduler = notificationScheduler
		self.projectionStateManager = projectionStateManager
	}

	/// Clear persisted projection state when the day rolls over
	func clearProjectionStateForNewDay() {
		projectionStateManager.clearState()
		Self.logger.info("Cleared projection state at midnight - new day baseline")
	}

	/// Detect goal crossings and schedule notifications
	/// - Parameters:
	///   - currentProjected: The projected total based on latest data
	///   - moveGoal: The user's active energy goal
	///   - referenceDate: Date associated with the projection data
	func handleGoalCrossing(
		currentProjected: Double,
		moveGoal: Double,
		referenceDate: Date
	) async {
		let previousProjected = readPreviousProjection(referenceDate: referenceDate)

		guard
			let event = detector.detectCrossing(
				previousProjected: previousProjected,
				currentProjected: currentProjected,
				moveGoal: moveGoal
			)
		else {
			persistProjectionState(projectedTotal: currentProjected)
			return
		}

		do {
			try await notificationScheduler.scheduleNotification(for: event)
			Self.logger.info("✅ Notification scheduled successfully")
		} catch {
			Self.logger.error(
				"❌ Failed to schedule notification: \(error.localizedDescription, privacy: .public)"
			)
		}
		persistProjectionState(projectedTotal: currentProjected)
	}

	// MARK: - Private helpers

	private func readPreviousProjection(referenceDate: Date) -> Double? {
		do {
			let state = try projectionStateManager.readState()
			let calendar = Calendar.current
			if calendar.isDate(state.timestamp, inSameDayAs: referenceDate) {
				return state.projectedTotal
			} else {
				projectionStateManager.clearState()
				Self.logger.info("Cleared projection state from previous day")
				return nil
			}
		} catch ProjectionStateCacheError.fileNotFound {
			return nil
		} catch {
			Self.logger.error(
				"Failed to read projection state: \(error.localizedDescription, privacy: .public)"
			)
			return nil
		}
	}

	private func persistProjectionState(projectedTotal: Double) {
		do {
			try projectionStateManager.writeState(ProjectionState(projectedTotal: projectedTotal))
		} catch {
			Self.logger.error(
				"Failed to persist projection state: \(error.localizedDescription, privacy: .public)"
			)
			Self.logger.error("Next crossing detection may be inaccurate")
		}
	}
}
