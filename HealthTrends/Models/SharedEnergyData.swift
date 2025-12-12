import Foundation
import HealthTrendsShared

/// Shared data structure for communicating energy data between the app and widget
struct SharedEnergyData: Codable {
	let todayTotal: Double
	let moveGoal: Double
	let todayHourlyData: [SerializableHourlyEnergyData]
	let latestSampleTimestamp: Date?  // Timestamp of most recent HealthKit sample

	/// Creates a SharedEnergyData instance with validation
	///
	/// - Parameters:
	///   - todayTotal: Total calories burned today (must be non-negative)
	///   - moveGoal: Daily move goal in calories (must be non-negative)
	///   - todayHourlyData: Array of hourly energy data (must be cumulative/monotonic)
	///   - latestSampleTimestamp: Timestamp of most recent HealthKit sample
	///
	/// - Precondition: todayTotal must be non-negative
	/// - Precondition: moveGoal must be non-negative
	/// - Precondition: Hourly data must be monotonically increasing (cumulative)
	/// - Precondition: todayTotal must match the last hourly value when hourly data exists
	/// - Precondition: todayTotal must be 0 when hourly data is empty
	init(
		todayTotal: Double,
		moveGoal: Double,
		todayHourlyData: [SerializableHourlyEnergyData],
		latestSampleTimestamp: Date? = nil
	) {
		precondition(todayTotal >= 0, "todayTotal must be non-negative")
		precondition(moveGoal >= 0, "moveGoal must be non-negative")

		// Validate hourly data is monotonically increasing (cumulative)
		for i in 1..<todayHourlyData.count {
			let previous = todayHourlyData[i - 1].calories
			let current = todayHourlyData[i].calories
			precondition(
				current >= previous,
				"Hourly data must be cumulative: hour \(i) has \(current) cal, but previous hour had \(previous) cal"
			)
		}

		if let lastHourCalories = todayHourlyData.last?.calories {
			precondition(
				abs(lastHourCalories - todayTotal) < 0.01,
				"todayTotal (\(todayTotal)) must match last hourly value (\(lastHourCalories))"
			)
		} else {
			precondition(abs(todayTotal) < 0.01, "todayTotal must be 0 when hourly data is empty")
		}

		self.todayTotal = todayTotal
		self.moveGoal = moveGoal
		self.todayHourlyData = todayHourlyData
		self.latestSampleTimestamp = latestSampleTimestamp
	}

	/// Custom Decodable implementation to ensure validation during JSON decoding
	///
	/// This ensures that validation rules are enforced even when loading data from
	/// the shared container, not just when creating instances programmatically.
	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let todayTotal = try container.decode(Double.self, forKey: .todayTotal)
		let moveGoal = try container.decode(Double.self, forKey: .moveGoal)
		let todayHourlyData = try container.decode(
			[SerializableHourlyEnergyData].self, forKey: .todayHourlyData)
		let latestSampleTimestamp = try container.decodeIfPresent(Date.self, forKey: .latestSampleTimestamp)

		// Call the validated initializer
		self.init(
			todayTotal: todayTotal,
			moveGoal: moveGoal,
			todayHourlyData: todayHourlyData,
			latestSampleTimestamp: latestSampleTimestamp
		)
	}

	private enum CodingKeys: String, CodingKey {
		case todayTotal
		case moveGoal
		case todayHourlyData
		case latestSampleTimestamp
	}

	/// Codable version of HourlyEnergyData
	struct SerializableHourlyEnergyData: Codable {
		let hour: Date
		let calories: Double

		init(from hourlyData: HourlyEnergyData) {
			self.hour = hourlyData.hour
			self.calories = hourlyData.calories
		}

		func toHourlyEnergyData() -> HourlyEnergyData {
			HourlyEnergyData(hour: hour, calories: calories)
		}
	}
}

/// Manager for reading/writing shared energy data to App Group container
final class SharedEnergyDataManager {
	static let shared = SharedEnergyDataManager()

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
	func writeEnergyData(
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
	func readEnergyData() throws -> SharedEnergyData {
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

enum SharedDataError: Error {
	case containerNotFound
	case fileNotFound
}
