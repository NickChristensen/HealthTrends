//
//  TextMeasurement.swift
//  HealthTrends
//
//  Created by Claude on 2025-11-15.
//

import UIKit

/// Measure the width of a text string using a specified UIFont text style
///
/// This function provides accurate text width measurements for layout calculations,
/// collision detection, and precise positioning of text elements.
///
/// - Parameters:
///   - text: The text string to measure
///   - textStyle: The UIFont.TextStyle to use (e.g., .caption1, .body, .headline)
/// - Returns: The width of the text in points, rounded up to the nearest integer
///
/// - Example:
///   ```swift
///   let width = measureTextWidth("8:23 PM", textStyle: .caption1)
///   // Use width for collision detection or positioning
///   ```
func measureTextWidth(_ text: String, textStyle: UIFont.TextStyle) -> CGFloat {
	let font = UIFont.preferredFont(forTextStyle: textStyle)
	let attributes = [NSAttributedString.Key.font: font]
	let size = (text as NSString).size(withAttributes: attributes)
	return ceil(size.width)
}
