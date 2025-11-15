//
//  DailyActiveEnergyWidget.swift
//  DailyActiveEnergyWidget
//
//  Created by Nick Christensen on 2025-11-14.
//

import WidgetKit
import SwiftUI

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
        // For widget gallery - return quickly with real data if available, otherwise placeholder
        if let entry = loadCurrentEntry() {
            completion(entry)
        } else {
            completion(.placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergyWidgetEntry>) -> Void) {
        // Generate timeline entries for the next few hours
        let currentDate = Date()
        var entries: [EnergyWidgetEntry] = []

        // Load current data from shared container
        if let currentEntry = loadCurrentEntry() {
            entries.append(currentEntry)
        } else {
            // Fallback to placeholder if no data available
            entries.append(.placeholder)
        }

        // Generate entries for the next 4 hours (every 15 minutes)
        // Each entry will re-read from shared container when its time comes
        for minuteOffset in stride(from: 15, through: 240, by: 15) {
            if let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate),
               let entry = loadCurrentEntry(forDate: entryDate) {
                entries.append(entry)
            }
        }

        // Reload timeline when entries run out
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    /// Load current energy data from shared container
    private func loadCurrentEntry(forDate date: Date = Date()) -> EnergyWidgetEntry? {
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
            print("Widget failed to load energy data: \(error)")
            return nil
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
