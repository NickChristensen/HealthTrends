import Foundation
import HealthKit
import os

/// Shared HealthKit query service for use by both app and widget
/// Provides efficient queries for energy data
/// Conforms to HealthDataProvider protocol for dependency injection and testing
public final class HealthKitQueryService: HealthDataProvider {
	private let healthStore: HKHealthStore
	private let calendar: Calendar
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "HealthKitQueryService"
	)

	public init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
		self.healthStore = healthStore
		self.calendar = calendar
	}

	// MARK: - Public API

	/// Check if HealthKit read authorization is likely granted
	/// Returns true if samples found (permission likely granted), false if no samples (permission likely denied or no data)
	/// Note: HealthKit privacy protections mean denied read permissions don't throw errors -
	/// they just return empty results. We use a heuristic: if user has any active energy data
	/// in last 30 days, assume permission granted. If 0 samples, assume permission denied.
	public func checkReadAuthorization() async -> Bool {
		let queryStartTime = Date()

		guard HKHealthStore.isHealthDataAvailable() else {
			Self.logger.warning(
				"HealthKit not available on this device (watchOS/iPad without health support)")
			return false
		}

		let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

		// Query for samples from last 30 days (wider window to catch data)
		let now = Date()
		guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else {
			Self.logger.error("Failed to calculate date 30 days ago - calendar computation error")
			return false
		}

		Self.logger.info(
			"Starting authorization check: querying last 30 days (\(thirtyDaysAgo, privacy: .public) to \(now, privacy: .public))"
		)

		let predicate = HKQuery.predicateForSamples(
			withStart: thirtyDaysAgo, end: now, options: .strictStartDate)

		do {
			let samples = try await withCheckedThrowingContinuation {
				(continuation: CheckedContinuation<[HKQuantitySample], Error>) in
				let query = HKSampleQuery(
					sampleType: activeEnergyType,
					predicate: predicate,
					limit: 1,
					sortDescriptors: [
						NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
					]
				) { _, samples, error in
					if let error = error {
						continuation.resume(throwing: error)
						return
					}
					continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
				}
				healthStore.execute(query)
			}

			let queryDuration = Date().timeIntervalSince(queryStartTime)
			let sampleCount = samples.count

			if sampleCount > 0 {
				// Authorization likely granted
				let latestSample = samples[0]
				let sampleDate = latestSample.startDate
				let sampleAge = now.timeIntervalSince(sampleDate)
				let calories = latestSample.quantity.doubleValue(for: .kilocalorie())

				Self.logger.info(
					"✅ Authorization check PASSED: found \(sampleCount) sample(s) in last 30 days")
				Self.logger.info("   Query duration: \(Int(queryDuration * 1000))ms")
				Self.logger.info(
					"   Latest sample: \(sampleDate, privacy: .public) (\(Int(sampleAge/3600))h ago, \(calories, privacy: .public) kcal)"
				)
				return true
			} else {
				// No samples found - either unauthorized OR user has no data
				Self.logger.warning("⚠️ Authorization check FAILED: no samples found in last 30 days")
				Self.logger.warning("   Query duration: \(Int(queryDuration * 1000))ms")
				Self.logger.warning(
					"   Date range: \(thirtyDaysAgo, privacy: .public) to \(now, privacy: .public)")
				Self.logger.warning(
					"   ⚠️ FALSE NEGATIVE POSSIBLE: User may have granted permission but has no data!"
				)
				Self.logger.warning(
					"   Recommendation: Check HealthKit authorization status in Settings > Privacy > Health"
				)
				return false
			}
		} catch {
			let queryDuration = Date().timeIntervalSince(queryStartTime)

			Self.logger.error(
				"❌ Authorization check FAILED with error after \(Int(queryDuration * 1000))ms")
			Self.logger.error("   Error: \(error.localizedDescription, privacy: .public)")
			Self.logger.error("   Error type: \(String(describing: type(of: error)), privacy: .public)")

			// Check for specific error types
			let nsError = error as NSError
			Self.logger.error("   Error domain: \(nsError.domain, privacy: .public)")
			Self.logger.error("   Error code: \(nsError.code)")

			if nsError.domain == "com.apple.healthkit" {
				switch nsError.code {
				case 5:  // HKErrorAuthorizationNotDetermined
					Self.logger.error(
						"   → Authorization not determined (user hasn't granted permission)")
				case 6:  // HKErrorAuthorizationDenied
					Self.logger.error("   → Authorization explicitly denied by user")
				default:
					Self.logger.error("   → Unknown HealthKit error code: \(nsError.code)")
				}
			}

			return false
		}
	}

	/// Fetch today's hourly energy breakdown
	/// Returns tuple of:
	/// - data: Cumulative calories at each hour boundary
	/// - latestSampleTimestamp: Timestamp of most recent HealthKit sample (nil if no samples)
	public func fetchTodayHourlyTotals() async throws -> (data: [HourlyEnergyData], latestSampleTimestamp: Date?) {
		let now = Date()
		let startOfDay = calendar.startOfDay(for: now)

		let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

		// Fetch hourly data (non-cumulative) and latest sample timestamp
		let (hourlyData, latestSampleTimestamp) = try await fetchHourlyData(
			from: startOfDay, to: now, type: activeEnergyType)

		let currentHourStart = calendar.dateInterval(of: .hour, for: now)!.start

		// Filter out current incomplete hour for completed hours
		let completeHours = hourlyData.filter { $0.hour < currentHourStart }

		// Convert to cumulative data (running sum)
		var cumulativeData: [HourlyEnergyData] = []

		// Start with 0 at midnight
		cumulativeData.append(HourlyEnergyData(hour: startOfDay, calories: 0))

		var runningTotal: Double = 0
		for data in completeHours.sorted(by: { $0.hour < $1.hour }) {
			runningTotal += data.calories
			// Use end of hour for timestamp
			let timestamp = calendar.date(byAdding: .hour, value: 1, to: data.hour)!
			cumulativeData.append(HourlyEnergyData(hour: timestamp, calories: runningTotal))
		}

		// Add current hour progress (timestamp = current time, not end of hour)
		let currentHourCalories = hourlyData.first(where: { $0.hour == currentHourStart })?.calories ?? 0

		if currentHourCalories > 0 {
			let total = runningTotal + currentHourCalories
			cumulativeData.append(HourlyEnergyData(hour: now, calories: total))
		}

		return (cumulativeData, latestSampleTimestamp)
	}

	/// Fetch average Active Energy data from past occurrences of the current weekday
	/// Returns "Total" and "Average" (see CLAUDE.md)
	/// Uses last 10 occurrences of today's weekday (e.g., if today is Saturday, uses last 10 Saturdays)
	public func fetchAverageData(for weekday: Int? = nil) async throws -> (
		total: Double, hourlyData: [HourlyEnergyData]
	) {
		let now = Date()
		let startOfToday = calendar.startOfDay(for: now)

		// Get current weekday (or use provided weekday)
		let targetWeekday = weekday ?? calendar.component(.weekday, from: startOfToday)

		// Get data from 70 days ago to yesterday (ensures at least 10 occurrences of each weekday)
		guard let seventyDaysAgo = calendar.date(byAdding: .day, value: -70, to: startOfToday),
			let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)
		else {
			return (0, [])
		}

		let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

		// Fetch daily totals for "Total" metric, filtered by weekday
		let dailyTotals = try await fetchDailyTotals(
			from: seventyDaysAgo, to: yesterday, type: activeEnergyType, filterWeekday: targetWeekday)
		let projectedTotal = dailyTotals.isEmpty ? 0 : dailyTotals.reduce(0, +) / Double(dailyTotals.count)

		// Fetch cumulative average hourly pattern, filtered by weekday
		let averageHourlyData = try await fetchCumulativeAverageHourlyPattern(
			from: seventyDaysAgo, to: yesterday, type: activeEnergyType, filterWeekday: targetWeekday)

		return (projectedTotal, averageHourlyData)
	}

	/// Fetch today's active energy goal from Activity Summary
	/// iOS supports weekday-specific goals, so this must be queried fresh each day
	/// Returns 0 if no goal is set or if running on simulator
	public func fetchMoveGoal() async throws -> Double {
		#if targetEnvironment(simulator)
			// Simulator doesn't have Fitness app, return mock goal
			return 800.0
		#else
			let now = Date()

			// Create predicate for today's activity summary
			var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
			dateComponents.calendar = calendar

			let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

			let activitySummary = try await withCheckedThrowingContinuation {
				(continuation: CheckedContinuation<HKActivitySummary?, Error>) in
				let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
					if let error = error {
						continuation.resume(throwing: error)
						return
					}
					continuation.resume(returning: summaries?.first)
				}
				healthStore.execute(query)
			}

			// Extract the active energy burned goal
			if let summary = activitySummary {
				let goalInKilocalories = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
				return goalInKilocalories > 0 ? goalInKilocalories : 0
			}

			// No summary available - return 0
			return 0
		#endif
	}

	// MARK: - Private Helpers

	/// Fetch hourly data for a specific time range
	private func fetchHourlyData(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws
		-> (data: [HourlyEnergyData], latestSampleTimestamp: Date?)
	{
		let predicate = HKQuery.predicateForSamples(
			withStart: startDate, end: endDate, options: .strictStartDate)

		var hourlyTotals: [Date: Double] = [:]
		var latestSampleTimestamp: Date? = nil

		let samples = try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<[HKQuantitySample], Error>) in
			let query = HKSampleQuery(
				sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
				sortDescriptors: nil
			) { _, samples, error in
				if let error = error {
					continuation.resume(throwing: error)
					return
				}
				continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
			}
			healthStore.execute(query)
		}

		// Group by hour and track latest sample timestamp
		for sample in samples {
			let hourStart =
				calendar.dateInterval(of: .hour, for: sample.startDate)?.start ?? sample.startDate
			let calories = sample.quantity.doubleValue(for: .kilocalorie())
			hourlyTotals[hourStart, default: 0] += calories

			// Track latest sample (use endDate for accuracy)
			if let currentLatest = latestSampleTimestamp {
				latestSampleTimestamp = max(currentLatest, sample.endDate)
			} else {
				latestSampleTimestamp = sample.endDate
			}
		}

		// Convert to array and sort
		let data = hourlyTotals.map { HourlyEnergyData(hour: $0.key, calories: $0.value) }
			.sorted { $0.hour < $1.hour }

		return (data, latestSampleTimestamp)
	}

	/// Fetch daily totals for a date range
	/// If filterWeekday is provided, only includes days matching that weekday (1 = Sunday, 7 = Saturday)
	private func fetchDailyTotals(
		from startDate: Date, to endDate: Date, type: HKQuantityType, filterWeekday: Int? = nil
	) async throws -> [Double] {
		let predicate = HKQuery.predicateForSamples(
			withStart: startDate, end: endDate, options: .strictStartDate)

		var dailyTotals: [Date: Double] = [:]

		let samples = try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<[HKQuantitySample], Error>) in
			let query = HKSampleQuery(
				sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
				sortDescriptors: nil
			) { _, samples, error in
				if let error = error {
					continuation.resume(throwing: error)
					return
				}
				continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
			}
			healthStore.execute(query)
		}

		// Group by day
		for sample in samples {
			let dayStart = calendar.startOfDay(for: sample.startDate)

			// Filter by weekday if specified
			if let filterWeekday = filterWeekday {
				let weekday = calendar.component(.weekday, from: dayStart)
				guard weekday == filterWeekday else { continue }
			}

			let calories = sample.quantity.doubleValue(for: .kilocalorie())
			dailyTotals[dayStart, default: 0] += calories
		}

		return Array(dailyTotals.values)
	}

	/// Fetch cumulative average hourly pattern across multiple days
	/// If filterWeekday is provided, only includes days matching that weekday (1 = Sunday, 7 = Saturday)
	private func fetchCumulativeAverageHourlyPattern(
		from startDate: Date, to endDate: Date, type: HKQuantityType, filterWeekday: Int? = nil
	) async throws -> [HourlyEnergyData] {
		let predicate = HKQuery.predicateForSamples(
			withStart: startDate, end: endDate, options: .strictStartDate)

		let samples = try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<[HKQuantitySample], Error>) in
			let query = HKSampleQuery(
				sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
				sortDescriptors: nil
			) { _, samples, error in
				if let error = error {
					continuation.resume(throwing: error)
					return
				}
				continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
			}
			healthStore.execute(query)
		}

		// Group samples by day, then calculate cumulative totals for each day
		var dailyCumulativeData: [Date: [Int: Double]] = [:]  // [dayStart: [hour: cumulativeCalories]]

		for sample in samples {
			let dayStart = calendar.startOfDay(for: sample.startDate)

			// Filter by weekday if specified
			if let filterWeekday = filterWeekday {
				let weekday = calendar.component(.weekday, from: dayStart)
				guard weekday == filterWeekday else { continue }
			}

			let hour = calendar.component(.hour, from: sample.startDate)
			let calories = sample.quantity.doubleValue(for: .kilocalorie())

			if dailyCumulativeData[dayStart] == nil {
				dailyCumulativeData[dayStart] = [:]
			}
			dailyCumulativeData[dayStart]![hour, default: 0] += calories
		}

		// Convert each day's hourly data to cumulative
		var dailyCumulative: [Date: [Int: Double]] = [:]  // [dayStart: [hour: cumulativeTotalByHour]]

		for (dayStart, hourlyData) in dailyCumulativeData {
			var runningTotal: Double = 0
			var cumulativeByHour: [Int: Double] = [:]

			// Sort hours and calculate cumulative
			for hour in 0..<24 {
				runningTotal += hourlyData[hour] ?? 0
				cumulativeByHour[hour] = runningTotal
			}

			dailyCumulative[dayStart] = cumulativeByHour
		}

		// For each hour, average the cumulative totals across all days
		var averageCumulativeByHour: [Int: Double] = [:]

		for hour in 0..<24 {
			var totalForHour: Double = 0
			var count = 0

			for (_, cumulativeByHour) in dailyCumulative {
				if let cumulativeAtHour = cumulativeByHour[hour], cumulativeAtHour > 0 {
					totalForHour += cumulativeAtHour
					count += 1
				}
			}

			averageCumulativeByHour[hour] = count > 0 ? totalForHour / Double(count) : 0
		}

		// Convert to HourlyEnergyData
		let now = Date()
		let startOfToday = calendar.startOfDay(for: now)
		let currentHour = calendar.component(.hour, from: now)
		let currentMinute = calendar.component(.minute, from: now)

		var hourlyData: [HourlyEnergyData] = []

		// Start with 0 at midnight
		hourlyData.append(HourlyEnergyData(hour: startOfToday, calories: 0))

		// Timestamps represent END of hour
		hourlyData.append(
			contentsOf: averageCumulativeByHour.map { hour, avgCumulative in
				let hourDate = calendar.date(byAdding: .hour, value: hour + 1, to: startOfToday)!
				return HourlyEnergyData(hour: hourDate, calories: avgCumulative)
			}.sorted { $0.hour < $1.hour })

		// Add interpolated NOW point for real-time average
		let avgAtCurrentHour = averageCumulativeByHour[currentHour] ?? 0
		let avgAtNextHour = averageCumulativeByHour[currentHour + 1] ?? avgAtCurrentHour
		let interpolationFactor = Double(currentMinute) / 60.0
		let avgAtNow = avgAtCurrentHour + (avgAtNextHour - avgAtCurrentHour) * interpolationFactor

		if avgAtNow > 0 {
			hourlyData.append(HourlyEnergyData(hour: now, calories: avgAtNow))
		}

		return hourlyData
	}
}
