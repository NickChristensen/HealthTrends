import Foundation

// MARK: - Goal Crossing Events

/// Direction of goal crossing
public enum GoalCrossingDirection: Sendable, Equatable {
	case belowToAbove  // Projected went from below goal → above goal
	case aboveToBelow  // Projected went from above goal → below goal
}

/// Event describing a projection goal crossing
public struct GoalCrossingEvent: Sendable, Equatable {
	public let direction: GoalCrossingDirection
	public let projectedTotal: Double
	public let moveGoal: Double
	public let detectedAt: Date

	public init(
		direction: GoalCrossingDirection,
		projectedTotal: Double,
		moveGoal: Double,
		detectedAt: Date = Date()
	) {
		self.direction = direction
		self.projectedTotal = projectedTotal
		self.moveGoal = moveGoal
		self.detectedAt = detectedAt
	}
}

// MARK: - Crossing Detector

/// Pure logic for detecting when projected total crosses goal threshold
/// Zero side effects - just compares values and returns crossing event if detected
public final class ProjectionGoalCrossingDetector: Sendable {
	public init() {}

	/// Detect if projected total crossed goal threshold between two states
	/// - Parameters:
	///   - previousProjected: Previous projected total (nil if no previous state)
	///   - currentProjected: Current projected total
	///   - moveGoal: Daily move goal
	/// - Returns: GoalCrossingEvent if crossing detected, nil otherwise
	public func detectCrossing(
		previousProjected: Double?,
		currentProjected: Double,
		moveGoal: Double
	) -> GoalCrossingEvent? {
		// Can't detect crossing without previous state
		guard let previous = previousProjected else {
			return nil
		}

		// Skip if goal is not set
		guard moveGoal > 0 else {
			return nil
		}

		// Check for below → above crossing
		if previous < moveGoal && currentProjected >= moveGoal {
			return GoalCrossingEvent(
				direction: .belowToAbove,
				projectedTotal: currentProjected,
				moveGoal: moveGoal
			)
		}

		// Check for above → below crossing
		if previous >= moveGoal && currentProjected < moveGoal {
			return GoalCrossingEvent(
				direction: .aboveToBelow,
				projectedTotal: currentProjected,
				moveGoal: moveGoal
			)
		}

		// No crossing detected
		return nil
	}
}
