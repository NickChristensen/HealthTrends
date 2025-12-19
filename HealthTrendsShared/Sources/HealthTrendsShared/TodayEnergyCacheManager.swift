import Foundation

/// Cache structure for today's energy data shared between app and widget
public struct TodayEnergyCache: Codable {
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

/// Manager for reading/writing today's energy cache to App Group container
public final class TodayEnergyCacheManager {
	public static let shared = TodayEnergyCacheManager()

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
			throw TodayEnergyCacheError.containerNotFound
		}

		let cache = TodayEnergyCache(
			todayTotal: todayTotal,
			moveGoal: moveGoal,
			todayHourlyData: todayHourlyData.map { .init(from: $0) },
			latestSampleTimestamp: latestSampleTimestamp
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let data = try encoder.encode(cache)
		try data.write(to: fileURL, options: .atomic)
	}

	/// Read energy data from shared container
	public func readEnergyData() throws -> TodayEnergyCache {
		guard let fileURL = fileURL else {
			throw TodayEnergyCacheError.containerNotFound
		}

		guard FileManager.default.fileExists(atPath: fileURL.path) else {
			throw TodayEnergyCacheError.fileNotFound
		}

		let data = try Data(contentsOf: fileURL)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(TodayEnergyCache.self, from: data)
	}

	/// Clear cached energy data (primarily for testing)
	public func clearCache() {
		guard let fileURL = fileURL else { return }
		try? FileManager.default.removeItem(at: fileURL)
	}
}

public enum TodayEnergyCacheError: Error {
	case containerNotFound
	case fileNotFound
}
