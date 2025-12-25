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
	static var description: IntentDescription = "Configure widget display and behavior"

	@Parameter(title: "Chart Start Time", default: .midnight)
	var chartStartHour: ChartStartHour

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

/// Options for the chart X-axis start time (12 AM through 12 PM)
enum ChartStartHour: Int, AppEnum, CaseIterable {
	case midnight = 0
	case oneAM = 1
	case twoAM = 2
	case threeAM = 3
	case fourAM = 4
	case fiveAM = 5
	case sixAM = 6
	case sevenAM = 7
	case eightAM = 8
	case nineAM = 9
	case tenAM = 10
	case elevenAM = 11
	case noon = 12

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Chart Start Time")

	static var caseDisplayRepresentations: [ChartStartHour: DisplayRepresentation] = [
		.midnight: DisplayRepresentation(title: "12:00 AM"),
		.oneAM: DisplayRepresentation(title: "1:00 AM"),
		.twoAM: DisplayRepresentation(title: "2:00 AM"),
		.threeAM: DisplayRepresentation(title: "3:00 AM"),
		.fourAM: DisplayRepresentation(title: "4:00 AM"),
		.fiveAM: DisplayRepresentation(title: "5:00 AM"),
		.sixAM: DisplayRepresentation(title: "6:00 AM"),
		.sevenAM: DisplayRepresentation(title: "7:00 AM"),
		.eightAM: DisplayRepresentation(title: "8:00 AM"),
		.nineAM: DisplayRepresentation(title: "9:00 AM"),
		.tenAM: DisplayRepresentation(title: "10:00 AM"),
		.elevenAM: DisplayRepresentation(title: "11:00 AM"),
		.noon: DisplayRepresentation(title: "12:00 PM"),
	]
}
