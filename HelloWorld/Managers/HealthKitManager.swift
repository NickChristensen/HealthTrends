import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todayTotal: Double = 0
    @Published var averageAtCurrentHour: Double = 0  // Average cumulative calories BY current hour (see CLAUDE.md)
    @Published var projectedTotal: Double = 0  // Average of complete daily totals (see CLAUDE.md)
    @Published var moveGoal: Double = 0  // Daily Move goal from Fitness app
    @Published var todayHourlyData: [HourlyEnergyData] = []
    @Published var averageHourlyData: [HourlyEnergyData] = []

    // Check if HealthKit is available on this device
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // Request authorization to read and write Active Energy data
    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        // Types we want to read and write
        let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        let activitySummaryType = HKObjectType.activitySummaryType()

        let typesToRead: Set<HKObjectType> = [activeEnergyType, activitySummaryType]
        let typesToWrite: Set<HKSampleType> = [activeEnergyType]

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

        // For read-only permissions, HealthKit doesn't reveal if user granted access (privacy protection)
        // We'll assume authorization completed successfully if no error was thrown
        isAuthorized = true
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
    func generateSampleData() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        // Clear existing data first to avoid duplicates
        try await clearSampleData()

        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let calendar = Calendar.current
        let now = Date()

        // Generate data for the past 60 days
        var samplesToSave: [HKQuantitySample] = []

        for dayOffset in 0..<60 {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)) else {
                continue
            }

            // For today (dayOffset == 0), only generate up to current hour
            // For past days, generate all 24 hours
            let maxHour = dayOffset == 0 ? calendar.component(.hour, from: now) : 23

            // Generate hourly data points for each day
            for hour in 0...maxHour {
                guard let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayStart) else {
                    continue
                }

                // Don't generate data in the future
                guard hourStart <= now else {
                    continue
                }

                // Generate realistic calories per hour
                let baseCalories = generateRealisticCalories(for: hour)
                let calories = baseCalories + Double.random(in: -10...10)

                let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: max(0, calories))
                let sample = HKQuantitySample(
                    type: activeEnergyType,
                    quantity: quantity,
                    start: hourStart,
                    end: calendar.date(byAdding: .hour, value: 1, to: hourStart)!
                )

                samplesToSave.append(sample)
            }
        }

        try await healthStore.save(samplesToSave)
    }

    // Generate realistic calorie burn based on time of day
    private func generateRealisticCalories(for hour: Int) -> Double {
        switch hour {
        case 0..<6:   return Double.random(in: 5...15)     // Sleep/early morning
        case 6..<7:   return Double.random(in: 20...40)    // Wake up
        case 7:       return Double.random(in: 150...250)  // Morning workout
        case 8..<9:   return Double.random(in: 20...40)    // Post-workout
        case 9..<12:  return Double.random(in: 25...50)    // Morning activity
        case 12..<14: return Double.random(in: 30...60)    // Lunch/midday
        case 14..<17: return Double.random(in: 25...55)    // Afternoon
        case 17..<20: return Double.random(in: 35...70)    // Evening activity
        case 20..<22: return Double.random(in: 20...40)    // Evening
        default:      return Double.random(in: 10...20)    // Late night
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

        let (today, average) = try await (todayData, averageData)

        self.todayTotal = today.total
        self.todayHourlyData = today.hourlyData
        self.projectedTotal = average.total
        self.averageHourlyData = average.hourlyData

        // Calculate interpolated average at current minute
        self.averageAtCurrentHour = average.hourlyData.interpolatedValue(at: Date()) ?? 0

        // Write data to shared container for widget access
        try? SharedEnergyDataManager.shared.writeEnergyData(
            todayTotal: self.todayTotal,
            averageAtCurrentHour: self.averageAtCurrentHour,
            projectedTotal: self.projectedTotal,
            moveGoal: self.moveGoal,
            todayHourlyData: self.todayHourlyData,
            averageHourlyData: self.averageHourlyData
        )
    }

    // Fetch Move goal from Activity Summary
    func fetchMoveGoal() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        #if targetEnvironment(simulator)
        // Simulator doesn't have Fitness app, use mock goal for development
        self.moveGoal = 800
        #else
        let calendar = Calendar.current
        let now = Date()

        // Create predicate for today's activity summary
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        dateComponents.calendar = calendar

        let predicate = HKQuery.predicateForActivitySummary(with: dateComponents)

        let activitySummary = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKActivitySummary?, Error>) in
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
            self.moveGoal = goalInKilocalories
        } else {
            self.moveGoal = 0
        }
        #endif
    }

    // Fetch today's Active Energy data
    // Returns cumulative calories at each hour (see CLAUDE.md for "Today" definition)
    private func fetchTodayData() async throws -> (total: Double, hourlyData: [HourlyEnergyData]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        // Fetch hourly data (non-cumulative)
        let hourlyData = try await fetchHourlyData(from: startOfDay, to: now, type: activeEnergyType)

        let currentHourStart = calendar.dateInterval(of: .hour, for: now)!.start

        // Filter out current incomplete hour for completed hours
        let completeHours = hourlyData.filter { $0.hour < currentHourStart }

        // Convert to cumulative data (running sum)
        // Timestamps represent END of each complete hour
        var cumulativeData: [HourlyEnergyData] = []

        // Start with 0 at midnight to show beginning of day
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
        let total = runningTotal + currentHourCalories

        if currentHourCalories > 0 {
            cumulativeData.append(HourlyEnergyData(hour: now, calories: total))
        }

        return (total, cumulativeData)
    }

    // Fetch average Active Energy data from past 30 days
    // Returns "Total" and "Average" (see CLAUDE.md)
    private func fetchAverageData() async throws -> (total: Double, hourlyData: [HourlyEnergyData]) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        // Get data from 30 days ago to yesterday (excluding today)
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday),
              let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else {
            return (0, [])
        }

        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!

        // Fetch daily totals for "Total" metric (average of complete daily totals)
        let dailyTotals = try await fetchDailyTotals(from: thirtyDaysAgo, to: yesterday, type: activeEnergyType)
        let projectedTotal = dailyTotals.isEmpty ? 0 : dailyTotals.reduce(0, +) / Double(dailyTotals.count)

        // Fetch cumulative average hourly pattern for "Average" metric
        let averageHourlyData = try await fetchCumulativeAverageHourlyPattern(from: thirtyDaysAgo, to: yesterday, type: activeEnergyType)

        return (projectedTotal, averageHourlyData)
    }

    // Fetch hourly data for a specific time range
    private func fetchHourlyData(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [HourlyEnergyData] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let calendar = Calendar.current

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

    // Fetch daily totals for a date range
    private func fetchDailyTotals(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [Double] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let calendar = Calendar.current

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

    // Fetch cumulative average hourly pattern across multiple days
    // For each hour H, calculates average of cumulative totals BY that hour (see CLAUDE.md for "Average")
    private func fetchCumulativeAverageHourlyPattern(from startDate: Date, to endDate: Date, type: HKQuantityType) async throws -> [HourlyEnergyData] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let calendar = Calendar.current

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

        // Start with 0 at midnight to show beginning of day
        hourlyData.append(HourlyEnergyData(hour: startOfToday, calories: 0))

        // Timestamps should represent END of hour (hour 0 = 1 AM, hour 23 = midnight next day)
        hourlyData.append(contentsOf: averageCumulativeByHour.map { hour, avgCumulative in
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
