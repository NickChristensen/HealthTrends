import Foundation

/// Shared data structure for communicating energy data between the app and widget
public struct SharedEnergyData: Codable {
	public let todayTotal: Double
	public let moveGoal: Double
	public let todayHourlyData: [SerializableHourlyEnergyData]
	public let latestSampleTimestamp: Date?  // Timestamp of most recent HealthKit sample

	public init(
		todayTotal: Double,
		moveGoal: Double,
		todayHourlyData: [SerializableHourlyEnergyData],
		latestSampleTimestamp: Date? = nil
	) {
		self.todayTotal = todayTotal
		self.moveGoal = moveGoal
		self.todayHourlyData = todayHourlyData
		self.latestSampleTimestamp = latestSampleTimestamp
	}

	/// Codable version of HourlyEnergyData
	public struct SerializableHourlyEnergyData: Codable {
		public let hour: Date
		public let calories: Double

		public init(from hourlyData: HourlyEnergyData) {
			self.hour = hourlyData.hour
			self.calories = hourlyData.calories
		}

		public func toHourlyEnergyData() -> HourlyEnergyData {
			HourlyEnergyData(hour: hour, calories: calories)
		}
	}
}

/// Manager for reading/writing shared energy data to App Group container
public final class SharedEnergyDataManager {
	public static let shared = SharedEnergyDataManager()

	private let appGroupIdentifier = "group.com.healthtrends.shared"
	private let fileName = "energy-data.json"

	private init() {}

	/// Get the shared container URL
	private var sharedContainerURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
	}

	/// Get the file URL for storing energy data
	private var fileURL: URL? {
		sharedContainerURL?.appendingPathComponent(fileName)
	}

	/// Write energy data to shared container
	public func writeEnergyData(
		todayTotal: Double,
		moveGoal: Double,
		todayHourlyData: [HourlyEnergyData],
		latestSampleTimestamp: Date? = nil
	) throws {
		guard let fileURL = fileURL else {
			throw SharedDataError.containerNotFound
		}

		let sharedData = SharedEnergyData(
			todayTotal: todayTotal,
			moveGoal: moveGoal,
			todayHourlyData: todayHourlyData.map { .init(from: $0) },
			latestSampleTimestamp: latestSampleTimestamp
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(sharedData)
		try data.write(to: fileURL, options: .atomic)
	}

	/// Read energy data from shared container
	public func readEnergyData() throws -> SharedEnergyData {
		guard let fileURL = fileURL else {
			throw SharedDataError.containerNotFound
		}

		guard FileManager.default.fileExists(atPath: fileURL.path) else {
			throw SharedDataError.fileNotFound
		}

		let data = try Data(contentsOf: fileURL)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(SharedEnergyData.self, from: data)
	}
}

public enum SharedDataError: Error {
	case containerNotFound
	case fileNotFound
}
