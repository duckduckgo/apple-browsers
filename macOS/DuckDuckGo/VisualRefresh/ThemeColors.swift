//
//  ThemeColors.swift
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

import Foundation
import AppKit
import DesignResourcesKit

struct ThemeColors: ColorPalette {
    let accentAltContentPrimary: NSColor
    let accentAltContentSecondary: NSColor
    let accentAltContentTertiary: NSColor
    let accentAltGlowPrimary: NSColor
    let accentAltPrimary: NSColor
    let accentAltSecondary: NSColor
    let accentAltTertiary: NSColor
    let accentAltTextPrimary: NSColor
    let accentAltTextSecondary: NSColor
    let accentAltTextTertiary: NSColor
    let accentContentPrimary: NSColor
    let accentContentSecondary: NSColor
    let accentContentTertiary: NSColor
    let accentGlowPrimary: NSColor
    let accentPrimary: NSColor
    let accentSecondary: NSColor
    let accentTertiary: NSColor
    let accentTextPrimary: NSColor
    let accentTextSecondary: NSColor
    let accentTextTertiary: NSColor
    let controlsDecorationPrimary: NSColor
    let controlsDecorationSecondary: NSColor
    let controlsDecorationTertiary: NSColor
    let controlsFillPrimary: NSColor
    let controlsFillSecondary: NSColor
    let controlsFillTertiary: NSColor
    let decorationPrimary: NSColor
    let decorationSecondary: NSColor
    let decorationTertiary: NSColor
    let destructiveContentPrimary: NSColor
    let destructiveContentSecondary: NSColor
    let destructiveContentTertiary: NSColor
    let destructiveGlow: NSColor
    let destructivePrimary: NSColor
    let destructiveSecondary: NSColor
    let destructiveTertiary: NSColor
    let destructiveTextPrimary: NSColor
    let destructiveTextSecondary: NSColor
    let destructiveTextTertiary: NSColor
    let highlightPrimary: NSColor
    let iconsPrimary: NSColor
    let iconsSecondary: NSColor
    let iconsTertiary: NSColor
    let shadowPrimary: NSColor
    let shadowSecondary: NSColor
    let shadowTertiary: NSColor
    let surfaceBackdrop: NSColor
    let surfaceCanvas: NSColor
    let surfacePrimary: NSColor
    let surfaceSecondary: NSColor
    let surfaceTertiary: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textTertiary: NSColor
    let toneShadePrimary: NSColor
    let toneTintPrimary: NSColor
}

extension ThemeColors {

    init(themeName: ThemeName) {
        let palette = Self.designColorPalette(for: themeName)

        accentAltContentPrimary = NSColor(designSystemColor: .accentAltContentPrimary, palette: palette)
        accentAltContentSecondary = NSColor(designSystemColor: .accentAltContentSecondary, palette: palette)
        accentAltContentTertiary = NSColor(designSystemColor: .accentAltContentTertiary, palette: palette)
        accentAltGlowPrimary = NSColor(designSystemColor: .accentAltGlowPrimary, palette: palette)
        accentAltPrimary = NSColor(designSystemColor: .accentAltPrimary, palette: palette)
        accentAltSecondary = NSColor(designSystemColor: .accentAltSecondary, palette: palette)
        accentAltTertiary = NSColor(designSystemColor: .accentAltTertiary, palette: palette)
        accentAltTextPrimary = NSColor(designSystemColor: .accentAltTextPrimary, palette: palette)
        accentAltTextSecondary = NSColor(designSystemColor: .accentAltTextSecondary, palette: palette)
        accentAltTextTertiary = NSColor(designSystemColor: .accentAltTextTertiary, palette: palette)
        accentContentPrimary = NSColor(designSystemColor: .accentContentPrimary, palette: palette)
        accentContentSecondary = NSColor(designSystemColor: .accentContentSecondary, palette: palette)
        accentContentTertiary = NSColor(designSystemColor: .accentContentTertiary, palette: palette)
        accentGlowPrimary = NSColor(designSystemColor: .accentGlowPrimary, palette: palette)
        accentPrimary = NSColor(designSystemColor: .accentPrimary, palette: palette)
        accentSecondary = NSColor(designSystemColor: .accentSecondary, palette: palette)
        accentTertiary = NSColor(designSystemColor: .accentTertiary, palette: palette)
        accentTextPrimary = NSColor(designSystemColor: .accentTextPrimary, palette: palette)
        accentTextSecondary = NSColor(designSystemColor: .accentTextSecondary, palette: palette)
        accentTextTertiary = NSColor(designSystemColor: .accentTextTertiary, palette: palette)
        controlsDecorationPrimary = NSColor(designSystemColor: .controlsDecorationPrimary, palette: palette)
        controlsDecorationSecondary = NSColor(designSystemColor: .controlsDecorationSecondary, palette: palette)
        controlsDecorationTertiary = NSColor(designSystemColor: .controlsDecorationTertiary, palette: palette)
        controlsFillPrimary = NSColor(designSystemColor: .controlsFillPrimary, palette: palette)
        controlsFillSecondary = NSColor(designSystemColor: .controlsFillSecondary, palette: palette)
        controlsFillTertiary = NSColor(designSystemColor: .controlsFillTertiary, palette: palette)
        decorationPrimary = NSColor(designSystemColor: .decorationPrimary, palette: palette)
        decorationSecondary = NSColor(designSystemColor: .decorationSecondary, palette: palette)
        decorationTertiary = NSColor(designSystemColor: .decorationTertiary, palette: palette)
        destructiveContentPrimary = NSColor(designSystemColor: .destructiveContentPrimary, palette: palette)
        destructiveContentSecondary = NSColor(designSystemColor: .destructiveContentSecondary, palette: palette)
        destructiveContentTertiary = NSColor(designSystemColor: .destructiveContentTertiary, palette: palette)
        destructiveGlow = NSColor(designSystemColor: .destructiveGlow, palette: palette)
        destructivePrimary = NSColor(designSystemColor: .destructivePrimary, palette: palette)
        destructiveSecondary = NSColor(designSystemColor: .destructiveSecondary, palette: palette)
        destructiveTertiary = NSColor(designSystemColor: .destructiveTertiary, palette: palette)
        destructiveTextPrimary = NSColor(designSystemColor: .destructiveTextPrimary, palette: palette)
        destructiveTextSecondary = NSColor(designSystemColor: .destructiveTextSecondary, palette: palette)
        destructiveTextTertiary = NSColor(designSystemColor: .destructiveTextTertiary, palette: palette)
        highlightPrimary = NSColor(designSystemColor: .highlightPrimary, palette: palette)
        iconsPrimary = NSColor(designSystemColor: .iconsPrimary, palette: palette)
        iconsSecondary = NSColor(designSystemColor: .iconsSecondary, palette: palette)
        iconsTertiary = NSColor(designSystemColor: .iconsTertiary, palette: palette)
        shadowPrimary = NSColor(designSystemColor: .shadowPrimary, palette: palette)
        shadowSecondary = NSColor(designSystemColor: .shadowSecondary, palette: palette)
        shadowTertiary = NSColor(designSystemColor: .shadowTertiary, palette: palette)
        surfaceBackdrop = NSColor(designSystemColor: .surfaceBackdrop, palette: palette)
        surfaceCanvas = NSColor(designSystemColor: .surfaceCanvas, palette: palette)
        surfacePrimary = NSColor(designSystemColor: .surfacePrimary, palette: palette)
        surfaceSecondary = NSColor(designSystemColor: .surfaceSecondary, palette: palette)
        surfaceTertiary = NSColor(designSystemColor: .surfaceTertiary, palette: palette)
        textPrimary = NSColor(designSystemColor: .textPrimary, palette: palette)
        textSecondary = NSColor(designSystemColor: .textSecondary, palette: palette)
        textTertiary = NSColor(designSystemColor: .textTertiary, palette: palette)
        toneShadePrimary = NSColor(designSystemColor: .toneShadePrimary, palette: palette)
        toneTintPrimary = NSColor(designSystemColor: .toneTintPrimary, palette: palette)
    }

    private static func designColorPalette(for themeName: ThemeName) -> DesignResourcesKit.ColorPalette {
        switch themeName {
        case .default:
            .default
        case .figma:
            .figma
        case .coolGray:
            .coolGray
        case .desert:
            .desert
        case .green:
            .green
        case .orange:
            .orange
        case .rose:
            .rose
        case .slateBlue:
            .slateBlue
        case .violet:
            .violet
        }
    }
}
