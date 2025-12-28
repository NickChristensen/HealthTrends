//
//  WidgetConfigurationIntent.swift
//  DailyActiveEnergyWidget
//
//  Created by Claude on 2025-11-29.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Configuration for the Daily Active Energy Widget
struct EnergyWidgetConfigurationIntent: WidgetConfigurationIntent {
	static var title: LocalizedStringResource = "Widget Configuration"
	static var description: IntentDescription = "Configure widget display and behavior"

	// MARK: Appearance
	@Parameter(title: "Accent color", default: .activityOrange)
	var accentColor: AccentColorOption

	@Parameter(title: "Chart start time", default: .midnight)
	var chartStartHour: ChartStartHour

	// MARK: Behavior
	@Parameter(title: "Tapping", default: .refresh)
	var tapAction: TapActionOption
}

/// Options for what happens when the widget is tapped
enum TapActionOption: String, AppEnum {
	case refresh = "Refreshes data"
	case openApp = "Opens Health Trends"

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tapping")

	static var caseDisplayRepresentations: [TapActionOption: DisplayRepresentation] = [
		.refresh: DisplayRepresentation(
			title: "Refreshes data"
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

/// Options for widget accent color
enum AccentColorOption: String, AppEnum, CaseIterable {
	case activityOrange = "Activity orange"
	case blue = "Blue"
	case cyan = "Cyan"
	case green = "Green"
	case indigo = "Indigo"
	case mint = "Mint"
	case orange = "Orange"
	case pink = "Pink"
	case purple = "Purple"
	case red = "Red"
	case teal = "Teal"
	case yellow = "Yellow"

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Accent Color")

	static var caseDisplayRepresentations: [AccentColorOption: DisplayRepresentation] = [
		.activityOrange: DisplayRepresentation(title: "Activity orange"),
		.blue: DisplayRepresentation(title: "Blue"),
		.cyan: DisplayRepresentation(title: "Cyan"),
		.green: DisplayRepresentation(title: "Green"),
		.indigo: DisplayRepresentation(title: "Indigo"),
		.mint: DisplayRepresentation(title: "Mint"),
		.orange: DisplayRepresentation(title: "Orange"),
		.pink: DisplayRepresentation(title: "Pink"),
		.purple: DisplayRepresentation(title: "Purple"),
		.red: DisplayRepresentation(title: "Red"),
		.teal: DisplayRepresentation(title: "Teal"),
		.yellow: DisplayRepresentation(title: "Yellow"),
	]
}

extension AccentColorOption {
	/// Convert enum case to SwiftUI Color
	var color: Color {
		switch self {
		case .activityOrange: return Color("AccentColor")
		case .blue: return .blue
		case .cyan: return .cyan
		case .green: return .green
		case .indigo: return .indigo
		case .mint: return .mint
		case .orange: return .orange
		case .pink: return .pink
		case .purple: return .purple
		case .red: return .red
		case .teal: return .teal
		case .yellow: return .yellow
		}
	}
}
