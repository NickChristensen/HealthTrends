//
//  ContentView.swift
//  HealthTrends
//
//  Created by Nick Christensen on 2025-10-04.
//

import SwiftUI
import Combine
import WidgetKit

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var authorizationRequested = false
    @State private var lastRefreshMinute: Int = Calendar.current.component(.minute, from: Date())
    @Environment(\.scenePhase) private var scenePhase
    #if targetEnvironment(simulator)
    @State private var showingDevTools = false
    #endif

    // Timer that checks every second for minute boundary changes
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                if healthKitManager.isAuthorized {
                    // Medium Widget Preview
                    WidgetPreviewContainer(family: .systemMedium, label: "Medium Widget") {
                        EnergyTrendView(
                            todayTotal: healthKitManager.todayTotal,
                            averageAtCurrentHour: healthKitManager.averageAtCurrentHour,
                            todayHourlyData: healthKitManager.todayHourlyData,
                            averageHourlyData: healthKitManager.averageHourlyData,
                            moveGoal: healthKitManager.moveGoal,
                            projectedTotal: healthKitManager.projectedTotal
                        )
                        .id(healthKitManager.refreshCount)
                    }

                    // Large Widget Preview
                    WidgetPreviewContainer(family: .systemLarge, label: "Large Widget") {
                        EnergyTrendView(
                            todayTotal: healthKitManager.todayTotal,
                            averageAtCurrentHour: healthKitManager.averageAtCurrentHour,
                            todayHourlyData: healthKitManager.todayHourlyData,
                            averageHourlyData: healthKitManager.averageHourlyData,
                            moveGoal: healthKitManager.moveGoal,
                            projectedTotal: healthKitManager.projectedTotal
                        )
                        .id(healthKitManager.refreshCount)
                    }
                } else if authorizationRequested {
                    Text("⚠️ Waiting for authorization...")
                        .foregroundStyle(.orange)
                } else {
                    Text("Needs HealthKit access")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color("AppBackground"))
        #if targetEnvironment(simulator)
        .onShake {
            showingDevTools = true
        }
        .sheet(isPresented: $showingDevTools) {
            DevelopmentToolsSheet(healthKitManager: healthKitManager)
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { showingDevTools = true }) {
                Image(systemName: "wrench.and.screwdriver")
                    .frame(width: 44, height: 44)
                    .font(.system(size: 20))
            }
            .buttonStyle(.glass)
            .padding()
        }
        #endif
        .onReceive(timer) { _ in
            // Only refresh when we cross a minute boundary
            let currentMinute = Calendar.current.component(.minute, from: Date())
            guard currentMinute != lastRefreshMinute else { return }
            lastRefreshMinute = currentMinute

            // Refresh data at the start of each new minute
            Task {
                guard healthKitManager.isAuthorized else { return }
                try? await healthKitManager.fetchEnergyData()

                do {
                    try await healthKitManager.fetchMoveGoal()
                } catch {
                    print("Failed to fetch move goal (using cached): \(error)")
                }

                // Reload widgets after updating data
                // (doesn't count against budget when app is in foreground)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .task {
            // Request HealthKit authorization when view appears
            guard !authorizationRequested else { return }
            authorizationRequested = true

            do {
                try await healthKitManager.requestAuthorization()

                // Fetch data after authorization
                try await healthKitManager.fetchEnergyData()
                try await healthKitManager.fetchMoveGoal()

                // Reload widgets with initial data
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                print("HealthKit error: \(error)")
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Refresh data when app comes to foreground
            if newPhase == .active && healthKitManager.isAuthorized {
                Task {
                    try? await healthKitManager.fetchEnergyData()

                    do {
                        try await healthKitManager.fetchMoveGoal()
                    } catch {
                        print("Failed to fetch move goal (using cached): \(error)")
                    }

                    // Reload widgets when app is foregrounded
                    // (doesn't count against budget when app is in foreground)
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
