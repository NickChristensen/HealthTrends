import HealthTrendsShared
import SwiftUI
import WidgetKit

/// UIKit DatePicker wrapped for countdown timer mode
struct CountdownTimerPicker: UIViewRepresentable {
	@Binding var duration: TimeInterval

	func makeUIView(context: Context) -> UIDatePicker {
		let picker = UIDatePicker()
		picker.datePickerMode = .countDownTimer
		picker.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .valueChanged)
		return picker
	}

	func updateUIView(_ picker: UIDatePicker, context: Context) {
		picker.countDownDuration = duration
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(duration: $duration)
	}

	class Coordinator: NSObject {
		let duration: Binding<TimeInterval>

		init(duration: Binding<TimeInterval>) {
			self.duration = duration
		}

		@objc func valueChanged(_ picker: UIDatePicker) {
			duration.wrappedValue = picker.countDownDuration
		}
	}
}

/// State for action buttons with icon transitions
enum ActionButtonState {
	case idle
	case loading
	case completed
}

/// Reusable action button with icon state transitions
struct ActionButton: View {
	let title: String
	let icon: String
	let action: () async -> Void

	@State private var state: ActionButtonState = .idle

	var body: some View {
		Button(action: {
			Task {
				state = .loading
				await action()
				state = .completed

				// Revert to original icon after 2 seconds
				try? await Task.sleep(for: .seconds(2))
				state = .idle
			}
		}) {
			HStack(spacing: 12) {
				iconView
					.frame(width: 24, height: 24)
				Text(title)
				Spacer()
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.foregroundStyle(Color.accentColor)
		.disabled(state == .loading)
	}

	@ViewBuilder
	private var iconView: some View {
		switch state {
		case .idle:
			Image(systemName: icon)
		case .loading:
			ProgressView()
				.progressViewStyle(.circular)
		case .completed:
			Image(systemName: "checkmark.circle.fill")
		}
	}
}

/// Development tools sheet content (simulator only)
struct DevelopmentToolsSheet: View {
	var healthKitManager: HealthKitManager
	@Environment(\.dismiss) private var dismiss

	@State private var showingPermissionError = false
	@State private var permissionErrorMessage = ""
	@State private var offsetSampleData: Bool = false
	@State private var selectedDuration: TimeInterval = 60 * 60  // Default to 1 hour
	@State private var cacheViewRefreshID = UUID()

	var body: some View {
		NavigationStack {
			List {
				#if targetEnvironment(simulator)
					Section {
						Toggle("Offset sample data", isOn: $offsetSampleData)
							.listRowBackground(Color(.systemBackground))

						if offsetSampleData {
							CountdownTimerPicker(duration: $selectedDuration)
								.frame(maxWidth: .infinity)
								.listRowBackground(Color(.systemBackground))
						}

						ActionButton(
							title: "Generate sample data",
							icon: "testtube.2",
						) {
							do {
								let dataAge = offsetSampleData ? selectedDuration : 0
								try await healthKitManager.generateSampleData(
									dataAge: dataAge)
								// Refresh all caches after generating
								try await healthKitManager.populateAllCaches()
								cacheViewRefreshID = UUID()
							} catch {
								permissionErrorMessage =
									"Write permission is required to generate sample data. Please allow access when prompted."
								showingPermissionError = true
								print("Failed to generate sample data: \(error)")
							}
						}
						.listRowBackground(Color(.systemBackground))
					} footer: {
						if offsetSampleData {
							Text("Generate data up to the specified time in the past")
						} else {
							Text("Generate data up to the current time")
						}
					}
				#endif

				ActionButton(
					title: "Reload widgets",
					icon: "widget.small",
				) {
					WidgetCenter.shared.reloadAllTimelines()
				}
				.listRowBackground(Color(.systemBackground))

				ActionButton(
					title: "Fetch health data & rebuild caches",
					icon: "heart.fill",
				) {
					do {
						try await healthKitManager.populateAllCaches()
						cacheViewRefreshID = UUID()
					} catch {
						print("Failed to fetch health data: \(error)")
					}
				}
				.listRowBackground(Color(.systemBackground))

				Section("Authorization Debug") {
					AuthorizationDebugView(healthKitManager: healthKitManager)
				}
				.listRowBackground(Color(.systemBackground))

				Section {
					CacheDebugView()
						.id(cacheViewRefreshID)
				}
			}
			.listStyle(.insetGrouped)
			.navigationTitle("Development Tools")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(action: { dismiss() }) {
						Image(systemName: "xmark")
					}
				}
			}
		}
		.presentationDetents([.medium, .large])
		.alert("Permission Required", isPresented: $showingPermissionError) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(permissionErrorMessage)
		}
	}
}

/// Debug view showing authorization check values
struct AuthorizationDebugView: View {
	var healthKitManager: HealthKitManager
	@State private var cacheStatus: CacheCheckResult?

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			DebugRow(
				label: "isAuthorized",
				value: healthKitManager.isAuthorized.description,
				isError: !healthKitManager.isAuthorized
			)

			if let status = cacheStatus {
				DebugRow(
					label: "Cache file exists",
					value: status.exists.description,
					isError: !status.exists
				)

				if status.exists, let age = status.ageSeconds {
					DebugRow(
						label: "Data age",
						value: formatAge(age),
						isError: age > 3600  // Warn if older than 1 hour
					)
				}

				if let todayTotal = status.todayTotal {
					DebugRow(label: "Today total", value: "\(Int(todayTotal)) kcal")
				}

				if let moveGoal = status.moveGoal {
					DebugRow(label: "Move goal", value: "\(Int(moveGoal)) kcal")
				}

				if let hourlyCount = status.hourlyDataCount {
					DebugRow(label: "Hourly data points", value: "\(hourlyCount)")
				}

				if let timestamp = status.latestSampleTimestamp {
					DebugRow(
						label: "Latest sample",
						value: formatTimestamp(timestamp)
					)
				}

				if let error = status.error {
					DebugRow(label: "Cache read error", value: error, isError: true)
				}
			}
		}
		.font(.system(.body, design: .monospaced))
		.task {
			await checkCacheStatus()
		}
	}

	private func checkCacheStatus() async {
		// Try to read the cache and capture all details
		do {
			let data = try TodayEnergyCacheManager.shared.readEnergyData()

			// Calculate cache age from latest sample timestamp
			let age = data.latestSampleTimestamp.map { Date().timeIntervalSince($0) }

			cacheStatus = CacheCheckResult(
				exists: true,
				ageSeconds: age,
				todayTotal: data.todayTotal,
				moveGoal: data.moveGoal,
				hourlyDataCount: data.todayHourlyData.count,
				latestSampleTimestamp: data.latestSampleTimestamp,
				error: nil
			)
		} catch TodayEnergyCacheError.fileNotFound {
			cacheStatus = CacheCheckResult(
				exists: false,
				ageSeconds: nil,
				todayTotal: nil,
				moveGoal: nil,
				hourlyDataCount: nil,
				latestSampleTimestamp: nil,
				error: "File not found"
			)
		} catch TodayEnergyCacheError.containerNotFound {
			cacheStatus = CacheCheckResult(
				exists: false,
				ageSeconds: nil,
				todayTotal: nil,
				moveGoal: nil,
				hourlyDataCount: nil,
				latestSampleTimestamp: nil,
				error: "App group container not found"
			)
		} catch {
			cacheStatus = CacheCheckResult(
				exists: true,
				ageSeconds: nil,
				todayTotal: nil,
				moveGoal: nil,
				hourlyDataCount: nil,
				latestSampleTimestamp: nil,
				error: error.localizedDescription
			)
		}
	}

	private func formatAge(_ seconds: TimeInterval) -> String {
		if seconds < 60 {
			return "\(Int(seconds))s"
		} else if seconds < 3600 {
			return "\(Int(seconds / 60))m"
		} else {
			let hours = Int(seconds / 3600)
			let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
			return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
		}
	}

	private func formatTimestamp(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateStyle = .none
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}
}

/// Debug row component
struct DebugRow: View {
	let label: String
	let value: String
	var isError: Bool = false

	var body: some View {
		HStack(alignment: .top) {
			Text(label + ":")
				.foregroundStyle(.secondary)
			Spacer()
			Text(value)
				.foregroundStyle(isError ? .red : .primary)
				.multilineTextAlignment(.trailing)
		}
	}
}

/// Result of checking cache status
struct CacheCheckResult {
	let exists: Bool
	let ageSeconds: TimeInterval?
	let todayTotal: Double?
	let moveGoal: Double?
	let hourlyDataCount: Int?
	let latestSampleTimestamp: Date?
	let error: String?
}
