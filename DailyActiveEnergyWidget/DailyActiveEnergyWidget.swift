//
//  DailyActiveEnergyWidget.swift
//  DailyActiveEnergyWidget
//
//  Created by Nick Christensen on 2025-11-14.
//

import AppIntents
import HealthKit
import HealthTrendsShared
import SwiftUI
@preconcurrency import UserNotifications
import WidgetKit
import os

// MARK: - Timeline Entry

struct EnergyWidgetEntry: TimelineEntry {
	let date: Date
	let todayTotal: Double
	let averageAtCurrentHour: Double
	let averageTotal: Double
	let moveGoal: Double
	let todayHourlyData: [HourlyEnergyData]
	let averageHourlyData: [HourlyEnergyData]
	let configuration: EnergyWidgetConfigurationIntent
	let isAuthorized: Bool

	/// Placeholder entry with sample data for widget gallery
	static var placeholder: EnergyWidgetEntry {
		EnergyWidgetEntry(
			date: Date(),
			todayTotal: 467,
			averageAtCurrentHour: 389,
			averageTotal: 1034,
			moveGoal: 800,
			todayHourlyData: generateSampleTodayData(),
			averageHourlyData: generateSampleAverageData(),
			configuration: EnergyWidgetConfigurationIntent(),
			isAuthorized: false  // Show unauthorized view until timeline generates
		)
	}

	/// Generate sample today data for preview
	private static func generateSampleTodayData() -> [HourlyEnergyData] {
		let calendar = Calendar.current
		let now = Date()
		let startOfDay = calendar.startOfDay(for: now)
		let currentHour = calendar.component(.hour, from: now)

		var data: [HourlyEnergyData] = []
		var cumulative: Double = 0

		// Midnight point
		data.append(HourlyEnergyData(hour: startOfDay, calories: 0))

		// Completed hours
		for hour in 0..<currentHour {
			let calories = Double.random(in: 20...80)
			cumulative += calories
			let timestamp = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!
			data.append(HourlyEnergyData(hour: timestamp, calories: cumulative))
		}

		// Current hour
		cumulative += Double.random(in: 10...40)
		data.append(HourlyEnergyData(hour: now, calories: cumulative))

		return data
	}

	/// Generate sample average data for preview
	private static func generateSampleAverageData() -> [HourlyEnergyData] {
		let calendar = Calendar.current
		let now = Date()
		let startOfDay = calendar.startOfDay(for: now)

		var data: [HourlyEnergyData] = []
		var cumulative: Double = 0

		// Midnight point
		data.append(HourlyEnergyData(hour: startOfDay, calories: 0))

		// Average cumulative pattern for all 24 hours
		for hour in 0..<24 {
			let hourlyAverage = Double.random(in: 25...65)
			cumulative += hourlyAverage
			let timestamp = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay)!
			data.append(HourlyEnergyData(hour: timestamp, calories: cumulative))
		}

		// NOW interpolated point
		let currentHour = calendar.component(.hour, from: now)
		let currentMinute = calendar.component(.minute, from: now)
		let avgAtCurrentHour = data[currentHour + 1].calories
		let avgAtNextHour = data[min(currentHour + 2, 24)].calories
		let interpolationFactor = Double(currentMinute) / 60.0
		let avgAtNow = avgAtCurrentHour + (avgAtNextHour - avgAtCurrentHour) * interpolationFactor
		data.append(HourlyEnergyData(hour: now, calories: avgAtNow))

		return data
	}
}

// MARK: - Timeline Provider

struct EnergyWidgetProvider: AppIntentTimelineProvider {
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends", category: "DailyActiveEnergyWidget")

	private let healthKitService: HealthDataProvider
	private let averageCacheManager: AverageDataCacheManager
	private let todayCacheManager: TodayEnergyCacheManager
	private let notificationScheduler: NotificationScheduler
	private let projectionStateManager: ProjectionStateCacheManager

	// Production initializer (used by widget system)
	init() {
		self.healthKitService = HealthKitQueryService()
		self.averageCacheManager = AverageDataCacheManager()
		self.todayCacheManager = TodayEnergyCacheManager.shared
		self.notificationScheduler = UserNotificationScheduler()
		self.projectionStateManager = ProjectionStateCacheManager.shared
	}

	// Test initializer with dependency injection for all dependencies
	init(
		healthKitService: HealthDataProvider,
		averageCacheManager: AverageDataCacheManager = AverageDataCacheManager(),
		todayCacheManager: TodayEnergyCacheManager = TodayEnergyCacheManager.shared,
		notificationScheduler: NotificationScheduler = UserNotificationScheduler(),
		projectionStateManager: ProjectionStateCacheManager = ProjectionStateCacheManager.shared
	) {
		self.healthKitService = healthKitService
		self.averageCacheManager = averageCacheManager
		self.todayCacheManager = todayCacheManager
		self.notificationScheduler = notificationScheduler
		self.projectionStateManager = projectionStateManager
	}

	func placeholder(in context: Context) -> EnergyWidgetEntry {
		.placeholder
	}

	func snapshot(for configuration: EnergyWidgetConfigurationIntent, in context: Context) async
		-> EnergyWidgetEntry
	{
		// For widget gallery - return quickly with cached data
		return loadCachedEntry(configuration: configuration)
	}

	func timeline(for configuration: EnergyWidgetConfigurationIntent, in context: Context) async -> Timeline<
		EnergyWidgetEntry
	> {
		let currentDate = Date()
		let calendar = Calendar.current

		// Use hybrid approach: query HealthKit for today, use cached average data
		var entries: [EnergyWidgetEntry] = []
		let currentEntry = await loadFreshEntry(forDate: currentDate, configuration: configuration)
		entries.append(currentEntry)

		// Log authorization state for correlation
		Self.logger.info("Widget timeline generated at \(currentDate, privacy: .public)")
		Self.logger.info("   Entry timestamp (NOW marker): \(currentEntry.date, privacy: .public)")
		Self.logger.info(
			"   Authorization status: \(currentEntry.isAuthorized ? "✅ AUTHORIZED" : "❌ UNAUTHORIZED")")
		Self.logger.info("   Today total: \(currentEntry.todayTotal, privacy: .public) kcal")
		Self.logger.info(
			"   Data points: today=\(currentEntry.todayHourlyData.count), average=\(currentEntry.averageHourlyData.count)"
		)

		// Calculate next refresh time - use guards for safety
		guard let next15MinUpdate = calendar.date(byAdding: .minute, value: 15, to: currentDate) else {
			// Fallback: simple timeline with current entry and default 15-min refresh
			return Timeline(entries: entries, policy: .after(currentDate.addingTimeInterval(900)))
		}

		guard
			let midnight = calendar.nextDate(
				after: currentDate, matching: DateComponents(hour: 0), matchingPolicy: .nextTime)
		else {
			// Fallback: no midnight entry, just normal 15-min refresh
			return Timeline(entries: entries, policy: .after(next15MinUpdate))
		}

		let timeline: Timeline<EnergyWidgetEntry>

		if midnight <= next15MinUpdate {
			// Midnight is coming up - create zero-state entry with NEW weekday's average data
			let timeUntilMidnight = midnight.timeIntervalSince(currentDate)
			Self.logger.info("Midnight in \(Int(timeUntilMidnight))s - scheduling zero-state entry")

			let midnightEntry = createMidnightEntry(
				date: midnight,
				moveGoal: currentEntry.moveGoal,
				configuration: configuration,
				isAuthorized: currentEntry.isAuthorized
			)
			entries.append(midnightEntry)

			// Reload 1 minute after midnight for fresh data
			guard let reloadTime = calendar.date(byAdding: .minute, value: 1, to: midnight) else {
				// Fallback: use .atEnd
				return Timeline(entries: entries, policy: .atEnd)
			}

			timeline = Timeline(entries: entries, policy: .after(reloadTime))
		} else {
			timeline = Timeline(entries: entries, policy: .after(next15MinUpdate))
		}

		return timeline
	}

	/// Normalize timestamps in hourly data to match a target date
	/// Preserves hour/minute components while updating the date
	/// Used to align cached historical patterns with the current day's timeline
	/// Preserves end-of-day midnight endpoint for projection lines
	private func normalizeTimestamps(_ data: [HourlyEnergyData], to targetDate: Date) -> [HourlyEnergyData] {
		let calendar = Calendar.current
		let targetStartOfDay = calendar.startOfDay(for: targetDate)

		guard let targetEndOfDay = calendar.date(byAdding: .day, value: 1, to: targetStartOfDay) else {
			return []
		}

		return data.compactMap { dataPoint in
			let hour = calendar.component(.hour, from: dataPoint.hour)
			let minute = calendar.component(.minute, from: dataPoint.hour)

			// Special handling for midnight (hour 0) points:
			// - Start-of-day midnight (today 00:00, calories=0): Normalize to today
			// - End-of-day midnight (tomorrow 00:00, calories>0): Preserve as tomorrow for projection endpoint
			if hour == 0 && minute == 0 {
				if dataPoint.calories > 0 {
					// This is the end-of-day projection endpoint (tomorrow's midnight)
					// Keep it at tomorrow's date - do NOT normalize to today
					return HourlyEnergyData(hour: targetEndOfDay, calories: dataPoint.calories)
				} else {
					// This is start-of-day midnight (0 calories) - normalize to today
					return HourlyEnergyData(hour: targetStartOfDay, calories: 0)
				}
			}

			// For all other hours, normalize to target date
			guard
				let normalizedDate = calendar.date(
					bySettingHour: hour,
					minute: minute,
					second: 0,
					of: targetStartOfDay
				)
			else {
				return nil
			}

			return HourlyEnergyData(hour: normalizedDate, calories: dataPoint.calories)
		}
	}

	/// Validates if a timestamp is from the same day as a reference date
	/// Returns the timestamp if valid (same day), nil otherwise
	/// Used to ensure effectiveDate is never stale (from a previous day)
	private func validateTimestampIsToday(_ timestamp: Date?, comparedTo referenceDate: Date) -> Date? {
		guard let timestamp = timestamp else { return nil }
		let calendar = Calendar.current
		return calendar.isDate(timestamp, inSameDayAs: referenceDate) ? timestamp : nil
	}

	/// Create a predictive zero-state entry for midnight
	/// We know that "Today" resets to 0 at midnight, so this is a valid deterministic state
	/// Loads average data for the NEW weekday (e.g., Tuesday at midnight, not Monday)
	private func createMidnightEntry(
		date: Date,
		moveGoal: Double,
		configuration: EnergyWidgetConfigurationIntent,
		isAuthorized: Bool
	) -> EnergyWidgetEntry {
		let calendar = Calendar.current
		let startOfDay = calendar.startOfDay(for: date)

		// Derive weekday from the midnight date (not "today")
		let weekday = Weekday(date: date)!

		// Load average data for the NEW weekday
		let averageCache = averageCacheManager.load(for: weekday)

		// Normalize timestamps to match the midnight date
		let cachedData = averageCache?.toHourlyEnergyData() ?? []
		let averageHourlyData = normalizeTimestamps(cachedData, to: date)
		let projectedTotal = averageCache?.projectedTotal ?? 0

		// Clear projection state at midnight to prevent false notifications
		// This prevents stale yesterday's projection from triggering "Falling Behind" alert
		// when the new day's low projection is compared against yesterday's final value
		projectionStateManager.clearState()
		Self.logger.info("Cleared projection state at midnight - new day baseline")

		return EnergyWidgetEntry(
			date: date,
			todayTotal: 0,  // Known: Today resets to 0 at midnight
			averageAtCurrentHour: 0,  // At midnight, average is also 0
			averageTotal: projectedTotal,
			moveGoal: moveGoal,  // Use previous goal; will be refreshed after midnight reload
			todayHourlyData: [HourlyEnergyData(hour: startOfDay, calories: 0)],  // Single point at midnight with 0
			averageHourlyData: averageHourlyData,  // New weekday's pattern with normalized timestamps
			configuration: configuration,
			isAuthorized: isAuthorized
		)
	}

	/// Create an error entry for cache failures and unauthorized states
	/// Used when HealthKit queries fail and no cache is available
	private func createErrorEntry(
		date: Date,
		configuration: EnergyWidgetConfigurationIntent
	) -> EnergyWidgetEntry {
		EnergyWidgetEntry(
			date: date,
			todayTotal: 0,
			averageAtCurrentHour: 0,
			averageTotal: 0,
			moveGoal: loadCachedMoveGoal(),
			todayHourlyData: [],
			averageHourlyData: [],
			configuration: configuration,
			isAuthorized: false
		)
	}

	/// Load fresh entry using hybrid approach: query HealthKit for today, use cached average
	/// Note: Internal visibility for testing purposes
	internal func loadFreshEntry(forDate date: Date = Date(), configuration: EnergyWidgetConfigurationIntent) async
		-> EnergyWidgetEntry
	{
		let healthKit = healthKitService  // Use injected service

		// Try to get fresh today's data AND move goal from HealthKit
		let todayData: [HourlyEnergyData]
		let todayTotal: Double
		let moveGoal: Double
		let latestSampleTimestamp: Date?

		do {
			// Query both today's data and move goal in parallel
			async let hourlyTotals = healthKit.fetchTodayHourlyTotals()
			async let goalQuery = healthKit.fetchMoveGoal()

			let ((hourlyData, sampleTimestamp), fetchedGoal) = try await (hourlyTotals, goalQuery)
			todayData = hourlyData
			todayTotal = hourlyData.last?.calories ?? 0
			moveGoal = fetchedGoal > 0 ? fetchedGoal : loadCachedMoveGoal()
			latestSampleTimestamp = sampleTimestamp

			// Write today's data to cache for future widget refreshes
			// This ensures cache stays fresh even if user rarely opens the app
			do {
				try todayCacheManager.writeEnergyData(
					todayTotal: todayTotal,
					moveGoal: moveGoal,
					todayHourlyData: hourlyData,
					latestSampleTimestamp: latestSampleTimestamp
				)
				Self.logger.info("✅ Widget wrote today's data to cache")
			} catch {
				// Non-fatal: cache write failure doesn't affect widget display
				Self.logger.warning("⚠️ Widget failed to write today's cache (non-fatal)")
				Self.logger.warning("   Error: \(error.localizedDescription, privacy: .public)")
			}

			// TODO: Remove this check
			// Check data freshness - warn if older than 30 minutes
			if let latestDataPoint = hourlyData.last {
				let dataAge = date.timeIntervalSince(latestDataPoint.hour)

				// Warning if data is more than 30 minutes old
				if dataAge > 1800 {
					Self.logger.warning("⚠️ Stale HealthKit data detected")
					Self.logger.warning("⚠️ Query time: \(date, privacy: .public)")
					Self.logger.warning(
						"⚠️ Latest data point: \(latestDataPoint.hour, privacy: .public)")
					Self.logger.warning("⚠️ Data age: \(Int(dataAge/60)) minutes (\(Int(dataAge))s)")
					Self.logger.warning(
						"⚠️ Today total: \(todayTotal) cal from \(hourlyData.count) data points"
					)
				}
			}
		} catch {
			// HealthKit query failed - attempt cache fallback
			Self.logger.error("❌ HealthKit query failed - falling back to cache")

			// Log specific error type for better diagnostics
			if let hkError = error as? HKError {
				Self.logger.error("   HealthKit error code: \(hkError.code.rawValue)")
				switch hkError.code {
				case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
					Self.logger.error("   → Authorization issue")
				case .errorDatabaseInaccessible:
					Self.logger.error("   → Device locked (temporary)")
				default:
					Self.logger.error("   → HealthKit error: \(hkError.localizedDescription)")
				}
			} else {
				Self.logger.error("   UNEXPECTED: Non-HealthKit error type: \(type(of: error))")
				Self.logger.error("   Error: \(error.localizedDescription, privacy: .public)")
			}

			// Try to read TodayEnergyCache cache (today only)
			do {
				let todayCache = try todayCacheManager.readEnergyData()
				let calendar = Calendar.current

				// Read average data from weekday-specific cache
				let weekday = Weekday(date: date)!
				let averageCache = averageCacheManager.load(for: weekday)
				let cachedAverageData = averageCache?.toHourlyEnergyData() ?? []
				let averageHourlyData = normalizeTimestamps(cachedAverageData, to: date)
				let projectedTotal = averageCache?.projectedTotal ?? 0

				// Determine effectiveDate: use sample timestamp ONLY if it's from today
				let effectiveDate =
					validateTimestampIsToday(todayCache.latestSampleTimestamp, comparedTo: date)
					?? date
				if todayCache.latestSampleTimestamp != nil && effectiveDate == date {
					// Timestamp was present but invalid (stale)
					Self.logger.warning(
						"⚠️ Stale sample timestamp in cache (not from today) - using current time as fallback"
					)
					Self.logger.warning(
						"   Sample timestamp: \(todayCache.latestSampleTimestamp!, privacy: .public)"
					)
					Self.logger.warning(
						"   Current time: \(date, privacy: .public)")
				} else if todayCache.latestSampleTimestamp == nil {
					Self.logger.warning(
						"⚠️ No sample timestamp in cache - using current time as fallback")
					Self.logger.warning(
						"   This may indicate: first install, no activity data, or cache corruption"
					)
				}
				let averageAtCurrentHour = averageHourlyData.interpolatedValue(at: effectiveDate) ?? 0

				// Determine if cache is from today (used for branch logic)
				// If no sample timestamp exists, treat as stale (fail-safe)
				let isCacheFromToday: Bool
				if let sampleTime = todayCache.latestSampleTimestamp {
					isCacheFromToday = calendar.isDate(sampleTime, inSameDayAs: date)
				} else {
					isCacheFromToday = false  // No timestamp = treat as stale
					Self.logger.warning("   → Treating cache as stale (fail-safe behavior)")
				}

				if isCacheFromToday {
					// TODAY'S CACHE: Use cached today data + cached average data

					Self.logger.info("✅ Using today's cached data + average cache")
					Self.logger.info(
						"   Latest sample: \(todayCache.latestSampleTimestamp?.description ?? "nil", privacy: .public)"
					)
					Self.logger.info(
						"   Effective NOW: \(effectiveDate, privacy: .public)")
					Self.logger.info(
						"   Today total: \(todayCache.todayTotal, privacy: .public) kcal")
					Self.logger.info(
						"   Average cache: \(averageCache != nil ? "✅ available" : "❌ missing")"
					)

					return EnergyWidgetEntry(
						date: effectiveDate,
						todayTotal: todayCache.todayTotal,
						averageAtCurrentHour: averageAtCurrentHour,
						averageTotal: projectedTotal,
						moveGoal: todayCache.moveGoal,
						todayHourlyData: todayCache.todayHourlyData.map {
							$0.toHourlyEnergyData()
						},
						averageHourlyData: averageHourlyData,
						configuration: configuration,
						isAuthorized: true  // Cache exists = authorized
					)
				} else {
					// YESTERDAY'S CACHE: Show average data with empty today

					Self.logger.info("⚠️ Using yesterday's cache - showing average only")
					Self.logger.info(
						"   Latest sample: \(todayCache.latestSampleTimestamp?.description ?? "nil", privacy: .public)"
					)
					Self.logger.info(
						"   Effective NOW: \(effectiveDate, privacy: .public)")
					Self.logger.info("   Projected total: \(projectedTotal, privacy: .public) kcal")

					return EnergyWidgetEntry(
						date: effectiveDate,
						todayTotal: 0,
						averageAtCurrentHour: averageAtCurrentHour,
						averageTotal: projectedTotal,
						moveGoal: todayCache.moveGoal,  // Use cached goal when query fails
						todayHourlyData: [],  // Empty today data
						averageHourlyData: averageHourlyData,
						configuration: configuration,
						isAuthorized: true  // Cache exists = authorized
					)
				}
			} catch TodayEnergyCacheError.fileNotFound {
				// NO CACHE: Never authorized OR first run
				Self.logger.warning("❌ No cache found - returning unauthorized state")
				return createErrorEntry(date: date, configuration: configuration)
			} catch TodayEnergyCacheError.containerNotFound {
				// APP GROUP ERROR: Configuration issue
				Self.logger.error("❌ App group container not found - configuration error")
				return createErrorEntry(date: date, configuration: configuration)
			} catch let error as DecodingError {
				// CACHE CORRUPTION: Failed to decode cached data
				Self.logger.error("❌ Cache corruption: Failed to decode cached data")
				Self.logger.error("   Error: \(String(describing: error))")
				Self.logger.error("   Action: Cache will be regenerated on next app launch")
				return createErrorEntry(date: date, configuration: configuration)
			} catch {
				// OTHER UNEXPECTED CACHE ERROR
				Self.logger.error("❌ UNEXPECTED cache error: \(type(of: error))")
				Self.logger.error("   Error: \(error.localizedDescription, privacy: .public)")
				return createErrorEntry(date: date, configuration: configuration)
			}
		}

		// Load or refresh average data cache
		let averageData: [HourlyEnergyData]
		let projectedTotal: Double

		let weekday = Weekday(date: date)!
		if averageCacheManager.shouldRefresh(for: weekday) {
			// Cache is stale or missing - refresh it
			Self.logger.info(
				"Average data cache for weekday \(weekday.rawValue) is stale/missing - refreshing from HealthKit"
			)

			do {
				let (total, hourlyData) = try await healthKit.fetchAverageData(for: nil)
				projectedTotal = total
				averageData = hourlyData

				Self.logger.info("✅ Successfully fetched average data for weekday \(weekday.rawValue)")
				Self.logger.info("   Projected total: \(total, privacy: .public) kcal")
				Self.logger.info("   Hourly data points: \(hourlyData.count)")

				// Save to cache for future use
				let cache = AverageDataCache(
					averageHourlyPattern: hourlyData,
					projectedTotal: total,
					cachedAt: Date(),
					cacheVersion: 1
				)
				do {
					try averageCacheManager.save(cache, for: weekday)
					Self.logger.info("   ✅ Saved average data to weekday \(weekday.rawValue) cache")
				} catch {
					Self.logger.error("   ❌ CRITICAL: Failed to save average cache")
					Self.logger.error("   Weekday: \(weekday.rawValue)")
					Self.logger.error("   Error: \(error.localizedDescription, privacy: .public)")
					Self.logger.error(
						"   Widget will re-query HealthKit on every refresh (performance impact)"
					)
				}
			} catch {
				Self.logger.error("❌ Widget FAILED to fetch average data at \(date, privacy: .public)")
				Self.logger.error("   Error: \(error.localizedDescription, privacy: .public)")
				Self.logger.error(
					"   Error type: \(String(describing: type(of: error)), privacy: .public)")

				// Try to use stale cache as fallback
				if let staleCache = averageCacheManager.load(for: weekday) {
					let cachedData = staleCache.toHourlyEnergyData()
					averageData = normalizeTimestamps(cachedData, to: date)
					projectedTotal = staleCache.projectedTotal
					let cacheAge = date.timeIntervalSince(staleCache.cachedAt)

					Self.logger.warning("   ⚠️ Using STALE cache as fallback")
					Self.logger.warning(
						"   Cache timestamp: \(staleCache.cachedAt, privacy: .public)")
					Self.logger.warning(
						"   Cache age: \(Int(cacheAge/3600)) hours (\(Int(cacheAge/60)) minutes)"
					)
					Self.logger.warning(
						"   Projected total: \(projectedTotal, privacy: .public) kcal")
				} else {
					// No cache available - return today-only entry
					Self.logger.error("   ❌ No stale cache available - returning today-only entry")
					let effectiveDate = todayData.last?.hour ?? date
					let timestampSource = todayData.last == nil ? "query time" : "latest today data"
					Self.logger.error(
						"   Entry timestamp: \(effectiveDate, privacy: .public) (\(timestampSource))"
					)

					return EnergyWidgetEntry(
						date: effectiveDate,
						todayTotal: todayTotal,
						averageAtCurrentHour: 0,
						averageTotal: 0,
						moveGoal: loadCachedMoveGoal(),
						todayHourlyData: todayData,
						averageHourlyData: [],
						configuration: configuration,
						isAuthorized: true
					)
				}
			}
		} else {
			// Use fresh cache
			if let cache = averageCacheManager.load(for: weekday) {
				let cachedData = cache.toHourlyEnergyData()
				averageData = normalizeTimestamps(cachedData, to: date)
				projectedTotal = cache.projectedTotal
				let cacheAge = date.timeIntervalSince(cache.cachedAt)

				Self.logger.info("✅ Using fresh average data cache for weekday \(weekday.rawValue)")
				Self.logger.info("   Cache timestamp: \(cache.cachedAt, privacy: .public)")
				Self.logger.info("   Cache age: \(Int(cacheAge/60)) minutes")
				Self.logger.info("   Projected total: \(projectedTotal, privacy: .public) kcal")
			} else {
				// Shouldn't happen (shouldRefresh would return true), but handle gracefully
				Self.logger.warning(
					"⚠️ UNEXPECTED: shouldRefresh=false but no cache found - using empty average data"
				)
				averageData = []
				projectedTotal = 0
			}
		}

		// Calculate interpolated average at current hour
		// Priority for "NOW" marker: latest sample timestamp > data point timestamp > query time
		// Rationale: Latest sample timestamp is the true time of HealthKit data freshness.
		// This prevents the NOW marker from appearing ahead of actual data when there's a delay
		// between sample collection and widget refresh (e.g., device locked, background sync).
		// IMPORTANT: Only use timestamps if they're from today (not stale)
		let effectiveDate =
			validateTimestampIsToday(latestSampleTimestamp, comparedTo: date)
			?? validateTimestampIsToday(todayData.last?.hour, comparedTo: date)
			?? date

		// Log warnings for stale timestamps
		if latestSampleTimestamp != nil
			&& validateTimestampIsToday(latestSampleTimestamp, comparedTo: date) == nil
		{
			if validateTimestampIsToday(todayData.last?.hour, comparedTo: date) != nil {
				Self.logger.warning(
					"⚠️ Stale latestSampleTimestamp (not from today) - using last data point instead"
				)
				Self.logger.warning("   Sample timestamp: \(latestSampleTimestamp!, privacy: .public)")
			} else {
				Self.logger.warning(
					"⚠️ Stale latestSampleTimestamp (not from today) - using current time")
				Self.logger.warning("   Sample timestamp: \(latestSampleTimestamp!, privacy: .public)")
			}
		}
		if todayData.last?.hour != nil
			&& validateTimestampIsToday(todayData.last?.hour, comparedTo: date) == nil
		{
			Self.logger.warning("⚠️ Stale last data point (not from today) - using current time")
			Self.logger.warning("   Last data point: \(todayData.last!.hour, privacy: .public)")
		}
		let averageAtCurrentHour = averageData.interpolatedValue(at: effectiveDate) ?? 0

		// Check for projection goal crossing and schedule notification if needed
		let currentProjected = todayTotal + (projectedTotal - averageAtCurrentHour)
		await detectAndNotifyGoalCrossing(
			currentProjected: currentProjected,
			moveGoal: moveGoal,
			referenceDate: effectiveDate
		)

		// Log timestamp details for debugging
		Self.logger.info("Widget timeline entry created:")
		Self.logger.info("   Query time: \(date, privacy: .public)")
		Self.logger.info("   Latest sample: \(latestSampleTimestamp?.description ?? "nil", privacy: .public)")
		Self.logger.info("   Effective NOW: \(effectiveDate, privacy: .public)")
		if let sampleTime = latestSampleTimestamp {
			let staleness = Int(date.timeIntervalSince(sampleTime))
			Self.logger.info("   Data age: \(staleness)s")
		}

		return EnergyWidgetEntry(
			date: effectiveDate,
			todayTotal: todayTotal,
			averageAtCurrentHour: averageAtCurrentHour,
			averageTotal: projectedTotal,
			moveGoal: moveGoal,  // Use fresh goal from HealthKit query
			todayHourlyData: todayData,
			averageHourlyData: averageData,
			configuration: configuration,
			isAuthorized: true
		)
	}

	/// Load cached entry from shared container (for widget gallery)
	private func loadCachedEntry(forDate date: Date = Date(), configuration: EnergyWidgetConfigurationIntent)
		-> EnergyWidgetEntry
	{
		do {
			let todayCache = try todayCacheManager.readEnergyData()

			// Read average data from weekday-specific cache
			let weekday = Weekday(date: date)!
			let averageCache = averageCacheManager.load(for: weekday)
			let cachedAverageData = averageCache?.toHourlyEnergyData() ?? []
			let averageHourlyData = normalizeTimestamps(cachedAverageData, to: date)
			let projectedTotal = averageCache?.projectedTotal ?? 0

			// Use sample timestamp ONLY if it's from today
			let effectiveDate =
				validateTimestampIsToday(todayCache.latestSampleTimestamp, comparedTo: date) ?? date
			if todayCache.latestSampleTimestamp != nil && effectiveDate == date {
				Self.logger.warning(
					"⚠️ Widget gallery: Stale sample timestamp in cache (not from today) - using current time"
				)
				Self.logger.warning(
					"   Sample timestamp: \(todayCache.latestSampleTimestamp!, privacy: .public)")
			} else if todayCache.latestSampleTimestamp == nil {
				Self.logger.warning(
					"⚠️ Widget gallery: No sample timestamp in cache - using current time")
			}
			let averageAtCurrentHour = averageHourlyData.interpolatedValue(at: effectiveDate) ?? 0

			return EnergyWidgetEntry(
				date: effectiveDate,
				todayTotal: todayCache.todayTotal,
				averageAtCurrentHour: averageAtCurrentHour,
				averageTotal: projectedTotal,
				moveGoal: todayCache.moveGoal,
				todayHourlyData: todayCache.todayHourlyData.map { $0.toHourlyEnergyData() },
				averageHourlyData: averageHourlyData,
				configuration: configuration,
				isAuthorized: true  // Cached data implies previous authorization
			)
		} catch {
			Self.logger.warning("Failed to load cached data in loadCachedEntry()")
			return createErrorEntry(date: date, configuration: configuration)
		}
	}

	/// Load cached move goal (goals don't change frequently)
	private func loadCachedMoveGoal() -> Double {
		do {
			let sharedData = try todayCacheManager.readEnergyData()
			return sharedData.moveGoal
		} catch {
			return 800  // Default fallback
		}
	}

	/// Detect goal crossing and schedule notification
	private func detectAndNotifyGoalCrossing(
		currentProjected: Double,
		moveGoal: Double,
		referenceDate: Date
	) async {
		let detector = ProjectionGoalCrossingDetector()

		// Read previous state
		let previousProjected: Double?
		do {
			let state = try projectionStateManager.readState()
			let calendar = Calendar.current
			if calendar.isDate(state.timestamp, inSameDayAs: referenceDate) {
				previousProjected = state.projectedTotal
			} else {
				projectionStateManager.clearState()
				previousProjected = nil
				Self.logger.info("Cleared projection state from previous day")
			}
		} catch ProjectionStateCacheError.fileNotFound {
			// First run - no previous state exists yet
			previousProjected = nil
		} catch {
			Self.logger.error(
				"Failed to read projection state: \(error.localizedDescription, privacy: .public)")
			previousProjected = nil
		}

		// Detect crossing
		guard
			let event = detector.detectCrossing(
				previousProjected: previousProjected,
				currentProjected: currentProjected,
				moveGoal: moveGoal
			)
		else {
			// No crossing - just update state for next check
			do {
				try projectionStateManager.writeState(ProjectionState(projectedTotal: currentProjected))
			} catch {
				Self.logger.error(
					"Failed to persist projection state: \(error.localizedDescription, privacy: .public)"
				)
				Self.logger.error("Next crossing detection may be inaccurate")
			}
			return
		}

		// Crossing detected - schedule notification
		Self.logger.info("Goal crossing detected: \(String(describing: event.direction))")
		do {
			try await notificationScheduler.scheduleNotification(for: event)
			Self.logger.info("✅ Notification scheduled successfully")
		} catch {
			Self.logger.error(
				"❌ Failed to schedule notification: \(error.localizedDescription, privacy: .public)")
		}

		// Update state after notification
		do {
			try projectionStateManager.writeState(ProjectionState(projectedTotal: currentProjected))
		} catch {
			Self.logger.error(
				"Failed to persist projection state after notification: \(error.localizedDescription, privacy: .public)"
			)
			Self.logger.error("Next crossing detection may be inaccurate")
		}
	}
}

// MARK: - Notification Scheduler

/// Concrete notification scheduler using UNUserNotificationCenter
/// Schedules local notifications for projection goal crossings
final class UserNotificationScheduler: NotificationScheduler, @unchecked Sendable {
	private let notificationCenter: UNUserNotificationCenter
	private static let logger = Logger(
		subsystem: "com.finelycrafted.HealthTrends",
		category: "UserNotificationScheduler"
	)

	init(notificationCenter: UNUserNotificationCenter = .current()) {
		self.notificationCenter = notificationCenter
	}

	func scheduleNotification(for event: GoalCrossingEvent) async throws {
		// Check authorization first
		let settings = await notificationCenter.notificationSettings()
		guard settings.authorizationStatus == .authorized else {
			Self.logger.warning("Notification permission not granted - skipping notification")
			return
		}

		// Create content
		let content = UNMutableNotificationContent()
		content.title = formatTitle(for: event)
		content.body = formatBody(for: event)
		content.sound = .default
		content.categoryIdentifier = "GOAL_CROSSING"

		// Create request (use constant identifier to replace previous notifications)
		let request = UNNotificationRequest(
			identifier: "projection-goal-crossing",
			content: content,
			trigger: nil  // Deliver immediately
		)

		// Schedule
		try await notificationCenter.add(request)
		Self.logger.info("Scheduled goal crossing notification: \(String(describing: event.direction))")
	}

	private func formatTitle(for event: GoalCrossingEvent) -> String {
		switch event.direction {
		case .belowToAbove:
			return "On Track! 🎯"
		case .aboveToBelow:
			return "Falling Behind 📉"
		}
	}

	private func formatBody(for event: GoalCrossingEvent) -> String {
		let projected = Int(event.projectedTotal)
		let goal = Int(event.moveGoal)

		switch event.direction {
		case .belowToAbove:
			return
				"You're now projected to reach your goal! Projected: \(projected) cal / Goal: \(goal) cal"
		case .aboveToBelow:
			return "Your pace has slowed. Projected: \(projected) cal / Goal: \(goal) cal"
		}
	}
}

// MARK: - Empty State View

struct WidgetUnauthorizedView: View {
	@Environment(\.widgetFamily) var widgetFamily

	var body: some View {
		VStack(spacing: widgetFamily == .systemMedium ? 12 : 16) {
			Image(systemName: "heart.text.square.fill")
				.font(widgetFamily == .systemMedium ? .largeTitle : .system(size: 60))
				.foregroundStyle(.secondary)

			VStack(spacing: widgetFamily == .systemMedium ? 6 : 8) {
				Text("Health Access Required")
					.font(widgetFamily == .systemMedium ? .subheadline : .headline)
					.fontWeight(.semibold)
					.multilineTextAlignment(.center)

				Text("Tap to open the app and grant Health access")
					.font(widgetFamily == .systemMedium ? .caption : .subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
			.padding(.horizontal)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
	}
}

// MARK: - Widget View

struct DailyActiveEnergyWidgetEntryView: View {
	var entry: EnergyWidgetProvider.Entry

	var body: some View {
		if !entry.isAuthorized {
			// Unauthorized: tap opens app for HealthKit authorization
			WidgetUnauthorizedView()
				.widgetURL(URL(string: "healthtrends://"))
		} else {
			// Authorized: tap refreshes widget data
			Button(intent: RefreshWidgetIntent()) {
				contentView
			}
			.buttonStyle(.plain)
		}
	}

	private var contentView: some View {
		EnergyTrendView(
			todayTotal: entry.todayTotal,
			averageAtCurrentHour: entry.averageAtCurrentHour,
			todayHourlyData: entry.todayHourlyData,
			averageHourlyData: entry.averageHourlyData,
			moveGoal: entry.moveGoal,
			averageTotal: entry.averageTotal,
			dataTime: entry.date,
			chartStartHour: entry.configuration.chartStartHour.rawValue,
			accentColor: entry.configuration.accentColor.color
		)
	}
}

// MARK: - Widget Configuration

struct DailyActiveEnergyWidget: Widget {
	let kind: String = "DailyActiveEnergyWidget"

	var body: some WidgetConfiguration {
		AppIntentConfiguration(
			kind: kind, intent: EnergyWidgetConfigurationIntent.self, provider: EnergyWidgetProvider()
		) { entry in
			DailyActiveEnergyWidgetEntryView(entry: entry)
				.containerBackground(Color(.systemBackground), for: .widget)
		}
		.contentMarginsDisabled()
		.configurationDisplayName("Daily Active Energy")
		.description("Track your active energy compared to your recent average")
		.supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
	}
}

// MARK: - Previews

#Preview(as: .systemLarge) {
	DailyActiveEnergyWidget()
} timeline: {
	EnergyWidgetEntry.placeholder
}
#Preview(as: .systemMedium) {
	DailyActiveEnergyWidget()
} timeline: {
	EnergyWidgetEntry.placeholder
}
