//
//  DesignSystemShadow.swift
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

// Shared shadow styles.
//
// A style is defined here only when the same values are used in more than one place. Shadows whose
// values differ from every style below keep their own definitions on purpose: they are not rounded
// to the nearest style, so that adopting a style never changes how a screen looks. Align them with
// design before moving them to a shared style.

import CoreGraphics

extension DesignSystemColor: Sendable {}

/// One shadow: a design system color, its opacity, blur radius and offset.
public struct DesignSystemShadowLayer: Equatable, Sendable {
    public let color: DesignSystemColor
    public let opacity: Double
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: DesignSystemColor, opacity: Double = 1, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
        self.color = color
        self.opacity = opacity
        self.radius = radius
        self.x = x
        self.y = y
    }
}

/// A shadow treatment made of one or more layers, drawn in order.
public struct DesignSystemShadowStyle: Equatable, Sendable {
    public let layers: [DesignSystemShadowLayer]

    public init(layers: [DesignSystemShadowLayer]) {
        self.layers = layers
    }
}

public extension DesignSystemShadowStyle {
    /// Cards that sit on a surface, such as tab switcher cards.
    static let card = DesignSystemShadowStyle(layers: [
        DesignSystemShadowLayer(color: .shadowSecondary, radius: 12, y: 4)
    ])

    /// Search fields and the tiles that sit next to them in widgets.
    static let searchField = DesignSystemShadowStyle(layers: [
        DesignSystemShadowLayer(color: .shadowSecondary, radius: 12, y: 8)
    ])
}
