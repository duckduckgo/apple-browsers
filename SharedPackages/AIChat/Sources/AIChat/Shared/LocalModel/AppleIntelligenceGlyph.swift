//
//  AppleIntelligenceGlyph.swift
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

/// A stand-in for Apple's artwork, which isn't in the asset catalog yet.
public struct AppleIntelligenceGlyph: View {

    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        // Brand colors, not theme colors: the glyph looks the same in light and dark mode.
        Circle()
            .strokeBorder(AngularGradient(gradient: Gradient(colors: [.orange, .pink, .purple, .blue, .cyan, .orange]), center: .center),
                          lineWidth: size / 6)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
