import Foundation
import Testing

@testable import HealthTrendsShared

/// Unit tests for AverageDataCache and Weekday structures
@Suite("AverageDataCache Tests")
struct AverageDataCacheTests {

	// MARK: - Weekday Tests

	@Test("Weekday initializes from Sunday date correctly")
	func testWeekdayFromSunday() {
		// GIVEN: A Sunday date
		let calendar = Calendar.current
		var components = DateComponents()
		components.year = 2025
		components.month = 1
		components.day = 5  // Sunday, January 5, 2025
		let sunday = calendar.date(from: components)!

		// WHEN: Creating Weekday from date
		let weekday = Weekday(date: sunday)

		// THEN: Should be Sunday (1)
		#expect(weekday == .sunday)
		#expect(weekday?.rawValue == 1)
	}

	@Test("Weekday initializes from Saturday date correctly")
	func testWeekdayFromSaturday() {
		// GIVEN: A Saturday date
		let calendar = Calendar.current
		var components = DateComponents()
		components.year = 2025
		components.month = 1
		components.day = 11  // Saturday, January 11, 2025
		let saturday = calendar.date(from: components)!

		// WHEN: Creating Weekday from date
		let weekday = Weekday(date: saturday)

		// THEN: Should be Saturday (7)
		#expect(weekday == .saturday)
		#expect(weekday?.rawValue == 7)
	}

	@Test("Weekday uses start of day for weekday calculation")
	func testWeekdayUsesStartOfDay() {
		// GIVEN: A Saturday date at 11:59 PM
		let calendar = Calendar.current
		var components = DateComponents()
		components.year = 2025
		components.month = 1
		components.day = 11  // Saturday
		components.hour = 23
		components.minute = 59
		let saturdayNight = calendar.date(from: components)!

		// WHEN: Creating Weekday from date
		let weekday = Weekday(date: saturdayNight)

		// THEN: Should still be Saturday (not Sunday)
		#expect(weekday == .saturday)
	}

	// MARK: - AverageDataCache Tests

	@Test("Cache is fresh when created today")
	func testCacheFreshToday() {
		// GIVEN: Cache created right now
		let cache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1000.0,
			cachedAt: Date()
		)

		// THEN: Should not be stale
		#expect(cache.isStale == false)
	}

	@Test("Cache is stale when created yesterday")
	func testCacheStaleYesterday() {
		// GIVEN: Cache created yesterday
		let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
		let cache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1000.0,
			cachedAt: yesterday
		)

		// THEN: Should be stale
		#expect(cache.isStale == true)
	}

	@Test("Cache is stale when created last week")
	func testCacheStaleLastWeek() {
		// GIVEN: Cache created 7 days ago
		let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
		let cache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1000.0,
			cachedAt: lastWeek
		)

		// THEN: Should be stale
		#expect(cache.isStale == true)
	}

	@Test("Cache roundtrip conversion preserves data")
	func testCacheRoundtripConversion() {
		// GIVEN: Original hourly data
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())

		let originalData = [
			HourlyEnergyData(
				hour: calendar.date(byAdding: .hour, value: 9, to: today)!,
				calories: 100.0
			),
			HourlyEnergyData(
				hour: calendar.date(byAdding: .hour, value: 10, to: today)!,
				calories: 200.0
			),
		]

		// WHEN: Creating cache and converting back
		let cache = AverageDataCache(
			averageHourlyPattern: originalData,
			projectedTotal: 1000.0
		)
		let convertedData = cache.toHourlyEnergyData()

		// THEN: Data should be preserved
		#expect(convertedData.count == 2)
		#expect(convertedData[0].calories == 100.0)
		#expect(convertedData[1].calories == 200.0)
		#expect(calendar.isDate(convertedData[0].hour, equalTo: originalData[0].hour, toGranularity: .second))
		#expect(calendar.isDate(convertedData[1].hour, equalTo: originalData[1].hour, toGranularity: .second))
	}

	// MARK: - WeekdayAverageCache Tests

	@Test("WeekdayAverageCache stores and retrieves cache for specific weekday")
	func testWeekdayCacheGetAndSet() {
		// GIVEN: Empty weekday cache
		var weekdayCache = WeekdayAverageCache()

		// WHEN: Adding Saturday cache
		let saturdayCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1013.0
		)
		weekdayCache = weekdayCache.updating(cache: saturdayCache, for: .saturday)

		// THEN: Should retrieve Saturday cache
		let retrieved = weekdayCache.cache(for: .saturday)
		#expect(retrieved != nil)
		#expect(retrieved?.projectedTotal == 1013.0)
	}

	@Test("WeekdayAverageCache returns nil for missing weekday")
	func testWeekdayCacheMissingWeekday() {
		// GIVEN: Empty weekday cache
		let weekdayCache = WeekdayAverageCache()

		// WHEN: Requesting cache for Monday
		let result = weekdayCache.cache(for: .monday)

		// THEN: Should return nil
		#expect(result == nil)
	}

	@Test("WeekdayAverageCache updates existing weekday cache")
	func testWeekdayCacheUpdate() {
		// GIVEN: Weekday cache with Saturday data
		var weekdayCache = WeekdayAverageCache()
		let oldCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1000.0
		)
		weekdayCache = weekdayCache.updating(cache: oldCache, for: .saturday)

		// WHEN: Updating Saturday cache
		let newCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1100.0
		)
		weekdayCache = weekdayCache.updating(cache: newCache, for: .saturday)

		// THEN: Should have new value
		let retrieved = weekdayCache.cache(for: .saturday)
		#expect(retrieved?.projectedTotal == 1100.0)
	}

	@Test("WeekdayAverageCache stores different caches for different weekdays")
	func testWeekdayCacheMultipleWeekdays() {
		// GIVEN: Empty weekday cache
		var weekdayCache = WeekdayAverageCache()

		// WHEN: Adding caches for different weekdays
		let saturdayCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1013.0
		)
		let mondayCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 800.0
		)

		weekdayCache = weekdayCache.updating(cache: saturdayCache, for: .saturday)
		weekdayCache = weekdayCache.updating(cache: mondayCache, for: .monday)

		// THEN: Should retrieve correct cache for each weekday
		#expect(weekdayCache.cache(for: .saturday)?.projectedTotal == 1013.0)
		#expect(weekdayCache.cache(for: .monday)?.projectedTotal == 800.0)
		#expect(weekdayCache.cache(for: .tuesday) == nil)
	}

	// MARK: - Serialization Tests

	@Test("AverageDataCache encodes and decodes correctly")
	func testCacheSerialization() throws {
		// GIVEN: Cache with data
		let calendar = Calendar.current
		let today = calendar.startOfDay(for: Date())
		let hourlyData = [
			HourlyEnergyData(
				hour: calendar.date(byAdding: .hour, value: 10, to: today)!,
				calories: 500.0
			)
		]

		let originalCache = AverageDataCache(
			averageHourlyPattern: hourlyData,
			projectedTotal: 1013.0,
			cachedAt: today,
			cacheVersion: 2
		)

		// WHEN: Encoding and decoding
		let encoder = JSONEncoder()
		let decoder = JSONDecoder()
		encoder.dateEncodingStrategy = .iso8601
		decoder.dateDecodingStrategy = .iso8601

		let encoded = try encoder.encode(originalCache)
		let decoded = try decoder.decode(AverageDataCache.self, from: encoded)

		// THEN: Should preserve all data
		#expect(decoded.projectedTotal == 1013.0)
		#expect(decoded.cacheVersion == 2)
		#expect(decoded.averageHourlyPattern.count == 1)
		#expect(decoded.averageHourlyPattern[0].calories == 500.0)
	}

	@Test("WeekdayAverageCache encodes and decodes correctly")
	func testWeekdayCacheSerialization() throws {
		// GIVEN: Weekday cache with multiple weekdays
		var weekdayCache = WeekdayAverageCache()

		let saturdayCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 1013.0
		)
		let mondayCache = AverageDataCache(
			averageHourlyPattern: [],
			projectedTotal: 800.0
		)

		weekdayCache = weekdayCache.updating(cache: saturdayCache, for: .saturday)
		weekdayCache = weekdayCache.updating(cache: mondayCache, for: .monday)

		// WHEN: Encoding and decoding
		let encoder = JSONEncoder()
		let decoder = JSONDecoder()
		encoder.dateEncodingStrategy = .iso8601
		decoder.dateDecodingStrategy = .iso8601

		let encoded = try encoder.encode(weekdayCache)
		let decoded = try decoder.decode(WeekdayAverageCache.self, from: encoded)

		// THEN: Should preserve all weekday caches
		#expect(decoded.cache(for: .saturday)?.projectedTotal == 1013.0)
		#expect(decoded.cache(for: .monday)?.projectedTotal == 800.0)
		#expect(decoded.cache(for: .tuesday) == nil)
	}
}
