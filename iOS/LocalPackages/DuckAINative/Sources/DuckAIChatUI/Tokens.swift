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

#if canImport(UIKit)
import UIKit

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
        public static let controlSecondary = adaptive(light: 0x000000, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.18)
        public static let modelIconActive = adaptive(light: 0x000000, lightAlpha: 0.84, dark: 0xFFFFFF, darkAlpha: 0.80)
        public static let modelIconPrevious = adaptive(light: 0x484848, dark: 0xAAAAAA)
        public static let destructive = adaptive(light: 0xD83544, dark: 0xE44D55)
        public static let codeLanguage = UIColor(red: 136 / 255, green: 136 / 255, blue: 136 / 255, alpha: 1)
        public static let listMarker = textTertiary

        private static func adaptive(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> UIColor {
            UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                let hex = isDark ? dark : light
                return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                               green: CGFloat((hex >> 8) & 0xFF) / 255,
                               blue: CGFloat(hex & 0xFF) / 255,
                               alpha: isDark ? darkAlpha : lightAlpha)
            }
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
        public static let userBubble: CGFloat = 24
        public static let input: CGFloat = 24
        public static let codeOuter: CGFloat = 16
        public static let codeInner: CGFloat = 12
        public static let citationPill: CGFloat = 999
    }

    public enum Typography {
        public static let body = Style(size: 16, lineHeight: 24)
        public static let caption = Style(size: 13, lineHeight: 16)
        public static let modelName = Style(size: 13, lineHeight: 16, weight: .bold)
        public static let h1 = Style(size: 24, lineHeight: 32, weight: .bold, tracking: -0.3)
        public static let h2 = Style(size: 22, lineHeight: 28, weight: .bold, tracking: -0.3)
        public static let h3 = Style(size: 21, lineHeight: 24, weight: .bold, tracking: -0.2)
        public static let h4 = Style(size: 18, lineHeight: 24, weight: .bold, tracking: -0.1)
        public static let h5 = Style(size: 16, lineHeight: 24, weight: .bold)
        public static let tableCell = Style(size: 14, lineHeight: 21)
        public static let subtitle = Style(size: 14, lineHeight: 20)
        public static let code = Style(size: 12, lineHeight: 20, monospaced: true)
        public static let inlineCode = Style(size: 12, lineHeight: 24, monospaced: true)
        public static let codeLabel = Style(size: 12, lineHeight: 24, monospaced: true)

        public static func heading(_ level: Int) -> Style {
            switch level {
            case 1: h1
            case 2: h2
            case 3: h3
            case 4: h4
            default: h5
            }
        }

        public struct Style {
            public let size: CGFloat
            public let lineHeight: CGFloat
            public let weight: UIFont.Weight
            public let tracking: CGFloat
            private let monospaced: Bool

            public var font: UIFont {
                if monospaced { return .monospacedSystemFont(ofSize: size, weight: .regular) }
                let name = weight == .bold ? "DuckSansProduct-Bold" : "DuckSansProduct-Regular"
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
            }

            public var naturalLineHeight: CGFloat { font.lineHeight }

            public var lineSpacing: CGFloat { lineHeight - naturalLineHeight }

            fileprivate init(size: CGFloat, lineHeight: CGFloat, weight: UIFont.Weight = .regular,
                             tracking: CGFloat = 0, monospaced: Bool = false) {
                self.size = size
                self.lineHeight = lineHeight
                self.weight = weight
                self.tracking = tracking
                self.monospaced = monospaced
            }
        }
    }
}

#endif
