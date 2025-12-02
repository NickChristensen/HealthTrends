//
//  ShakeGesture.swift
//  HealthTrends
//
//  Created by Nick Christensen on 2025-11-09.
//

import SwiftUI

// MARK: - Shake Detection via UIWindow + NotificationCenter

extension UIDevice {
	static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

extension UIWindow {
	open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		if motion == .motionShake {
			NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
		}
	}
}

// MARK: - SwiftUI ViewModifier

struct DeviceShakeViewModifier: ViewModifier {
	let action: () -> Void

	func body(content: Content) -> some View {
		content
			.onAppear()
			.onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) {
				_ in
				action()
			}
	}
}

// MARK: - View Extension

extension View {
	/// Performs an action when the device is shaken
	/// - Parameter action: The action to perform when shake is detected
	/// - Note: In simulator, use Hardware > Shake (⌃⌘Z)
	func onShake(perform action: @escaping () -> Void) -> some View {
		self.modifier(DeviceShakeViewModifier(action: action))
	}
}
