//
//  RedesignedNewTabPageCardBackground.swift
//  DuckDuckGo
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

import Combine
import DesignResourcesKit
import SwiftUI

/// Shared raised surface for controls on the redesigned New Tab Page. The border matches the unified toggle input card.
/// With `usesLiquidGlass` on iOS 26 it is a Liquid Glass surface, like the focused unified toggle input.
struct RedesignedNewTabPageCardBackground: View {
    static let cornerRadius: CGFloat = Metrics.cornerRadius

    var usesLiquidGlass = false
    private let cornerRadius: CGFloat = Metrics.cornerRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let customizationStore: NewTabPageCustomizationStore
    @State private var theme: NewTabPageTheme

    init(usesLiquidGlass: Bool = false, customizationStore: NewTabPageCustomizationStore = NewTabPageCustomizationStore()) {
        self.usesLiquidGlass = usesLiquidGlass
        self.customizationStore = customizationStore
        _theme = State(initialValue: customizationStore.theme)
    }

    var body: some View {
        content
            .onReceive(customizationStore.themePublisher.receive(on: DispatchQueue.main)) { theme in
                self.theme = theme
            }
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 26, *), usesLiquidGlass, !reduceTransparency {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            raisedSurface
        }
    }

    private var raisedSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill = Color(theme.cardBackgroundColor)
        let shadowColor = Color(designSystemColor: .shadowSecondary)
        let borderColor = Color(singleUseColor: .inputContentSeparator)
        // Each shadow comes from its own fill-only layer. Chaining `.shadow` on the composite makes the second
        // shadow also cast the first one, which blurs the border and edge.
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(borderColor, lineWidth: Metrics.borderWidth))
            .overlay(
                shape
                    .inset(by: Metrics.highlightInset)
                    .stroke(Color(designSystemColor: .highlightDecoration), lineWidth: Metrics.highlightWidth)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center))
            )
            .background(shape.fill(fill).shadow(color: shadowColor, radius: Metrics.nearShadowRadius, y: Metrics.nearShadowOffset))
            .background(shape.fill(fill).shadow(color: shadowColor, radius: Metrics.farShadowRadius, y: Metrics.farShadowOffset))
    }
}

private enum Metrics {
    static let cornerRadius: CGFloat = 28
    static let borderWidth: CGFloat = 1
    static let highlightInset: CGFloat = 0.5
    static let highlightWidth: CGFloat = 1
    static let nearShadowRadius: CGFloat = 4
    static let nearShadowOffset: CGFloat = 2
    static let farShadowRadius: CGFloat = 16
    static let farShadowOffset: CGFloat = 8
}
