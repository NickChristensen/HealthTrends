import Foundation

/// Shared data structure for communicating energy data between the app and widget
struct SharedEnergyData: Codable {
    let todayTotal: Double
    let averageAtCurrentHour: Double
    let projectedTotal: Double
    let moveGoal: Double
    let todayHourlyData: [SerializableHourlyEnergyData]
    let averageHourlyData: [SerializableHourlyEnergyData]
    let lastUpdated: Date

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
        averageAtCurrentHour: Double,
        projectedTotal: Double,
        moveGoal: Double,
        todayHourlyData: [HourlyEnergyData],
        averageHourlyData: [HourlyEnergyData]
    ) throws {
        guard let fileURL = fileURL else {
            throw SharedDataError.containerNotFound
        }

        let sharedData = SharedEnergyData(
            todayTotal: todayTotal,
            averageAtCurrentHour: averageAtCurrentHour,
            projectedTotal: projectedTotal,
            moveGoal: moveGoal,
            todayHourlyData: todayHourlyData.map { .init(from: $0) },
            averageHourlyData: averageHourlyData.map { .init(from: $0) },
            lastUpdated: Date()
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
