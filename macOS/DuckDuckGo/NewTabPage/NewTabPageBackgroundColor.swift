//
//  NewTabPageBackgroundColor.swift
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

import AppKit
import Combine

/// Mirrors the colour the New Tab Page's scripts give `body`, so it can be shown before the page paints.
enum NewTabPageBackgroundColor {

    static func color(customBackground: CustomBackground?, canvas: NSColor, isDark: Bool) -> NSColor {
        switch customBackground {
        case .solidColor(let solidColor):
            return solidColor.color
        case .gradient(let gradient):
            return gradient.fallbackColor
        case .userImage(let image):
            return canvas.resolved(isDark: image.colorScheme == .dark)
        case .none:
            return canvas.resolved(isDark: isDark)
        }
    }

    static func publisher(
        customBackground: some Publisher<CustomBackground?, Never>,
        canvas: some Publisher<NSColor, Never>,
        isDark: some Publisher<Bool, Never>
    ) -> AnyPublisher<NSColor, Never> {
        Publishers.CombineLatest3(customBackground, canvas, isDark)
            .map { color(customBackground: $0, canvas: $1, isDark: $2) }
            .eraseToAnyPublisher()
    }
}

private extension NSColor {
    func resolved(isDark: Bool) -> NSColor {
        var resolved = self
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = usingColorSpace(.sRGB) ?? self
        }
        return resolved
    }
}
