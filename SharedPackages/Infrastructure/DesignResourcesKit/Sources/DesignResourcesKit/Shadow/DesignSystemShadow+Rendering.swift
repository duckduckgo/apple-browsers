//
//  DesignSystemShadow+Rendering.swift
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

import SwiftUI

public extension View {
    /// Applies each layer of `style` as a `.shadow`, in order.
    func designSystemShadow(_ style: DesignSystemShadowStyle) -> some View {
        modifier(DesignSystemShadowModifier(style: style))
    }
}

private struct DesignSystemShadowModifier: ViewModifier {
    let style: DesignSystemShadowStyle

    func body(content: Content) -> some View {
        style.layers.reduce(AnyView(content)) { view, layer in
            AnyView(view.shadow(color: Color(designSystemColor: layer.color).opacity(layer.opacity),
                                radius: layer.radius,
                                x: layer.x,
                                y: layer.y))
        }
    }
}

#if canImport(UIKit)
import UIKit

public extension CALayer {
    /// Sets the shadow color, opacity, radius and offset from `style`, resolving the color for `traitCollection`.
    ///
    /// A `CALayer` draws a single shadow, so `style` must have exactly one layer. Shape properties such as
    /// `shadowPath` and `masksToBounds` are left to the caller. The color doesn't follow appearance changes on
    /// its own: call this again when the trait collection changes.
    func applyDesignSystemShadow(_ style: DesignSystemShadowStyle, traitCollection: UITraitCollection) {
        assert(style.layers.count == 1, "CALayer draws one shadow; use a single-layer style")
        guard let shadow = style.layers.first else { return }

        shadowColor = UIColor(designSystemColor: shadow.color).resolvedColor(with: traitCollection).cgColor
        shadowOpacity = Float(shadow.opacity)
        shadowRadius = shadow.radius
        shadowOffset = CGSize(width: shadow.x, height: shadow.y)
    }
}
#endif
