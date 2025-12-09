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
	@Bindable var healthKitManager: HealthKitManager
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
								// Refresh data after generating
								try await healthKitManager.fetchEnergyData()
								try await healthKitManager.fetchMoveGoal()
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
					title: "Fetch health data",
					icon: "heart.fill",
				) {
					do {
						try await healthKitManager.fetchEnergyData()
						cacheViewRefreshID = UUID()
					} catch {
						print("Failed to fetch health data: \(error)")
					}
				}
				.listRowBackground(Color(.systemBackground))

				ActionButton(
					title: "Rebuild average data cache",
					icon: "arrow.clockwise",
				) {
					await healthKitManager.populateWeekdayCaches()
					cacheViewRefreshID = UUID()
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
