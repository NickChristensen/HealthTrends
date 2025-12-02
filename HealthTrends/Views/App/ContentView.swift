//
//  ContentView.swift
//  HealthTrends
//
//  Created by Nick Christensen on 2025-10-04.
//

import SwiftUI

struct ContentView: View {
	@StateObject private var healthKitManager = HealthKitManager()
	@State private var showingDevTools = false
	@State private var isRequestingAuthorization = false

	var body: some View {
		ZStack {
			Color("AppBackground")
				.ignoresSafeArea()

			VStack(spacing: 32) {
				Spacer()

				// App Icon
				Image("AppIconImage")
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 128, height: 128)
				VStack(spacing: 16) {
					Text("Health Trends")
						.font(.title)
						.fontWeight(.bold)

					Text(
						"This app has no user interface. It provides widgets for your home screen. [Tap here](https://support.apple.com/en-us/118610) for help adding home screen widgets."
					)
					.tint(.accentColor)  // optional: control link color
					.font(.body)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal)
				}

				Spacer()

				VStack(spacing: 24) {
					if !healthKitManager.isAuthorized {
						Button(action: {
							Task {
								isRequestingAuthorization = true
								do {
									try await healthKitManager
										.requestAuthorization()
								} catch {
									print(
										"HealthKit authorization error: \(error)"
									)
								}
								isRequestingAuthorization = false
							}
						}) {
							HStack {
								if isRequestingAuthorization {
									ProgressView()
										.tint(Color(uiColor: .systemBackground))
								} else {
									Text("Grant Health Access")
								}
							}
							.frame(maxWidth: .infinity)
							.padding()
							.background(Color.accentColor)
							.foregroundStyle(.background)
							.fontWeight(.semibold)
							.cornerRadius(12)
						}
						.disabled(isRequestingAuthorization)
						.padding(.horizontal)
					} else {
						Color.clear
							.frame(height: 52)  // Match button height
							.padding(.horizontal)

					}
				}
				.padding(.bottom, 32)
			}
		}
		.onShake {
			showingDevTools = true
		}
		.sheet(isPresented: $showingDevTools) {
			DevelopmentToolsSheet(healthKitManager: healthKitManager)
		}
		#if targetEnvironment(simulator)
			.overlay(alignment: .bottomTrailing) {
				Button(action: { showingDevTools = true }) {
					Image(systemName: "wrench.and.screwdriver")
					.frame(width: 44, height: 44)
					.font(.system(size: 20))
				}
				.buttonStyle(.glass)
				.padding(.trailing)
			}
		#endif
		.task {
			// Check authorization status when view appears
			await healthKitManager.checkAuthorizationStatus()
		}
	}
}

#Preview {
	ContentView()
}
