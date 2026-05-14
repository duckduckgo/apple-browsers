//
//  BorderedBackground.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import SwiftUI
import DesignResourcesKit

#if os(macOS)

/// A view modifier that applies a rounded background with a border.
///
/// This modifier applies:
/// - A rounded rectangle background with the specified color
/// - A rounded rectangle border with the specified color
///
public struct BorderedBackgroundModifier: ViewModifier {
    let backgroundColor: Color
    let borderColor: Color
    let cornerRadius: CGFloat

    init(backgroundColor: Color = Color(designSystemColor: .surfaceSecondary), borderColor: Color = Color(designSystemColor: .lines), cornerRadius: CGFloat = 8) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

public extension View {
    /// Applies a bordered background style with rounded background and border.
    ///
    /// - Parameters:
    ///   - color: The background color. Defaults to `.surfaceSecondary` design system color.
    ///   - borderColor: The border color. Defaults to `.lines` design system color.
    ///   - cornerRadius: The corner radius for the rounded rectangle. Defaults to 8.
    /// - Returns: A view with the bordered background style applied.
    func borderedBackground(color: Color = Color(designSystemColor: .surfaceSecondary), borderColor: Color = Color(designSystemColor: .lines), cornerRadius: CGFloat = 8) -> some View {
        modifier(BorderedBackgroundModifier(backgroundColor: color, borderColor: borderColor, cornerRadius: cornerRadius))
    }
}

#endif
