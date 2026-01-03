import XCTest

@testable import HealthTrendsShared

final class ProjectionStateCacheManagerTests: XCTestCase {
	var cacheManager: ProjectionStateCacheManager!
	let testFileName = "test-projection-state.json"
	private var tempDirectory: URL?

	override func setUp() {
		super.setUp()
		let uniqueDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try? FileManager.default.createDirectory(
			at: uniqueDirectory,
			withIntermediateDirectories: true
		)
		tempDirectory = uniqueDirectory
		cacheManager = ProjectionStateCacheManager(
			containerURLProvider: { uniqueDirectory },
			fileName: testFileName
		)
		// Clean up any existing test cache
		cacheManager.clearState()
	}

	override func tearDown() {
		cacheManager.clearState()
		if let tempDirectory {
			try? FileManager.default.removeItem(at: tempDirectory)
		}
		tempDirectory = nil
		cacheManager = nil
		super.tearDown()
	}

	// MARK: - Write and Read

	func testWriteAndRead_Success() throws {
		let testState = ProjectionState(
			projectedTotal: 875.5,
			timestamp: Date()
		)

		// Write
		try cacheManager.writeState(testState)

		// Read
		let readState = try cacheManager.readState()

		// Verify
		XCTAssertEqual(readState.projectedTotal, testState.projectedTotal)
		XCTAssertEqual(
			readState.timestamp.timeIntervalSince1970, testState.timestamp.timeIntervalSince1970,
			accuracy: 1.0)
	}

	func testMultipleWrites_OverwritesPrevious() throws {
		// Write first state
		let firstState = ProjectionState(projectedTotal: 700, timestamp: Date())
		try cacheManager.writeState(firstState)

		// Write second state
		let secondState = ProjectionState(projectedTotal: 900, timestamp: Date())
		try cacheManager.writeState(secondState)

		// Read
		let readState = try cacheManager.readState()

		// Verify only second state is persisted
		XCTAssertEqual(readState.projectedTotal, 900)
	}

	// MARK: - Read Errors

	func testRead_FileNotFound_ThrowsError() {
		XCTAssertThrowsError(try cacheManager.readState()) { error in
			XCTAssertTrue(error is ProjectionStateCacheError)
			if let cacheError = error as? ProjectionStateCacheError {
				XCTAssertEqual(cacheError, ProjectionStateCacheError.fileNotFound)
			}
		}
	}

	func testRead_AfterClear_ThrowsFileNotFound() throws {
		// Write state
		let state = ProjectionState(projectedTotal: 800, timestamp: Date())
		try cacheManager.writeState(state)

		// Clear
		cacheManager.clearState()

		// Try to read
		XCTAssertThrowsError(try cacheManager.readState()) { error in
			if let cacheError = error as? ProjectionStateCacheError {
				XCTAssertEqual(cacheError, ProjectionStateCacheError.fileNotFound)
			}
		}
	}

	// MARK: - Clear State

	func testClearState_DeletesFile() throws {
		// Write state
		let state = ProjectionState(projectedTotal: 800, timestamp: Date())
		try cacheManager.writeState(state)

		// Verify it exists
		_ = try cacheManager.readState()

		// Clear
		cacheManager.clearState()

		// Verify it's gone
		XCTAssertThrowsError(try cacheManager.readState())
	}

	// MARK: - Timestamp Precision

	func testTimestamp_PreservesSeconds() throws {
		let now = Date()
		let state = ProjectionState(projectedTotal: 850, timestamp: now)

		try cacheManager.writeState(state)
		let readState = try cacheManager.readState()

		// ISO8601 encoding preserves seconds, not milliseconds
		XCTAssertEqual(readState.timestamp.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
	}

	// MARK: - Concurrent Access

	func testConcurrentWrites_DoNotCorrupt() throws {
		let expectation = XCTestExpectation(description: "All concurrent writes complete")
		expectation.expectedFulfillmentCount = 10

		DispatchQueue.concurrentPerform(iterations: 10) { index in
			do {
				let state = ProjectionState(
					projectedTotal: Double(index * 100),
					timestamp: Date()
				)
				try cacheManager.writeState(state)
				expectation.fulfill()
			} catch {
				XCTFail("Concurrent write failed: \(error)")
			}
		}

		wait(for: [expectation], timeout: 5.0)

		// Verify we can still read (file not corrupted)
		XCTAssertNoThrow(try cacheManager.readState())
	}

	// MARK: - Fractional Values

	func testFractionalProjection_PreservesPrecision() throws {
		let state = ProjectionState(
			projectedTotal: 875.123456,
			timestamp: Date()
		)

		try cacheManager.writeState(state)
		let readState = try cacheManager.readState()

		XCTAssertEqual(readState.projectedTotal, 875.123456, accuracy: 0.000001)
	}

	// MARK: - Large Values

	func testLargeProjection_Persists() throws {
		let state = ProjectionState(
			projectedTotal: 9999999.99,
			timestamp: Date()
		)

		try cacheManager.writeState(state)
		let readState = try cacheManager.readState()

		XCTAssertEqual(readState.projectedTotal, 9999999.99, accuracy: 0.01)
	}

	// MARK: - Zero Values

	func testZeroProjection_Persists() throws {
		let state = ProjectionState(
			projectedTotal: 0.0,
			timestamp: Date()
		)

		try cacheManager.writeState(state)
		let readState = try cacheManager.readState()

		XCTAssertEqual(readState.projectedTotal, 0.0)
	}
}
