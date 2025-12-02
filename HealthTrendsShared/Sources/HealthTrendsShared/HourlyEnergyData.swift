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
		// Filter to only on-the-hour data points (exclude interpolated NOW points)
		// Data is already sorted chronologically in the array
		let onTheHourData = self.filter {
			Calendar.current.component(.minute, from: $0.hour) == 0
		}

		guard !onTheHourData.isEmpty else { return nil }

		// Find the two adjacent hourly data points that bracket the target time
		// This automatically handles hour 23 → 0 wraparound via chronological date comparison
		var lowerBound: HourlyEnergyData?
		var upperBound: HourlyEnergyData?

		for data in onTheHourData {
			if data.hour <= date {
				lowerBound = data
			} else {
				upperBound = data
				break
			}
		}

		// Edge cases
		guard let lower = lowerBound else {
			// Before first data point - return first value
			return onTheHourData.first?.calories
		}

		guard let upper = upperBound else {
			// After last data point - return last value
			return onTheHourData.last?.calories
		}

		// Linear interpolation between two points
		let timeRange = upper.hour.timeIntervalSince(lower.hour)
		let timeElapsed = date.timeIntervalSince(lower.hour)
		let progress = timeElapsed / timeRange

		return lower.calories + (upper.calories - lower.calories) * progress
	}
}
