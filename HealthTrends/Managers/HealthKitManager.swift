import Foundation
import HealthKit
import HealthTrendsShared
import WidgetKit

@MainActor
@Observable
final class HealthKitManager {
	private let healthStore = HKHealthStore()
	private let moveGoalCacheKey = "cachedMoveGoal"

	var isAuthorized = false
	var todayTotal: Double = 0
	var averageAtCurrentHour: Double = 0  // Average cumulative calories BY current hour (see CLAUDE.md)
	var projectedTotal: Double = 0  // Average of complete daily totals (see CLAUDE.md)
	var moveGoal: Double = 0  // Daily Move goal from Fitness app
	var todayHourlyData: [HourlyEnergyData] = []
	var averageHourlyData: [HourlyEnergyData] = []
	private(set) var latestSampleTimestamp: Date? = nil  // Timestamp of most recent HealthKit sample
	private(set) var refreshCount: Int = 0  // Increments on each refresh to force UI updates

	init() {
		// Load cached move goal on initialization
		self.moveGoal = loadCachedMoveGoal()
	}

	// Check if HealthKit is available on this device
	var isHealthKitAvailable: Bool {
		HKHealthStore.isHealthDataAvailable()
	}

	// MARK: - Move Goal Caching

	/// Load cached move goal from UserDefaults
	private func loadCachedMoveGoal() -> Double {
		UserDefaults.standard.double(forKey: moveGoalCacheKey)
	}

	/// Save move goal to UserDefaults
	private func cacheMoveGoal(_ goal: Double) {
		UserDefaults.standard.set(goal, forKey: moveGoalCacheKey)
	}

	// Request authorization to read Active Energy data
	// Write authorization is requested separately when generating sample data
	func requestAuthorization() async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
		let activitySummaryType = HKObjectType.activitySummaryType()

		let typesToRead: Set<HKObjectType> = [activeEnergyType, activitySummaryType]

		// Request read permissions
		try await healthStore.requestAuthorization(toShare: [], read: typesToRead)

		// Verify permission via hybrid approach (cache + query)
		isAuthorized = await verifyReadAuthorization()

		// If authorized, fetch data immediately to populate cache and show user data
		if isAuthorized {
			print("✅ Authorization verified - fetching initial data")
			do {
				try await fetchEnergyData()
				print("✅ Initial data fetch successful")

				// Populate all 7 weekday caches for complete widget fallback coverage
				await populateWeekdayCaches()
			} catch {
				// Don't throw - authorization succeeded even if data fetch failed
				// User might have no data yet, or device might be locked
				print("⚠️ Initial data fetch failed (non-fatal): \(error.localizedDescription)")
			}
		}
	}

	/// Verify read authorization using hybrid approach
	/// Fast path: Check cache (instant verification if data was previously fetched)
	/// Query path: Perform minimal HealthKit query to detect actual permission state
	private func verifyReadAuthorization() async -> Bool {
		// FAST PATH: Check cache first (existing behavior when it works)
		do {
			let _ = try SharedEnergyDataManager.shared.readEnergyData()
			print("✅ Cache exists - authorization verified (fast path)")
			return true
		} catch SharedDataError.fileNotFound {
			// Cache doesn't exist - need to query HealthKit directly
			print("⚠️ No cache found - checking HealthKit directly (query path)")
		} catch SharedDataError.containerNotFound {
			// App group configuration error
			print("❌ App group container not found - configuration error")
			return false
		} catch {
			// Other cache error (corruption, decode failure) - fall through to query
			print("⚠️ Cache read error: \(error.localizedDescription) - trying query path")
		}

		// QUERY PATH: Use HealthKitQueryService to check permission
		let queryService = HealthKitQueryService(healthStore: healthStore)
		let isAuthorized = await queryService.checkReadAuthorization()

		if isAuthorized {
			print("✅ HealthKit query succeeded - permission granted")
		} else {
			print("❌ HealthKit query failed - permission likely denied or no data")
		}

		return isAuthorized
	}

	/// Check current authorization status
	/// Call when app returns from background to detect if user revoked permission
	func checkAuthorizationStatus() async {
		isAuthorized = await verifyReadAuthorization()
	}

	/// Request write authorization for development/testing purposes
	/// Called on-demand when user generates sample data
	func requestWriteAuthorization() async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
		let typesToWrite: Set<HKSampleType> = [activeEnergyType]

		// Request write permission only
		try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
	}

	// Delete all existing Active Energy data
	func clearSampleData() async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!

		// Delete all samples from our app
		let predicate = HKQuery.predicateForObjects(from: [HKSource.default()])
		try await healthStore.deleteObjects(of: activeEnergyType, predicate: predicate)
	}

	// Generate realistic sample Active Energy data
	// dataAge: How far back from current time to generate data (in seconds). Default 0 = up to current time.
	func generateSampleData(dataAge: TimeInterval = 0) async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		// Request write permission before attempting to write
		try await requestWriteAuthorization()

		// Clear existing data first to avoid duplicates
		try await clearSampleData()

		let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
		let calendar = Calendar.current
		let now = Date()
		let effectiveNow = now.addingTimeInterval(-dataAge)

		// Generate data for the past 60 days
		var samplesToSave: [HKQuantitySample] = []

		for dayOffset in 0..<60 {
			guard
				let dayStart = calendar.date(
					byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now))
			else {
				continue
			}

			// For today (dayOffset == 0), only generate up to effectiveNow
			// For past days, generate all 24 hours
			let currentHour = calendar.component(.hour, from: effectiveNow)
			let currentMinute = calendar.component(.minute, from: effectiveNow)
			let maxHour = dayOffset == 0 ? currentHour : 23

			// Generate hourly data points for each day
			for hour in 0...maxHour {
				guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else {
					continue
				}

				// Don't generate data beyond effectiveNow
				guard hourStart <= effectiveNow else {
					continue
				}

				// For the current hour on today, check if we need a partial hour or full hour
				let isCurrentHour = (dayOffset == 0 && hour == currentHour)
				let hourEnd: Date

				if isCurrentHour && currentMinute > 0 {
					// Generate partial hour up to the exact minute
					hourEnd = effectiveNow
				} else {
					// Generate full hour
					hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart)!
				}

				// Generate realistic calories per hour (prorated if partial)
				let baseCalories = generateRealisticCalories(for: hour)
				let calories: Double

				if isCurrentHour && currentMinute > 0 {
					// Prorate calories based on fraction of hour
					let fractionOfHour = Double(currentMinute) / 60.0
					calories = (baseCalories + Double.random(in: -10...10)) * fractionOfHour
				} else {
					calories = baseCalories + Double.random(in: -10...10)
				}

				let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: max(0, calories))
				let sample = HKQuantitySample(
					type: activeEnergyType,
					quantity: quantity,
					start: hourStart,
					end: hourEnd
				)

				samplesToSave.append(sample)
			}
		}

		try await healthStore.save(samplesToSave)
	}

	// Generate realistic calorie burn based on time of day
	private func generateRealisticCalories(for hour: Int) -> Double {
		switch hour {
		case 0..<6: return Double.random(in: 5...15)  // Sleep/early morning
		case 6..<7: return Double.random(in: 20...40)  // Wake up
		case 7: return Double.random(in: 150...250)  // Morning workout
		case 8..<9: return Double.random(in: 20...40)  // Post-workout
		case 9..<12: return Double.random(in: 25...50)  // Morning activity
		case 12..<14: return Double.random(in: 30...60)  // Lunch/midday
		case 14..<17: return Double.random(in: 25...55)  // Afternoon
		case 17..<20: return Double.random(in: 35...70)  // Evening activity
		case 20..<22: return Double.random(in: 20...40)  // Evening
		default: return Double.random(in: 10...20)  // Late night
		}
	}

	// MARK: - Data Fetching

	// Fetch all Active Energy data
	func fetchEnergyData() async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		async let todayData = fetchTodayData()
		async let averageData = fetchAverageData()
		async let _ = fetchMoveGoal()  // Fetches and updates self.moveGoal as side effect

		let (today, average) = try await (todayData, averageData)

		self.todayTotal = today.total
		self.todayHourlyData = today.hourlyData
		self.latestSampleTimestamp = today.latestSampleTimestamp
		self.projectedTotal = average.total
		self.averageHourlyData = average.hourlyData

		// Calculate interpolated average at current minute
		self.averageAtCurrentHour = average.hourlyData.interpolatedValue(at: Date()) ?? 0

		// Increment refresh counter to force UI redraw (updates NOW label even if data unchanged)
		self.refreshCount += 1

		// Write today's data to shared container for widget fallback
		try? SharedEnergyDataManager.shared.writeEnergyData(
			todayTotal: self.todayTotal,
			moveGoal: self.moveGoal,
			todayHourlyData: self.todayHourlyData,
			latestSampleTimestamp: self.latestSampleTimestamp
		)

		// Write average data to weekday-specific cache for widget (refreshed daily)
		let weekday = Weekday.today
		let cache = AverageDataCache(
			averageHourlyPattern: self.averageHourlyData,
			projectedTotal: self.projectedTotal,
			cachedAt: Date(),
			cacheVersion: 1
		)
		try? AverageDataCacheManager().save(cache, for: weekday)

		// Reload widget timelines to pick up fresh data
		WidgetCenter.shared.reloadAllTimelines()
	}

	// Fetch Move goal from Activity Summary
	// iOS supports weekday-specific goals, so this must be called regularly (not just once)
	func fetchMoveGoal() async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		let queryService = HealthKitQueryService(healthStore: healthStore)
		let goal = try await queryService.fetchMoveGoal()

		// Only update if we got a valid goal (> 0)
		if goal > 0 {
			self.moveGoal = goal
			cacheMoveGoal(goal)
		}
		// If goal is 0, keep cached value (don't overwrite with 0)
	}

	// Fetch today's Active Energy data
	// Returns cumulative calories at each hour (see CLAUDE.md for "Today" definition)
	private func fetchTodayData() async throws -> (
		total: Double, hourlyData: [HourlyEnergyData], latestSampleTimestamp: Date?
	) {
		// Use shared query service to get hourly data and latest sample timestamp
		let queryService = HealthKitQueryService(healthStore: healthStore)
		let (cumulativeData, latestSampleTimestamp) = try await queryService.fetchTodayHourlyTotals()

		// Total is the last data point's calories (cumulative)
		let total = cumulativeData.last?.calories ?? 0

		return (total, cumulativeData, latestSampleTimestamp)
	}

	// Fetch average Active Energy data from past occurrences of the current weekday
	// Returns "Total" and "Average" (see CLAUDE.md)
	// Uses last 10 occurrences of today's weekday (e.g., if today is Saturday, uses last 10 Saturdays)
	private func fetchAverageData(for weekday: Int? = nil) async throws -> (
		total: Double, hourlyData: [HourlyEnergyData]
	) {
		let calendar = Calendar.current
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

		// Fetch daily totals for "Total" metric (average of complete daily totals), filtered by weekday
		let dailyTotals = try await fetchDailyTotals(
			from: seventyDaysAgo, to: yesterday, type: activeEnergyType, filterWeekday: targetWeekday)
		let projectedTotal = dailyTotals.isEmpty ? 0 : dailyTotals.reduce(0, +) / Double(dailyTotals.count)

		// Fetch cumulative average hourly pattern for "Average" metric, filtered by weekday
		let averageHourlyData = try await fetchCumulativeAverageHourlyPattern(
			from: seventyDaysAgo, to: yesterday, type: activeEnergyType, filterWeekday: targetWeekday)

		return (projectedTotal, averageHourlyData)
	}

	/// Populate weekday-specific average caches for all 7 weekdays
	/// Called after initial authorization to ensure widget has fallback data for all weekdays
	func populateWeekdayCaches() async {
		print("📊 Populating weekday-specific average caches for all 7 weekdays...")

		let cacheManager = AverageDataCacheManager()

		// Populate caches for all 7 weekdays (1=Sunday through 7=Saturday)
		for weekdayRawValue in 1...7 {
			guard let weekday = Weekday(rawValue: weekdayRawValue) else { continue }

			do {
				// Fetch average data for this specific weekday
				let (total, hourlyData) = try await fetchAverageData(for: weekdayRawValue)

				// Save to weekday-specific cache
				let cache = AverageDataCache(
					averageHourlyPattern: hourlyData,
					projectedTotal: total,
					cachedAt: Date(),
					cacheVersion: 1
				)
				try cacheManager.save(cache, for: weekday)

				print(
					"  ✅ Cached weekday \(weekdayRawValue): \(total) kcal projected, \(hourlyData.count) hourly points"
				)
			} catch {
				print("  ⚠️ Failed to cache weekday \(weekdayRawValue): \(error.localizedDescription)")
				// Continue with other weekdays even if one fails
			}
		}

		print("✅ Weekday cache population complete")
	}

	// Fetch hourly data for a specific time range
	private func fetchHourlyData(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws
		-> [HourlyEnergyData]
	{
		let predicate = HKQuery.predicateForSamples(
			withStart: startDate, end: endDate, options: .strictStartDate)
		let calendar = Calendar.current

		var hourlyTotals: [Date: Double] = [:]

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

		// Group by hour
		for sample in samples {
			let hourStart =
				calendar.dateInterval(of: .hour, for: sample.startDate)?.start ?? sample.startDate
			let calories = sample.quantity.doubleValue(for: .kilocalorie())
			hourlyTotals[hourStart, default: 0] += calories
		}

		// Convert to array and sort
		return hourlyTotals.map { HourlyEnergyData(hour: $0.key, calories: $0.value) }
			.sorted { $0.hour < $1.hour }
	}

	// Fetch daily totals for a date range
	// If filterWeekday is provided, only includes days matching that weekday (1 = Sunday, 7 = Saturday)
	private func fetchDailyTotals(
		from startDate: Date, to endDate: Date, type: HKQuantityType, filterWeekday: Int? = nil
	) async throws -> [Double] {
		let predicate = HKQuery.predicateForSamples(
			withStart: startDate, end: endDate, options: .strictStartDate)
		let calendar = Calendar.current

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

	// Fetch cumulative average hourly pattern across multiple days
	// For each hour H, calculates average of cumulative totals BY that hour (see CLAUDE.md for "Average")
	// If filterWeekday is provided, only includes days matching that weekday (1 = Sunday, 7 = Saturday)
	private func fetchCumulativeAverageHourlyPattern(
		from startDate: Date, to endDate: Date, type: HKQuantityType, filterWeekday: Int? = nil
	) async throws -> [HourlyEnergyData] {
		let predicate = HKQuery.predicateForSamples(
			withStart: startDate, end: endDate, options: .strictStartDate)
		let calendar = Calendar.current

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

		// Start with 0 at midnight to show beginning of day
		hourlyData.append(HourlyEnergyData(hour: startOfToday, calories: 0))

		// Timestamps should represent END of hour (hour 0 = 1 AM, hour 23 = midnight next day)
		hourlyData.append(
			contentsOf: averageCumulativeByHour.map { hour, avgCumulative in
				let hourDate = calendar.date(byAdding: .hour, value: hour + 1, to: startOfToday)!
				return HourlyEnergyData(hour: hourDate, calories: avgCumulative)
			}.sorted { $0.hour < $1.hour })

		// Add interpolated NOW point for real-time average
		// Interpolate between current hour and next hour based on minutes into hour
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

enum HealthKitError: Error {
	case notAvailable
	case authorizationDenied
}
