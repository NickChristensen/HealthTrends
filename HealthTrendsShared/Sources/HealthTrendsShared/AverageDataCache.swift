import Foundation
import os

// MARK: - Weekday

/// Represents a weekday for cache indexing (1 = Sunday, 7 = Saturday)
/// Maps to Calendar.component(.weekday, from:) values
public enum Weekday: Int, Codable, CaseIterable, Sendable {
	case sunday = 1
	case monday = 2
	case tuesday = 3
	case wednesday = 4
	case thursday = 5
	case friday = 6
	case saturday = 7

	/// Initialize from a date
	public init?(date: Date, calendar: Calendar = .current) {
		let weekdayComponent = calendar.component(.weekday, from: calendar.startOfDay(for: date))
		self.init(rawValue: weekdayComponent)
	}

	/// Get the current weekday
	public static var today: Weekday {
		Weekday(date: Date())!
	}
}

// MARK: - Average Data Cache

/// Cached average energy data from matching weekday pattern (last ~10 occurrences)
/// Refreshed once per day to minimize expensive HealthKit queries
public struct AverageDataCache: Codable, Sendable {
	public let averageHourlyPattern: [SerializableHourlyEnergyData]
	public let projectedTotal: Double
	public let cachedAt: Date
	public let cacheVersion: Int

	public init(
		averageHourlyPattern: [HourlyEnergyData],
		projectedTotal: Double,
		cachedAt: Date = Date(),
		cacheVersion: Int = 1
	) {
		self.averageHourlyPattern = averageHourlyPattern.map { SerializableHourlyEnergyData(from: $0) }
		self.projectedTotal = projectedTotal
		self.cachedAt = cachedAt
		self.cacheVersion = cacheVersion
	}

	/// Check if cache is stale (from a previous day)
	public var isStale: Bool {
		!Calendar.current.isDate(cachedAt, inSameDayAs: Date())
	}

	/// Convert to HourlyEnergyData array
	public func toHourlyEnergyData() -> [HourlyEnergyData] {
		averageHourlyPattern.map { $0.toHourlyEnergyData() }
	}

	/// Codable version of HourlyEnergyData
	public struct SerializableHourlyEnergyData: Codable, Sendable {
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

// MARK: - Weekday Average Cache

/// Version 2: Weekday-aware average data cache
/// Stores separate average patterns for each weekday to handle weekday-specific activity variations
public struct WeekdayAverageCache: Codable, Sendable {
	/// Dictionary mapping weekday (1-7) to that weekday's average cache
	/// Key: Weekday.rawValue (1=Sunday, 7=Saturday)
	/// Value: Average data calculated from last ~10 occurrences of that weekday
	public let weekdayData: [Int: AverageDataCache]

	/// Cache format version (2 for weekday-aware)
	public let cacheVersion: Int

	public init(weekdayData: [Int: AverageDataCache] = [:], cacheVersion: Int = 2) {
		self.weekdayData = weekdayData
		self.cacheVersion = cacheVersion
	}

	/// Get cache for a specific weekday
	public func cache(for weekday: Weekday) -> AverageDataCache? {
		weekdayData[weekday.rawValue]
	}

	/// Create a new cache with updated data for a specific weekday
	public func updating(cache: AverageDataCache, for weekday: Weekday) -> WeekdayAverageCache {
		var updatedData = weekdayData
		updatedData[weekday.rawValue] = cache
		return WeekdayAverageCache(weekdayData: updatedData, cacheVersion: cacheVersion)
	}
}

// MARK: - Cache Manager

/// Manager for reading/writing average data cache to App Group container
public class AverageDataCacheManager: @unchecked Sendable {
	private let appGroupIdentifier: String
	private let fileName: String
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "AverageDataCacheManager"
	)

	public init(
		appGroupIdentifier: String = "group.com.healthtrends.shared",
		fileName: String = "average-data-cache-v2.json"
	) {
		self.appGroupIdentifier = appGroupIdentifier
		self.fileName = fileName
	}

	/// Get the file URL for storing cache
	private var fileURL: URL? {
		FileManager.default
			.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
			.appendingPathComponent(fileName)
	}

	/// Load cache from disk, returns nil if stale or missing
	public func load() -> AverageDataCache? {
		guard let fileURL = fileURL,
			FileManager.default.fileExists(atPath: fileURL.path)
		else {
			return nil
		}

		do {
			let data = try Data(contentsOf: fileURL)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			let cache = try decoder.decode(AverageDataCache.self, from: data)

			// Return nil if stale
			guard !cache.isStale else {
				Self.logger.info(
					"Average data cache is stale - cached at \(cache.cachedAt, privacy: .public)")
				return nil
			}

			return cache
		} catch {
			Self.logger.error(
				"Failed to load average data cache: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// Save cache to disk
	public func save(_ cache: AverageDataCache) throws {
		guard let fileURL = fileURL else {
			throw CacheError.containerNotFound
		}

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = .prettyPrinted

		let data = try encoder.encode(cache)
		try data.write(to: fileURL, options: .atomic)
	}

	/// Check if cache should be refreshed based on time of day
	/// Returns true if cache is stale or it's morning (6-9 AM) and we haven't refreshed today
	public func shouldRefresh() -> Bool {
		guard let cache = load() else {
			return true  // No cache or stale
		}

		let calendar = Calendar.current
		let now = Date()
		let hour = calendar.component(.hour, from: now)

		// If cache is from yesterday and it's morning, refresh
		if !calendar.isDate(cache.cachedAt, inSameDayAs: now) {
			return hour >= 6  // Don't wake up queries at 3 AM
		}

		return false
	}

	// MARK: - Weekday-Specific API

	/// Load cache for a specific weekday
	/// - Parameter weekday: The weekday to load cache for
	/// - Returns: Cache if available and fresh, nil otherwise
	public func load(for weekday: Weekday) -> AverageDataCache? {
		guard let container = loadContainer() else { return nil }

		let cache = container.cache(for: weekday)

		// Check if cache exists and is not too old (< 30 days)
		if let cache = cache, !isStale(cache) {
			return cache
		}

		return nil
	}

	/// Save cache for a specific weekday
	/// - Parameters:
	///   - cache: The cache data to save
	///   - weekday: The weekday this cache is for
	public func save(_ cache: AverageDataCache, for weekday: Weekday) throws {
		// Load existing container or create new
		let container = loadContainer() ?? WeekdayAverageCache()

		// Update with new weekday data
		let updated = container.updating(cache: cache, for: weekday)

		// Save to disk atomically
		try saveContainer(updated)
	}

	/// Check if cache should be refreshed for a specific weekday
	/// - Parameter weekday: The weekday to check
	/// - Returns: true if cache is missing, stale, or it's morning and cache is from previous occurrence
	public func shouldRefresh(for weekday: Weekday) -> Bool {
		guard let cache = load(for: weekday) else {
			return true  // No cache or stale
		}

		let calendar = Calendar.current
		let now = Date()
		let hour = calendar.component(.hour, from: now)

		// If cache is from a previous occurrence of this weekday and it's morning, refresh
		if !calendar.isDate(cache.cachedAt, inSameDayAs: now) {
			return hour >= 6  // Don't wake up queries at 3 AM
		}

		return false
	}

	// MARK: - Private Helpers

	/// Load the entire weekday cache container from disk
	public func loadContainer() -> WeekdayAverageCache? {
		guard let fileURL = fileURL,
			FileManager.default.fileExists(atPath: fileURL.path)
		else {
			return nil
		}

		do {
			let data = try Data(contentsOf: fileURL)
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			return try decoder.decode(WeekdayAverageCache.self, from: data)
		} catch {
			Self.logger.error(
				"Failed to load weekday cache container: \(error.localizedDescription, privacy: .public)"
			)
			return nil
		}
	}

	/// Save the entire weekday cache container to disk
	private func saveContainer(_ container: WeekdayAverageCache) throws {
		guard let fileURL = fileURL else {
			throw CacheError.containerNotFound
		}

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = .prettyPrinted

		let data = try encoder.encode(container)
		try data.write(to: fileURL, options: .atomic)  // Atomic write for thread safety
	}

	/// Check if a cache entry is stale (older than 30 days)
	private func isStale(_ cache: AverageDataCache) -> Bool {
		let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
		return cache.cachedAt < thirtyDaysAgo
	}

	/// Clear all cached data (useful for testing)
	public func clearCache() {
		guard let fileURL = fileURL else { return }

		try? FileManager.default.removeItem(at: fileURL)
		Self.logger.debug("Cleared average data cache")
	}
}

public enum CacheError: Error {
	case containerNotFound
}
