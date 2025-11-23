import Foundation

/// Cached average energy data from 30-day pattern
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

/// Manager for reading/writing average data cache to App Group container
public final class AverageDataCacheManager: Sendable {
    private let appGroupIdentifier: String
    private let fileName: String

    public init(appGroupIdentifier: String = "group.com.healthtrends.shared", fileName: String = "average-data-cache.json") {
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
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cache = try decoder.decode(AverageDataCache.self, from: data)

            // Return nil if stale
            guard !cache.isStale else {
                return nil
            }

            return cache
        } catch {
            print("Failed to load average data cache: \(error)")
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
}

public enum CacheError: Error {
    case containerNotFound
}
