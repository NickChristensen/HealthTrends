import Foundation
import HealthKit
import HealthTrendsShared
import WidgetKit

@Observable
final class HealthKitManager {
	private let healthStore = HKHealthStore()
	private let moveGoalCacheKey = "cachedMoveGoal"

	var isAuthorized = false
	var moveGoal: Double = 0  // Daily Move goal from Fitness app

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

		// If authorized, populate all caches for widget support
		if isAuthorized {
			print("✅ Authorization verified - populating caches")

			// Request notification permissions after HealthKit authorization
			await requestNotificationPermissions()

			do {
				try await populateTodayCache()
				await populateWeekdayCaches()
				print("✅ Cache population successful")
			} catch {
				// Don't throw - authorization succeeded even if cache population failed
				// User might have no data yet, or device might be locked
				print("⚠️ Cache population failed (non-fatal): \(error.localizedDescription)")
			}
		}
	}

	/// Request notification permissions for goal crossing alerts
	private func requestNotificationPermissions() async {
		let permissionProvider = UserNotificationPermissionProvider()
		do {
			let granted = try await permissionProvider.requestPermission()
			if granted {
				print("✅ Notification permissions granted")
			} else {
				print("⚠️ Notification permissions denied - goal crossing alerts disabled")
			}
		} catch {
			print("❌ Failed to request notification permissions: \(error.localizedDescription)")
		}
	}

	/// Verify read authorization using hybrid approach
	/// Fast path: Check cache (instant verification if data was previously fetched)
	/// Query path: Perform minimal HealthKit query to detect actual permission state
	private func verifyReadAuthorization() async -> Bool {
		// FAST PATH: Check cache first (existing behavior when it works)
		do {
			let _ = try TodayEnergyCacheManager.shared.readEnergyData()
			print("✅ Cache exists - authorization verified (fast path)")
			return true
		} catch TodayEnergyCacheError.fileNotFound {
			// Cache doesn't exist - need to query HealthKit directly
			print("⚠️ No cache found - checking HealthKit directly (query path)")
		} catch TodayEnergyCacheError.containerNotFound {
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
		let dataTime = now.addingTimeInterval(-dataAge)

		// Generate data for the past 60 days
		var samplesToSave: [HKQuantitySample] = []

		for dayOffset in 0..<60 {
			guard
				let dayStart = calendar.date(
					byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now))
			else {
				continue
			}

			// For today (dayOffset == 0), only generate up to dataTime
			// For past days, generate all 24 hours
			let currentHour = calendar.component(.hour, from: dataTime)
			let currentMinute = calendar.component(.minute, from: dataTime)
			let maxHour = dayOffset == 0 ? currentHour : 23

			// Generate hourly data points for each day
			for hour in 0...maxHour {
				guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else {
					continue
				}

				// Don't generate data beyond dataTime
				guard hourStart <= dataTime else {
					continue
				}

				// For the current hour on today, check if we need a partial hour or full hour
				let isCurrentHour = (dayOffset == 0 && hour == currentHour)
				let hourEnd: Date

				if isCurrentHour && currentMinute > 0 {
					// Generate partial hour up to the exact minute
					hourEnd = dataTime
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

	// MARK: - Cache Population

	/// Populate all caches (convenience method for debug tools)
	func populateAllCaches() async throws {
		try await populateTodayCache()
		await populateWeekdayCaches()
	}

	/// Populate today's energy data cache for widget fallback
	private func populateTodayCache() async throws {
		guard isHealthKitAvailable else {
			throw HealthKitError.notAvailable
		}

		let queryService = HealthKitQueryService(healthStore: healthStore)

		// Fetch today's data and move goal in parallel
		async let todayData = queryService.fetchTodayHourlyTotals()
		async let moveGoalData = queryService.fetchMoveGoal()

		let ((cumulativeData, latestSampleTimestamp), goal) = try await (todayData, moveGoalData)

		// Update and cache move goal if valid
		if goal > 0 {
			self.moveGoal = goal
			cacheMoveGoal(goal)
		}

		// Calculate today's total (last cumulative data point)
		let todayTotal = cumulativeData.last?.calories ?? 0

		// Write today's data to shared container for widget fallback
		do {
			try TodayEnergyCacheManager.shared.writeEnergyData(
				todayTotal: todayTotal,
				moveGoal: self.moveGoal,
				todayHourlyData: cumulativeData,
				latestSampleTimestamp: latestSampleTimestamp
			)
		} catch {
			print("⚠️ WARNING: Failed to write energy data cache for widget (non-fatal)")
			print("   Error: \(error.localizedDescription)")
			let nsError = error as NSError
			print("   Domain: \(nsError.domain), Code: \(nsError.code)")
			print("   Widget will query HealthKit directly on next refresh")
		}

		// Write average data to weekday-specific cache
		let weekday = Weekday.today
		let (projectedTotal, averageHourlyData) = try await fetchAverageData()

		let cache = AverageDataCache(
			averageHourlyPattern: averageHourlyData,
			projectedTotal: projectedTotal,
			cachedAt: Date(),
			cacheVersion: 1
		)
		do {
			try AverageDataCacheManager().save(cache, for: weekday)
		} catch {
			print("⚠️ WARNING: Failed to write weekday cache for widget (non-fatal)")
			print("   Weekday: \(weekday.rawValue)")
			print("   Error: \(error.localizedDescription)")
			let nsError = error as NSError
			print("   Domain: \(nsError.domain), Code: \(nsError.code)")
			print("   Widget will query HealthKit directly on next refresh")
		}

		// Reload widget timelines to pick up fresh data
		WidgetCenter.shared.reloadAllTimelines()
	}

	// Fetch average Active Energy data from past occurrences of the current weekday
	// Returns "Total" and "Average" (see CLAUDE.md)
	// Uses last 10 occurrences of today's weekday (e.g., if today is Saturday, uses last 10 Saturdays)
	// Delegates to shared HealthKitQueryService for efficient statistics-based queries
	private func fetchAverageData(for weekday: Int? = nil) async throws -> (
		total: Double, hourlyData: [HourlyEnergyData]
	) {
		let queryService = HealthKitQueryService(healthStore: healthStore, calendar: Calendar.current)
		return try await queryService.fetchAverageData(for: weekday)
	}

	/// Populate weekday-specific average caches for all 7 weekdays
	/// Called after initial authorization to ensure widget has fallback data for all weekdays
	func populateWeekdayCaches() async {
		print("📊 Populating weekday-specific average caches for all 7 weekdays...")

		let cacheManager = AverageDataCacheManager()
		var failedWeekdays: [Int] = []

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
				failedWeekdays.append(weekdayRawValue)
				print("  ❌ FAILED to cache weekday \(weekdayRawValue)")
				print("     Error: \(error.localizedDescription)")
				let nsError = error as NSError
				print("     Domain: \(nsError.domain), Code: \(nsError.code)")
			}
		}

		if failedWeekdays.isEmpty {
			print("✅ Weekday cache population complete - all 7 weekdays cached")
		} else {
			print("⚠️ Weekday cache population INCOMPLETE")
			print("   Failed weekdays: \(failedWeekdays.map { String($0) }.joined(separator: ", "))")
			print("   Widget may show incomplete data on these weekdays")
		}
	}
}

enum HealthKitError: Error {
	case notAvailable
	case authorizationDenied
}
