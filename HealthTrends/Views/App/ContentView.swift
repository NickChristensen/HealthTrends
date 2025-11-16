//
//  ContentView.swift
//  HealthTrends
//
//  Created by Nick Christensen on 2025-10-04.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var authorizationRequested = false
    #if targetEnvironment(simulator)
    @State private var showingDevTools = false
    #endif

    // Timer that fires every minute to refresh data
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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
            // Refresh data every minute while app is active
            Task {
                guard healthKitManager.isAuthorized else { return }
                try? await healthKitManager.fetchEnergyData()

                do {
                    try await healthKitManager.fetchMoveGoal()
                } catch {
                    print("Failed to fetch move goal (using cached): \(error)")
                }
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
            } catch {
                print("HealthKit error: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
