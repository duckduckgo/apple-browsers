//
//  IconBadge.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

#if os(iOS) || os(macOS)

import SwiftUI
import DesignResourcesKit

/// A template glyph centered in a circle: a surface fill and a `.lines` hairline border, with the glyph
/// tinted `.textPrimary`. The default sizing matches the design system's 16px glyph in a 32px badge. Shared
/// by the onboarding showcase card and the feature grid so their icons stay visually identical. When `icon`
/// is `nil` only the circle is drawn.
public struct IconBadge: View {
    private let icon: Image?
    private let diameter: CGFloat
    private let iconSize: CGFloat
    private let borderWidth: CGFloat

    public init(icon: Image? = nil, diameter: CGFloat = 32, iconSize: CGFloat = 16, borderWidth: CGFloat = 1) {
        self.icon = icon
        self.diameter = diameter
        self.iconSize = iconSize
        self.borderWidth = borderWidth
    }

    public var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle().stroke(Color(designSystemColor: .lines), lineWidth: borderWidth)
            }
            .overlay {
                if let icon {
                    icon
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                }
            }
    }

    private var fillColor: Color {
        #if os(iOS)
        Color(designSystemColor: .surface)
        #else
        Color(designSystemColor: .surfacePrimary)
        #endif
    }
}

#if DEBUG
private struct IconBadgePreview: View {
    var body: some View {
        HStack(spacing: 16) {
            IconBadge(icon: Image(systemName: "lock.fill"))
            IconBadge(icon: Image(systemName: "bolt.fill"))
            IconBadge() // Circle only (no glyph)
            IconBadge(icon: Image(systemName: "star.fill"), diameter: 48, iconSize: 24)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .surfaceTertiary))
    }
}

#Preview("Light") {
    IconBadgePreview()
}

#Preview("Dark") {
    IconBadgePreview()
        .preferredColorScheme(.dark)
}

#Preview("Large Text") {
    IconBadgePreview()
        .dynamicTypeSize(.accessibility3)
}
#endif

#endif
