//
//  UnifiedToggleInputModeCuePalette.swift
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

import UIKit

/// A colour field as gradient stops. For the conic sweep, the first and last stop must match,
/// otherwise the wrap shows a seam.
struct UnifiedToggleInputModeCueGradient {
    let colors: [UIColor]
    let locations: [NSNumber]
}

/// Colours for the mode cues, drawn only from the brand's nature ramps: pondwater alone for Search,
/// pondwater fusing through blossom into mandarin for Duck.ai.
///
/// The brand ramps in `DesignResourcesKit` are internal to that module, so the stops below are
/// transcribed from them and still need design sign-off.
enum UnifiedToggleInputModeCuePalette {

    private enum Ramp {
        static let pondwater30 = UIColor(red8Bit: 0xA1, 0xD0, 0xF7)
        static let pondwater40 = UIColor(red8Bit: 0x75, 0xB6, 0xEB)
        static let pondwater50 = UIColor(red8Bit: 0x43, 0x97, 0xE0)
        static let pondwater60 = UIColor(red8Bit: 0x10, 0x74, 0xCC)
        static let blossom30 = UIColor(red8Bit: 0xD3, 0xB9, 0xEB)
        static let blossom40 = UIColor(red8Bit: 0xC1, 0x9E, 0xDB)
        static let blossom50 = UIColor(red8Bit: 0x9F, 0x6E, 0xB8)
        static let mandarin30 = UIColor(red8Bit: 0xFF, 0xB2, 0x94)
        static let mandarin40 = UIColor(red8Bit: 0xFF, 0x8D, 0x5C)
    }

    private enum TextShimmerMetrics {
        static let stopCount = 24
        /// The cool tail fades in over the first stretch; the warm head fades out over the last.
        static let tailFadeEnd: CGFloat = 0.55
        static let headFadeStart: CGFloat = 0.82
    }

    // MARK: - Mode colours

    /// The mode's colours from tail to head, fully opaque, for the borders, the keyboard edge and the
    /// shimmer's Reduce Motion fallback.
    static func modeColors(for mode: TextEntryMode, resolvedWith traits: UITraitCollection) -> UnifiedToggleInputModeCueGradient {
        let anchors = rampAnchors(for: mode, isDark: traits.userInterfaceStyle == .dark)
        let locations = anchors.indices.map { NSNumber(value: Double($0) / Double(max(anchors.count - 1, 1))) }
        return UnifiedToggleInputModeCueGradient(colors: anchors, locations: locations)
    }

    private static func rampAnchors(for mode: TextEntryMode, isDark: Bool) -> [UIColor] {
        switch (mode, isDark) {
        case (.search, false): [Ramp.pondwater60, Ramp.pondwater40]
        case (.search, true): [Ramp.pondwater50, Ramp.pondwater30]
        case (.aiChat, false): [Ramp.pondwater50, Ramp.blossom40, Ramp.mandarin40]
        case (.aiChat, true): [Ramp.pondwater40, Ramp.blossom30, Ramp.mandarin30]
        }
    }

    // MARK: - Text shimmer

    /// The band that travels over typed text, tail first, with feathered ends.
    static func textShimmerBand(for mode: TextEntryMode, resolvedWith traits: UITraitCollection) -> UnifiedToggleInputModeCueGradient {
        let anchors = rampAnchors(for: mode, isDark: traits.userInterfaceStyle == .dark)
        let fractions = (0..<TextShimmerMetrics.stopCount).map { CGFloat($0) / CGFloat(TextShimmerMetrics.stopCount - 1) }
        let colors = fractions.map { fraction in
            color(at: fraction, fusing: anchors).withAlphaComponent(textShimmerOpacity(at: fraction))
        }
        return UnifiedToggleInputModeCueGradient(colors: colors, locations: fractions.map { NSNumber(value: Double($0)) })
    }

    private static func textShimmerOpacity(at fraction: CGFloat) -> CGFloat {
        smoothstep(0, TextShimmerMetrics.tailFadeEnd, fraction) * (1 - smoothstep(TextShimmerMetrics.headFadeStart, 1, fraction))
    }

    private static func smoothstep(_ lower: CGFloat, _ upper: CGFloat, _ value: CGFloat) -> CGFloat {
        let t = min(max((value - lower) / (upper - lower), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Mixes the two neighbouring ramp colours at `fraction` of the way through `anchors`.
    private static func color(at fraction: CGFloat, fusing anchors: [UIColor]) -> UIColor {
        guard anchors.count > 1 else { return anchors.first ?? .clear }
        let position = min(max(fraction, 0), 1) * CGFloat(anchors.count - 1)
        let index = min(Int(position), anchors.count - 2)
        return mix(anchors[index], anchors[index + 1], fraction: position - CGFloat(index))
    }

    private static func mix(_ from: UIColor, _ to: UIColor, fraction: CGFloat) -> UIColor {
        var (fromRed, fromGreen, fromBlue, fromAlpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (toRed, toGreen, toBlue, toAlpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        from.getRed(&fromRed, green: &fromGreen, blue: &fromBlue, alpha: &fromAlpha)
        to.getRed(&toRed, green: &toGreen, blue: &toBlue, alpha: &toAlpha)
        return UIColor(red: fromRed + (toRed - fromRed) * fraction,
                       green: fromGreen + (toGreen - fromGreen) * fraction,
                       blue: fromBlue + (toBlue - fromBlue) * fraction,
                       alpha: 1)
    }

    // MARK: - Border sweep

    /// Conic stops for the comet circling a border. Symmetric, so the wrap has no seam.
    static func gradient(for mode: TextEntryMode) -> UnifiedToggleInputModeCueGradient {
        switch mode {
        case .search: searchSweepGradient
        case .aiChat: duckAISweepGradient
        }
    }

    private static var searchSweepGradient: UnifiedToggleInputModeCueGradient {
        let deep = UIColor(lightColor: Ramp.pondwater60, darkColor: Ramp.pondwater40)
        let light = UIColor(lightColor: Ramp.pondwater40, darkColor: Ramp.pondwater30)
        return UnifiedToggleInputModeCueGradient(colors: [deep, light, deep], locations: [0, 0.5, 1])
    }

    private static var duckAISweepGradient: UnifiedToggleInputModeCueGradient {
        let pond = UIColor(lightColor: Ramp.pondwater50, darkColor: Ramp.pondwater40)
        let blossom = UIColor(lightColor: Ramp.blossom50, darkColor: Ramp.blossom40)
        let mandarin = UIColor(lightColor: Ramp.mandarin40, darkColor: Ramp.mandarin30)
        return UnifiedToggleInputModeCueGradient(colors: [pond, blossom, mandarin, blossom, pond],
                                                 locations: [0, 0.25, 0.5, 0.75, 1])
    }
}

private extension UIColor {
    convenience init(red8Bit red: Int, _ green: Int, _ blue: Int) {
        self.init(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
