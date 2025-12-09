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
import WidgetKit
import os

// MARK: - Timeline Entry

struct EnergyWidgetEntry: TimelineEntry {
	let date: Date
	let todayTotal: Double
	let averageAtCurrentHour: Double
	let projectedTotal: Double
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
			projectedTotal: 1034,
			moveGoal: 800,
			todayHourlyData: generateSampleTodayData(),
			averageHourlyData: generateSampleAverageData(),
			configuration: EnergyWidgetConfigurationIntent(),
			isAuthorized: true  // Show unauthorized view until timeline generates
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

		if midnight < next15MinUpdate {
			// Midnight is coming up - create zero-state entry
			let timeUntilMidnight = midnight.timeIntervalSince(currentDate)
			Self.logger.info("Midnight in \(Int(timeUntilMidnight))s - scheduling zero-state entry")

			let midnightEntry = createMidnightEntry(
				date: midnight,
				moveGoal: currentEntry.moveGoal,
				averageHourlyData: currentEntry.averageHourlyData,
				projectedTotal: currentEntry.projectedTotal,
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

	/// Create a predictive zero-state entry for midnight
	/// We know that "Today" resets to 0 at midnight, so this is a valid deterministic state
	/// We preserve average data for visual continuity until the next reload
	private func createMidnightEntry(
		date: Date,
		moveGoal: Double,
		averageHourlyData: [HourlyEnergyData],
		projectedTotal: Double,
		configuration: EnergyWidgetConfigurationIntent,
		isAuthorized: Bool
	) -> EnergyWidgetEntry {
		let calendar = Calendar.current
		let startOfDay = calendar.startOfDay(for: date)

		return EnergyWidgetEntry(
			date: date,
			todayTotal: 0,  // Known: Today resets to 0 at midnight
			averageAtCurrentHour: 0,  // At midnight, average is also 0
			projectedTotal: projectedTotal,  // Keep yesterday's projected total for reference
			moveGoal: moveGoal,  // Use previous goal; will be refreshed after midnight reload
			todayHourlyData: [HourlyEnergyData(hour: startOfDay, calories: 0)],  // Single point at midnight with 0
			averageHourlyData: averageHourlyData,  // Keep average pattern for visual continuity
			configuration: configuration,
			isAuthorized: isAuthorized
		)
	}

	/// Load fresh entry using hybrid approach: query HealthKit for today, use cached average
	private func loadFreshEntry(forDate date: Date = Date(), configuration: EnergyWidgetConfigurationIntent) async
		-> EnergyWidgetEntry
	{
		let healthKit = HealthKitQueryService()
		let cacheManager = AverageDataCacheManager()

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

			// Try to read SharedEnergyData cache (today only)
			do {
				let todayCache = try SharedEnergyDataManager.shared.readEnergyData()
				let calendar = Calendar.current

				// Read average data from weekday-specific cache
				let averageCache = cacheManager.load(for: Weekday.today)
				let averageHourlyData = averageCache?.toHourlyEnergyData() ?? []
				let projectedTotal = averageCache?.projectedTotal ?? 0
				let averageAtCurrentHour =
					averageHourlyData.interpolatedValue(at: todayCache.lastUpdated) ?? 0

				// Determine effectiveDate: use sample timestamp only if it's from today
				let effectiveDate: Date
				if let sampleTime = todayCache.latestSampleTimestamp,
					calendar.isDate(sampleTime, inSameDayAs: date)
				{
					effectiveDate = sampleTime  // Sample is from today, use it
				} else {
					effectiveDate = date  // No sample or stale sample, use current time
				}

				// Determine if cache is from today (used for branch logic)
				let isCacheFromToday = calendar.isDate(todayCache.lastUpdated, inSameDayAs: date)

				if isCacheFromToday {
					// TODAY'S CACHE: Use cached today data + cached average data

					Self.logger.info("✅ Using today's cached data + average cache")
					Self.logger.info(
						"   Cache write time: \(todayCache.lastUpdated, privacy: .public)")
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
						projectedTotal: projectedTotal,
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
						"   Cache write time: \(todayCache.lastUpdated, privacy: .public)")
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
						projectedTotal: projectedTotal,
						moveGoal: todayCache.moveGoal,  // Use cached goal when query fails
						todayHourlyData: [],  // Empty today data
						averageHourlyData: averageHourlyData,
						configuration: configuration,
						isAuthorized: true  // Cache exists = authorized
					)
				}
			} catch SharedDataError.fileNotFound {
				// NO CACHE: Never authorized OR first run
				Self.logger.warning("❌ No cache found - returning unauthorized state")

				return EnergyWidgetEntry(
					date: date,
					todayTotal: 0,
					averageAtCurrentHour: 0,
					projectedTotal: 0,
					moveGoal: loadCachedMoveGoal(),  // Last resort: UserDefaults cache
					todayHourlyData: [],
					averageHourlyData: [],
					configuration: configuration,
					isAuthorized: false  // No cache = unauthorized
				)
			} catch SharedDataError.containerNotFound {
				// APP GROUP ERROR: Configuration issue
				Self.logger.error("❌ App group container not found - configuration error")

				return EnergyWidgetEntry(
					date: date,
					todayTotal: 0,
					averageAtCurrentHour: 0,
					projectedTotal: 0,
					moveGoal: loadCachedMoveGoal(),  // Last resort: UserDefaults cache
					todayHourlyData: [],
					averageHourlyData: [],
					configuration: configuration,
					isAuthorized: false
				)
			} catch let error as DecodingError {
				// CACHE CORRUPTION: Failed to decode cached data
				Self.logger.error("❌ Cache corruption: Failed to decode cached data")
				Self.logger.error("   Error: \(String(describing: error))")
				Self.logger.error("   Action: Cache will be regenerated on next app launch")

				return EnergyWidgetEntry(
					date: date,
					todayTotal: 0,
					averageAtCurrentHour: 0,
					projectedTotal: 0,
					moveGoal: loadCachedMoveGoal(),  // Last resort: UserDefaults cache
					todayHourlyData: [],
					averageHourlyData: [],
					configuration: configuration,
					isAuthorized: false
				)
			} catch {
				// OTHER UNEXPECTED CACHE ERROR
				Self.logger.error("❌ UNEXPECTED cache error: \(type(of: error))")
				Self.logger.error("   Error: \(error.localizedDescription, privacy: .public)")

				return EnergyWidgetEntry(
					date: date,
					todayTotal: 0,
					averageAtCurrentHour: 0,
					projectedTotal: 0,
					moveGoal: loadCachedMoveGoal(),  // Last resort: UserDefaults cache
					todayHourlyData: [],
					averageHourlyData: [],
					configuration: configuration,
					isAuthorized: false
				)
			}
		}

		// Load or refresh average data cache
		let averageData: [HourlyEnergyData]
		let projectedTotal: Double

		let weekday = Weekday.today
		if cacheManager.shouldRefresh(for: weekday) {
			// Cache is stale or missing - refresh it
			Self.logger.info(
				"Average data cache for weekday \(weekday.rawValue) is stale/missing - refreshing from HealthKit"
			)

			do {
				let (total, hourlyData) = try await healthKit.fetchAverageData()
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
					try cacheManager.save(cache, for: weekday)
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
				if let staleCache = cacheManager.load(for: weekday) {
					averageData = staleCache.toHourlyEnergyData()
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
						projectedTotal: 0,
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
			if let cache = cacheManager.load(for: weekday) {
				averageData = cache.toHourlyEnergyData()
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
		let effectiveDate = latestSampleTimestamp ?? todayData.last?.hour ?? date
		let averageAtCurrentHour = averageData.interpolatedValue(at: effectiveDate) ?? 0

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
			projectedTotal: projectedTotal,
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
			let todayCache = try SharedEnergyDataManager.shared.readEnergyData()

			// Read average data from weekday-specific cache
			let cacheManager = AverageDataCacheManager()
			let averageCache = cacheManager.load(for: Weekday.today)
			let averageHourlyData = averageCache?.toHourlyEnergyData() ?? []
			let projectedTotal = averageCache?.projectedTotal ?? 0
			let averageAtCurrentHour = averageHourlyData.interpolatedValue(at: todayCache.lastUpdated) ?? 0

			return EnergyWidgetEntry(
				date: todayCache.lastUpdated,
				todayTotal: todayCache.todayTotal,
				averageAtCurrentHour: averageAtCurrentHour,
				projectedTotal: projectedTotal,
				moveGoal: todayCache.moveGoal,
				todayHourlyData: todayCache.todayHourlyData.map { $0.toHourlyEnergyData() },
				averageHourlyData: averageHourlyData,
				configuration: configuration,
				isAuthorized: true  // Cached data implies previous authorization
			)
		} catch {
			Self.logger.warning("Failed to load cached data in loadCachedEntry()")
			return EnergyWidgetEntry(
				date: date,
				todayTotal: 0,
				averageAtCurrentHour: 0,
				projectedTotal: 0,
				moveGoal: loadCachedMoveGoal(),
				todayHourlyData: [],
				averageHourlyData: [],
				configuration: configuration,
				isAuthorized: false  // No cache = unauthorized
			)
		}
	}

	/// Load cached move goal (goals don't change frequently)
	private func loadCachedMoveGoal() -> Double {
		do {
			let sharedData = try SharedEnergyDataManager.shared.readEnergyData()
			return sharedData.moveGoal
		} catch {
			return 800  // Default fallback
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
		// Show unauthorized view if not authorized
		if !entry.isAuthorized {
			WidgetUnauthorizedView()
				.widgetURL(URL(string: "healthtrends://"))
		} else if entry.configuration.tapAction == .refresh {
			// Tap to refresh - use AppIntent button
			Button(intent: RefreshWidgetIntent()) {
				contentView
			}
			.buttonStyle(.plain)
		} else {
			// Tap to open app - use default widgetURL behavior
			contentView
				.widgetURL(URL(string: "healthtrends://"))
		}
	}

	private var contentView: some View {
		EnergyTrendView(
			todayTotal: entry.todayTotal,
			averageAtCurrentHour: entry.averageAtCurrentHour,
			todayHourlyData: entry.todayHourlyData,
			averageHourlyData: entry.averageHourlyData,
			moveGoal: entry.moveGoal,
			projectedTotal: entry.projectedTotal,
			effectiveNow: entry.date
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

//#Preview(as: .systemMedium) {
//    DailyActiveEnergyWidget()
//} timeline: {
//    EnergyWidgetEntry.placeholder
//}

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
