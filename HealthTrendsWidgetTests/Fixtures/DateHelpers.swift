import Foundation

/// Date construction utilities for deterministic test data
enum DateHelpers {
	/// Create a date for a specific weekday, hour, and minute
	/// - Parameters:
	///   - weekday: Day of week (1=Sunday, 2=Monday, ..., 7=Saturday)
	///   - hour: Hour in 24-hour format (0-23)
	///   - minute: Minute (0-59)
	///   - weeksAgo: How many weeks in the past (0 = current week)
	///   - referenceDate: Base date for calculations (defaults to current time)
	/// - Returns: Date matching the specified criteria
	static func createDate(weekday: Int, hour: Int, minute: Int, weeksAgo: Int = 0, from referenceDate: Date? = nil) -> Date {
		let calendar = Calendar.current
		let baseDate = referenceDate ?? Date()

		// Find the most recent occurrence of the target weekday
		var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: baseDate)
		components.weekday = weekday
		components.hour = hour
		components.minute = minute
		components.second = 0
		components.nanosecond = 0

		guard let targetDate = calendar.date(from: components) else {
			fatalError("Failed to create date for weekday \(weekday), hour \(hour), minute \(minute)")
		}

		// If we need to go back weeks
		if weeksAgo > 0 {
			guard let pastDate = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: targetDate) else {
				fatalError("Failed to subtract \(weeksAgo) weeks from date")
			}
			return pastDate
		}

		return targetDate
	}

	/// Create a Saturday at specific time
	/// - Parameters:
	///   - hour: Hour in 24-hour format (0-23)
	///   - minute: Minute (0-59)
	///   - weeksAgo: How many weeks in the past (0 = current week)
	/// - Returns: Saturday date at specified time
	static func createSaturday(hour: Int, minute: Int, weeksAgo: Int = 0) -> Date {
		createDate(weekday: 7, hour: hour, minute: minute, weeksAgo: weeksAgo)
	}

	/// Create a Friday at specific time
	/// - Parameters:
	///   - hour: Hour in 24-hour format (0-23)
	///   - minute: Minute (0-59)
	///   - weeksAgo: How many weeks in the past (0 = current week)
	/// - Returns: Friday date at specified time
	static func createFriday(hour: Int, minute: Int, weeksAgo: Int = 0) -> Date {
		createDate(weekday: 6, hour: hour, minute: minute, weeksAgo: weeksAgo)
	}

	/// Get start of day (midnight) for a given date
	/// - Parameter date: Source date
	/// - Returns: Midnight on the same calendar day
	static func startOfDay(for date: Date) -> Date {
		Calendar.current.startOfDay(for: date)
	}

	/// Get end of day (just before midnight next day) for a given date
	/// - Parameter date: Source date
	/// - Returns: 23:59:59 on the same calendar day
	static func endOfDay(for date: Date) -> Date {
		let calendar = Calendar.current
		let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay(for: date))!
		return calendar.date(byAdding: .second, value: -1, to: startOfNextDay)!
	}

	/// Create a date at a specific hour on the same day as the reference date
	/// - Parameters:
	///   - hour: Hour in 24-hour format (0-23)
	///   - minute: Minute (0-59)
	///   - referenceDate: Base date to use for year/month/day
	/// - Returns: Date at specified time on same calendar day
	static func timeOnSameDay(hour: Int, minute: Int, as referenceDate: Date) -> Date {
		let calendar = Calendar.current
		var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
		components.hour = hour
		components.minute = minute
		components.second = 0
		components.nanosecond = 0

		guard let date = calendar.date(from: components) else {
			fatalError("Failed to create time \(hour):\(minute) on date \(referenceDate)")
		}

		return date
	}
}
