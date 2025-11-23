import Foundation

/// Data model for hourly energy data
/// Represents cumulative calories burned at a specific hour
public struct HourlyEnergyData: Identifiable, Sendable {
    public let id = UUID()
    public let hour: Date
    public let calories: Double

    public init(hour: Date, calories: Double) {
        self.hour = hour
        self.calories = calories
    }
}

// MARK: - Interpolation Helpers

extension Array where Element == HourlyEnergyData {
    /// Interpolate the calorie value at a specific time based on hourly data
    /// - Parameter date: The date/time to interpolate at
    /// - Returns: Interpolated calorie value, or nil if insufficient data
    public func interpolatedValue(at date: Date) -> Double? {
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)

        // Find the average values for current hour and next hour
        guard let currentHourData = self.first(where: {
            calendar.component(.hour, from: $0.hour) == currentHour
        }), let nextHourData = self.first(where: {
            calendar.component(.hour, from: $0.hour) == currentHour + 1
        }) else {
            return nil
        }

        // Interpolate based on minutes into the hour
        let progress = Double(currentMinute) / 60.0
        return currentHourData.calories + (nextHourData.calories - currentHourData.calories) * progress
    }
}
