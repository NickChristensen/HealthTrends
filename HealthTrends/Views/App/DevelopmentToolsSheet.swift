import SwiftUI
import WidgetKit

#if targetEnvironment(simulator)
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
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                state = .idle
            }
        }) {
            HStack(spacing: 12) {
                iconView
                    .frame(width: 24, height: 24)
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.borderless)
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
    @ObservedObject var healthKitManager: HealthKitManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ActionButton(
                    title: "Generate Sample Data",
                    icon: "testtube.2",
                ) {
                    do {
                        try await healthKitManager.generateSampleData()
                        // Refresh data after generating
                        try await healthKitManager.fetchEnergyData()
                        try await healthKitManager.fetchMoveGoal()
                    } catch {
                        print("Failed to generate sample data: \(error)")
                    }
                }
                .listRowBackground(Color(.systemBackground))

                ActionButton(
                    title: "Reload Widgets",
                    icon: "widget.small",
                ) {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .listRowBackground(Color(.systemBackground))
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
        .presentationDetents([.medium])
    }
}
#endif
