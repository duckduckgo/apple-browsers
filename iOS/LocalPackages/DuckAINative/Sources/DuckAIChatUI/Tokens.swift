//
//  Tokens.swift
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

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Mirrors the Duck.ai web frontend's own tokens so the native chat matches it; these are not DRK colors.
public enum DuckAIChatTokens {

    public enum Color {
        public static let textPrimary = adaptive(light: 0x000000, lightAlpha: 0.96, dark: 0xFFFFFF)
        public static let textSecondary = adaptive(light: 0x000000, lightAlpha: 0.66, dark: 0xFFFFFF, darkAlpha: 0.66)
        public static let textTertiary = adaptive(light: 0x000000, lightAlpha: 0.36, dark: 0xFFFFFF, darkAlpha: 0.36)
        public static let pageBackground = adaptive(light: 0xFFFFFF, dark: 0x111111)
        public static let userBubble = adaptive(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.09)
        public static let inputBackground = adaptive(light: 0xFFFFFF, dark: 0x333333)
        public static let inputBorder = adaptive(light: 0x000000, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.12)
        public static let accent = adaptive(light: 0x1074CC, dark: 0x75B6EB)
        public static let surfaceTertiary = adaptive(light: 0xFFFFFF, dark: 0x222222)
        public static let codeBackground = adaptive(light: 0xFFFFFF, dark: 0x181818)
        public static let codeFrame = adaptive(light: 0x000000, lightAlpha: 0.06, dark: 0x000000, darkAlpha: 0.24)
        public static let decorationSecondary = adaptive(light: 0x000000, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.12)
        public static let controlTertiary = adaptive(light: 0x000000, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.24)
        public static let listMarker = textTertiary

        private static func adaptive(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> SwiftUI.Color {
#if canImport(UIKit)
            return SwiftUI.Color(uiColor: UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                let hex = isDark ? dark : light
                return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                               green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255,
                               alpha: isDark ? darkAlpha : lightAlpha)
            })
#elseif canImport(AppKit)
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let hex = isDark ? dark : light
                return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                               green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255,
                               alpha: isDark ? darkAlpha : lightAlpha)
            })
#endif
        }
    }

    public enum Spacing {
        public static let s2: CGFloat = 2
        public static let s4: CGFloat = 4
        public static let s8: CGFloat = 8
        public static let s12: CGFloat = 12
        public static let s16: CGFloat = 16
        public static let s20: CGFloat = 20
        public static let s24: CGFloat = 24
        public static let s32: CGFloat = 32
        public static let s40: CGFloat = 40
    }

    public enum Radius {
        public static let userBubble = UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24,
                                                             bottomTrailingRadius: 24, topTrailingRadius: 0)
        public static let input: CGFloat = 24
        public static let codeOuter: CGFloat = 16
        public static let codeInner: CGFloat = 12
        public static let citationPill: CGFloat = 999
    }

    public enum Typography {
        public static let body = Style(size: 16, lineHeight: 24)
        public static let h1 = Style(size: 24, lineHeight: 32, weight: .bold)
        public static let h2 = Style(size: 20, lineHeight: 28, weight: .bold)
        public static let h3 = Style(size: 16, lineHeight: 24, weight: .bold)
        public static let tableCell = Style(size: 14, lineHeight: 20)

        public struct Style {
            public let size: CGFloat
            public let lineHeight: CGFloat
            public let weight: Font.Weight

            public var font: Font {
                let name = weight == .bold ? "DuckSansProduct-Bold" : "DuckSansProduct-Regular"
#if canImport(UIKit)
                let available = UIFont(name: name, size: size) != nil
#elseif canImport(AppKit)
                let available = NSFont(name: name, size: size) != nil
#endif
                if available {
                    return .custom(name, size: size, relativeTo: .body)
                }
#if canImport(UIKit)
                return .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: size), weight: weight)
#elseif canImport(AppKit)
                return .system(size: size, weight: weight)
#endif
            }

            fileprivate init(size: CGFloat, lineHeight: CGFloat, weight: Font.Weight = .regular) {
                self.size = size
                self.lineHeight = lineHeight
                self.weight = weight
            }
        }
    }
}
