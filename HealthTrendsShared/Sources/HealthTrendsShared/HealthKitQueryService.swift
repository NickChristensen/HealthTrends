import Foundation
import HealthKit

/// Shared HealthKit query service for use by both app and widget
/// Provides efficient queries for energy data
public final class HealthKitQueryService: Sendable {
    private let healthStore: HKHealthStore
    private let calendar: Calendar

    public init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    // MARK: - Public API

    /// Fetch today's hourly energy breakdown
    /// Returns cumulative calories at each hour boundary
    public func fetchTodayHourlyTotals() async throws -> [HourlyEnergyData] {
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        // Fetch hourly data (non-cumulative)
        let hourlyData = try await fetchHourlyData(from: startOfDay, to: now, type: activeEnergyType)

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

        return cumulativeData
    }

    /// Fetch average Active Energy data from past 30 days
    /// Returns "Total" and "Average" (see CLAUDE.md)
    public func fetchAverageData() async throws -> (total: Double, hourlyData: [HourlyEnergyData]) {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // Get data from 30 days ago to yesterday (excluding today)
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return (0, [])
        }

        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        // Fetch daily totals for "Total" metric
        let dailyTotals = try await fetchDailyTotals(from: thirtyDaysAgo, to: yesterday, type: activeEnergyType)
        let projectedTotal = dailyTotals.isEmpty ? 0 : dailyTotals.reduce(0, +) / Double(dailyTotals.count)

        // Fetch cumulative average hourly pattern
        let averageHourlyData = try await fetchCumulativeAverageHourlyPattern(from: thirtyDaysAgo, to: yesterday, type: activeEnergyType)

        return (projectedTotal, averageHourlyData)
    }

    // MARK: - Private Helpers

    /// Fetch hourly data for a specific time range
    private func fetchHourlyData(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [HourlyEnergyData] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        var hourlyTotals: [Date: Double] = [:]

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
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
            let hourStart = calendar.dateInterval(of: .hour, for: sample.startDate)?.start ?? sample.startDate
            let calories = sample.quantity.doubleValue(for: .kilocalorie())
            hourlyTotals[hourStart, default: 0] += calories
        }

        // Convert to array and sort
        return hourlyTotals.map { HourlyEnergyData(hour: $0.key, calories: $0.value) }
            .sorted { $0.hour < $1.hour }
    }

    /// Fetch daily totals for a date range
    private func fetchDailyTotals(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [Double] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        var dailyTotals: [Date: Double] = [:]

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
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
            let calories = sample.quantity.doubleValue(for: .kilocalorie())
            dailyTotals[dayStart, default: 0] += calories
        }

        return Array(dailyTotals.values)
    }

    /// Fetch cumulative average hourly pattern across multiple days
    private func fetchCumulativeAverageHourlyPattern(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [HourlyEnergyData] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }

        // Group samples by day, then calculate cumulative totals for each day
        var dailyCumulativeData: [Date: [Int: Double]] = [:] // [dayStart: [hour: cumulativeCalories]]

        for sample in samples {
            let dayStart = calendar.startOfDay(for: sample.startDate)
            let hour = calendar.component(.hour, from: sample.startDate)
            let calories = sample.quantity.doubleValue(for: .kilocalorie())

            if dailyCumulativeData[dayStart] == nil {
                dailyCumulativeData[dayStart] = [:]
            }
            dailyCumulativeData[dayStart]![hour, default: 0] += calories
        }

        // Convert each day's hourly data to cumulative
        var dailyCumulative: [Date: [Int: Double]] = [:] // [dayStart: [hour: cumulativeTotalByHour]]

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
        hourlyData.append(contentsOf: averageCumulativeByHour.map { hour, avgCumulative in
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
