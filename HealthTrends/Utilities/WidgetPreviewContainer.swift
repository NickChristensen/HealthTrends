//
//  WidgetPreviewContainer.swift
//  HealthTrends
//
//  Created by Nick Christensen on 2025-11-09.
//

import SwiftUI

enum WidgetFamily {
    case systemMedium
    case systemLarge
}

struct WidgetPreviewContainer<Content: View>: View {
    let family: WidgetFamily
    let label: String
    @ViewBuilder let content: () -> Content

    private var widgetSize: CGSize {
        let screenWidth = UIScreen.main.bounds.width
        let padding: CGFloat = 32 // Approximate home screen padding

        let width = screenWidth - padding * 2

        switch family {
        case .systemMedium:
            // Medium widgets are roughly 47% of screen height
            let height = (screenWidth - padding * 3) / 2
            return CGSize(width: width, height: height)
        case .systemLarge:
            // Large widgets are roughly 105% of their width
            let height = width * 1.05
            return CGSize(width: width, height: height)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            content()
                .padding(16) // Simulate widget system content margins
                .frame(width: widgetSize.width, height: widgetSize.height)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
    }
}
