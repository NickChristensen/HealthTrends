import XCTest

@testable import HealthTrendsShared

final class ProjectionGoalCrossingDetectorTests: XCTestCase {
	var detector: ProjectionGoalCrossingDetector!

	override func setUp() {
		super.setUp()
		detector = ProjectionGoalCrossingDetector()
	}

	override func tearDown() {
		detector = nil
		super.tearDown()
	}

	// MARK: - First Run (No Previous State)

	func testNoPreviousState_ReturnsNil() {
		let result = detector.detectCrossing(
			previousProjected: nil,
			currentProjected: 800,
			moveGoal: 600
		)

		XCTAssertNil(result, "Should not detect crossing on first run without previous state")
	}

	// MARK: - No Goal Set

	func testNoGoalSet_ReturnsNil() {
		let result = detector.detectCrossing(
			previousProjected: 500,
			currentProjected: 800,
			moveGoal: 0
		)

		XCTAssertNil(result, "Should not detect crossing when goal is 0")
	}

	// MARK: - Below → Above Crossing

	func testCrossing_BelowToAbove_Exact() {
		let result = detector.detectCrossing(
			previousProjected: 799,
			currentProjected: 800,
			moveGoal: 800
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .belowToAbove)
		XCTAssertEqual(result?.projectedTotal, 800)
		XCTAssertEqual(result?.moveGoal, 800)
	}

	func testCrossing_BelowToAbove_WellAbove() {
		let result = detector.detectCrossing(
			previousProjected: 700,
			currentProjected: 900,
			moveGoal: 800
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .belowToAbove)
		XCTAssertEqual(result?.projectedTotal, 900)
		XCTAssertEqual(result?.moveGoal, 800)
	}

	// MARK: - Above → Below Crossing

	func testCrossing_AboveToBelow_Exact() {
		let result = detector.detectCrossing(
			previousProjected: 800,
			currentProjected: 799,
			moveGoal: 800
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .aboveToBelow)
		XCTAssertEqual(result?.projectedTotal, 799)
		XCTAssertEqual(result?.moveGoal, 800)
	}

	func testCrossing_AboveToBelow_WellBelow() {
		let result = detector.detectCrossing(
			previousProjected: 900,
			currentProjected: 700,
			moveGoal: 800
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .aboveToBelow)
		XCTAssertEqual(result?.projectedTotal, 700)
		XCTAssertEqual(result?.moveGoal, 800)
	}

	// MARK: - No Crossing (Staying on Same Side)

	func testNoCrossing_StayingAbove() {
		let result = detector.detectCrossing(
			previousProjected: 850,
			currentProjected: 900,
			moveGoal: 800
		)

		XCTAssertNil(result, "Should not detect crossing when staying above goal")
	}

	func testNoCrossing_StayingBelow() {
		let result = detector.detectCrossing(
			previousProjected: 750,
			currentProjected: 700,
			moveGoal: 800
		)

		XCTAssertNil(result, "Should not detect crossing when staying below goal")
	}

	func testNoCrossing_PreviousExactlyAtGoal_CurrentAbove() {
		let result = detector.detectCrossing(
			previousProjected: 800,
			currentProjected: 850,
			moveGoal: 800
		)

		XCTAssertNil(result, "Should not detect crossing when previous was at goal and current is above")
	}

	// MARK: - Edge Cases

	func testEdgeCase_ZeroProjection() {
		let result = detector.detectCrossing(
			previousProjected: 0,
			currentProjected: 900,
			moveGoal: 800
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .belowToAbove)
	}

	func testEdgeCase_VeryLargeGoal() {
		let result = detector.detectCrossing(
			previousProjected: 5000,
			currentProjected: 3000,
			moveGoal: 4000
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .aboveToBelow)
	}

	func testEdgeCase_FractionalValues() {
		let result = detector.detectCrossing(
			previousProjected: 799.9,
			currentProjected: 800.1,
			moveGoal: 800.0
		)

		XCTAssertNotNil(result)
		XCTAssertEqual(result?.direction, .belowToAbove)
	}

	// MARK: - Event Timestamp

	func testEvent_ContainsTimestamp() {
		let before = Date()
		let result = detector.detectCrossing(
			previousProjected: 700,
			currentProjected: 900,
			moveGoal: 800
		)
		let after = Date()

		XCTAssertNotNil(result)
		XCTAssertGreaterThanOrEqual(result!.detectedAt, before)
		XCTAssertLessThanOrEqual(result!.detectedAt, after)
	}
}
