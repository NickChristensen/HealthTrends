import Foundation
import os

// MARK: - Projection State

/// Tracks the last known projected total to detect goal crossings
public struct ProjectionState: Codable, Sendable {
	public let projectedTotal: Double
	public let timestamp: Date

	public init(projectedTotal: Double, timestamp: Date = Date()) {
		self.projectedTotal = projectedTotal
		self.timestamp = timestamp
	}
}

// MARK: - State Cache Manager

/// Manages persistence of projection state for crossing detection
/// Stores last known projected total in App Group container
public final class ProjectionStateCacheManager: Sendable {
	private let appGroupIdentifier: String
	private let fileName: String
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "ProjectionStateCacheManager"
	)

	public static let shared = ProjectionStateCacheManager()

	public init(
		appGroupIdentifier: String = "group.com.healthtrends.shared",
		fileName: String = "projection-state.json"
	) {
		self.appGroupIdentifier = appGroupIdentifier
		self.fileName = fileName
	}

	/// Get the file URL for storing projection state
	private var fileURL: URL? {
		FileManager.default
			.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
			.appendingPathComponent(fileName)
	}

	/// Read previous projection state
	/// - Returns: Previous projection state
	/// - Throws: ProjectionStateCacheError if container not found or file doesn't exist
	public func readState() throws -> ProjectionState {
		guard let fileURL = fileURL else {
			throw ProjectionStateCacheError.containerNotFound
		}

		guard FileManager.default.fileExists(atPath: fileURL.path) else {
			throw ProjectionStateCacheError.fileNotFound
		}

		let data = try Data(contentsOf: fileURL)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(ProjectionState.self, from: data)
	}

	/// Write current projection state
	/// - Parameter state: The projection state to persist
	/// - Throws: ProjectionStateCacheError if container not found or write fails
	public func writeState(_ state: ProjectionState) throws {
		guard let fileURL = fileURL else {
			throw ProjectionStateCacheError.containerNotFound
		}

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(state)
		try data.write(to: fileURL, options: .atomic)
	}

	/// Clear state (useful for testing/debugging)
	public func clearState() {
		guard let fileURL = fileURL else { return }
		try? FileManager.default.removeItem(at: fileURL)
		Self.logger.debug("Cleared projection state cache")
	}
}

// MARK: - Errors

public enum ProjectionStateCacheError: Error {
	case containerNotFound
	case fileNotFound
}
