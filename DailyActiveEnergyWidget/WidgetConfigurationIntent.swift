//
//  WidgetConfigurationIntent.swift
//  DailyActiveEnergyWidget
//
//  Created by Claude on 2025-11-29.
//

import AppIntents
import WidgetKit

/// Configuration for the Daily Active Energy Widget
struct EnergyWidgetConfigurationIntent: WidgetConfigurationIntent {
	static var title: LocalizedStringResource = "Widget Configuration"
	static var description: IntentDescription = "Configure how the widget behaves when tapped"

	@Parameter(title: "Tapping", default: .refresh)
	var tapAction: TapActionOption
}

/// Options for what happens when the widget is tapped
enum TapActionOption: String, AppEnum {
	case refresh = "Refreshes Data"
	case openApp = "Opens Health Trends"

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tapping")

	static var caseDisplayRepresentations: [TapActionOption: DisplayRepresentation] = [
		.refresh: DisplayRepresentation(
			title: "Refreshes Data"
		),
		.openApp: DisplayRepresentation(
			title: "Opens Health Trends"
		),
	]
}
