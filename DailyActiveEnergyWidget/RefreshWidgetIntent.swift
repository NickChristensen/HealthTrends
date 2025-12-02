//
//  RefreshWidgetIntent.swift
//  DailyActiveEnergyWidget
//
//  Created by Claude on 2025-11-29.
//

import AppIntents
import WidgetKit

/// App Intent that refreshes the widget's data when tapped
/// This runs in the widget extension process and triggers a timeline reload
struct RefreshWidgetIntent: AppIntent {
	static var title: LocalizedStringResource = "Refresh Widget"
	static var description: IntentDescription = "Refreshes the widget's data from HealthKit"

	func perform() async throws -> some IntentResult {
		// Reload the widget timeline - this triggers getTimeline() in the provider
		// which will fetch fresh HealthKit data
		WidgetCenter.shared.reloadTimelines(ofKind: "DailyActiveEnergyWidget")

		return .result()
	}
}
