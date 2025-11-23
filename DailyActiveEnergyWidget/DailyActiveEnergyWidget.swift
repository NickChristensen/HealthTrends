//
//  DailyActiveEnergyWidget.swift
//  DailyActiveEnergyWidget
//
//  Created by Nick Christensen on 2025-11-14.
//

import WidgetKit
import SwiftUI
import HealthKit
import HealthTrendsShared

// MARK: - Timeline Entry

struct EnergyWidgetEntry: TimelineEntry {
    let date: Date
    let todayTotal: Double
    let averageAtCurrentHour: Double
    let projectedTotal: Double
    let moveGoal: Double
    let todayHourlyData: [HourlyEnergyData]
    let averageHourlyData: [HourlyEnergyData]

    /// Placeholder entry with sample data for widget gallery
    static var placeholder: EnergyWidgetEntry {
        EnergyWidgetEntry(
            date: Date(),
            todayTotal: 467,
            averageAtCurrentHour: 389,
            projectedTotal: 1034,
            moveGoal: 800,
            todayHourlyData: generateSampleTodayData(),
            averageHourlyData: generateSampleAverageData()
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

struct EnergyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergyWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (EnergyWidgetEntry) -> Void) {
        // For widget gallery - return quickly with cached data
        let entry = loadCachedEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergyWidgetEntry>) -> Void) {
        let currentDate = Date()

        // Use hybrid approach: query HealthKit for today, use cached average data
        Task {
            let entry = await loadFreshEntry(forDate: currentDate)

            // Schedule next refresh in 15 minutes
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))

            completion(timeline)
        }
    }

    /// Load fresh entry using hybrid approach: query HealthKit for today, use cached average
    private func loadFreshEntry(forDate date: Date = Date()) async -> EnergyWidgetEntry {
        let healthKit = HealthKitQueryService()
        let cacheManager = AverageDataCacheManager()

        // Try to get fresh today's data from HealthKit
        let todayData: [HourlyEnergyData]
        let todayTotal: Double

        do {
            let hourlyTotals = try await healthKit.fetchTodayHourlyTotals()
            todayData = hourlyTotals
            todayTotal = hourlyTotals.last?.calories ?? 0
        } catch {
            print("Widget failed to fetch today's HealthKit data: \(error)")
            // Fallback to cached data
            return loadCachedEntry(forDate: date)
        }

        // Load or refresh average data cache
        let averageData: [HourlyEnergyData]
        let projectedTotal: Double

        if cacheManager.shouldRefresh() {
            // Cache is stale or missing - refresh it
            do {
                let (total, hourlyData) = try await healthKit.fetchAverageData()
                projectedTotal = total
                averageData = hourlyData

                // Save to cache for future use
                let cache = AverageDataCache(
                    averageHourlyPattern: hourlyData,
                    projectedTotal: total,
                    cachedAt: Date(),
                    cacheVersion: 1
                )
                try? cacheManager.save(cache)
            } catch {
                print("Widget failed to fetch average data: \(error)")
                // Try to use stale cache as fallback
                if let staleCache = cacheManager.load() {
                    averageData = staleCache.toHourlyEnergyData()
                    projectedTotal = staleCache.projectedTotal
                } else {
                    // No cache available - return today-only entry
                    return EnergyWidgetEntry(
                        date: date,
                        todayTotal: todayTotal,
                        averageAtCurrentHour: 0,
                        projectedTotal: 0,
                        moveGoal: loadCachedMoveGoal(),
                        todayHourlyData: todayData,
                        averageHourlyData: []
                    )
                }
            }
        } else {
            // Use fresh cache
            if let cache = cacheManager.load() {
                averageData = cache.toHourlyEnergyData()
                projectedTotal = cache.projectedTotal
            } else {
                // Shouldn't happen (shouldRefresh would return true), but handle gracefully
                averageData = []
                projectedTotal = 0
            }
        }

        // Calculate interpolated average at current hour
        let averageAtCurrentHour = averageData.interpolatedValue(at: date) ?? 0

        return EnergyWidgetEntry(
            date: date,
            todayTotal: todayTotal,
            averageAtCurrentHour: averageAtCurrentHour,
            projectedTotal: projectedTotal,
            moveGoal: loadCachedMoveGoal(),
            todayHourlyData: todayData,
            averageHourlyData: averageData
        )
    }

    /// Load cached entry from shared container (fallback)
    private func loadCachedEntry(forDate date: Date = Date()) -> EnergyWidgetEntry {
        do {
            let sharedData = try SharedEnergyDataManager.shared.readEnergyData()
            return EnergyWidgetEntry(
                date: date,
                todayTotal: sharedData.todayTotal,
                averageAtCurrentHour: sharedData.averageAtCurrentHour,
                projectedTotal: sharedData.projectedTotal,
                moveGoal: sharedData.moveGoal,
                todayHourlyData: sharedData.todayHourlyData.map { $0.toHourlyEnergyData() },
                averageHourlyData: sharedData.averageHourlyData.map { $0.toHourlyEnergyData() }
            )
        } catch {
            print("Widget failed to load cached energy data: \(error)")
            return .placeholder
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

// MARK: - Widget View

struct DailyActiveEnergyWidgetEntryView: View {
    var entry: EnergyWidgetProvider.Entry

    var body: some View {
        EnergyTrendView(
            todayTotal: entry.todayTotal,
            averageAtCurrentHour: entry.averageAtCurrentHour,
            todayHourlyData: entry.todayHourlyData,
            averageHourlyData: entry.averageHourlyData,
            moveGoal: entry.moveGoal,
            projectedTotal: entry.projectedTotal
        )
    }
}

// MARK: - Widget Configuration

struct DailyActiveEnergyWidget: Widget {
    let kind: String = "DailyActiveEnergyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EnergyWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                DailyActiveEnergyWidgetEntryView(entry: entry)
                    .containerBackground(Color(.systemBackground), for: .widget)
            } else {
                DailyActiveEnergyWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(.systemBackground))
            }
        }
        .configurationDisplayName("Daily Active Energy")
        .description("Track your active energy compared to your 30-day average")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    DailyActiveEnergyWidget()
} timeline: {
    EnergyWidgetEntry.placeholder
}

#Preview(as: .systemLarge) {
    DailyActiveEnergyWidget()
} timeline: {
    EnergyWidgetEntry.placeholder
}
