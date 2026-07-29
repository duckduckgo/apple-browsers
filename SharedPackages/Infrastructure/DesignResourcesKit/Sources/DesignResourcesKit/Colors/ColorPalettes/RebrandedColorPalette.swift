//
//  RebrandedColorPalette.swift
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

import SwiftUI

#if os(iOS)

struct RebrandedColorPalette: ColorPaletteDefinition {

    static func dynamicColor(for designSystemColor: DesignSystemColor) -> DynamicColor {
        switch designSystemColor {
        case .accentPrimary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60, darkColor: RebrandingColor.Pondwater.pondwater40)
        case .accentTertiary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater80, darkColor: RebrandingColor.Pondwater.pondwater60)
        case .accentContentPrimary:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.white, darkColor: RebrandingColor.Eggshell.eggshell90)
        case .accentGlowSecondary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60.opacity(0.12), darkColor: RebrandingColor.Pondwater.pondwater40.opacity(0.12))
        case .accentTextPrimary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60, darkColor: RebrandingColor.Pondwater.pondwater40)
        case .textSelectionFill:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60.opacity(0.2), darkColor: RebrandingColor.Pondwater.pondwater40.opacity(0.2))
        case .destructivePrimary:
            return DynamicColor(lightColor: RebrandingColor.Red.red50, darkColor: RebrandingColor.Red.red40)
        case .alertGreen:
            return DynamicColor(staticColor: RebrandingColor.Green.green40)
        case .alertYellow:
            return DynamicColor(staticColor: RebrandingColor.Pollen.pollen50)
        case .accentBrandPrimary:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin50, darkColor: RebrandingColor.Pollen.pollen40)
        case .accentBrandTertiary:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin70, darkColor: RebrandingColor.Pollen.pollen60)
        case .accentBrandContentPrimary:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.white, darkColor: RebrandingColor.Pollen.pollen100)
        case .accentGlowPrimary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60.opacity(0.2), darkColor: RebrandingColor.Pondwater.pondwater40.opacity(0.2))
        case .accentAltGlowPrimary:
            return DynamicColor(lightColor: Color(0xA1CFF7).opacity(0.16), darkColor: Color(0xA1CFF7).opacity(0.12))
        case .accentAltContentPrimary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater90, darkColor: RebrandingColor.Pondwater.pondwater0)
        case .destructiveTertiary:
            return DynamicColor(lightColor: RebrandingColor.Red.red70, darkColor: RebrandingColor.Red.red60)
        case .destructiveGlowPrimary:
            return DynamicColor(lightColor: Color(0xE5244B).opacity(0.2), darkColor: Color(0xEE6D87).opacity(0.2))
        case .background, .panel:
            return DynamicColor(lightHex: 0xF8F8F8, darkHex: 0x212121)
        case .surface, .surfaceSecondary:
            return DynamicColor(lightHex: 0xFCFCFC, darkHex: 0x2B2B2B)
        case .surfaceTertiary:
            return DynamicColor(lightHex: 0xFFFFFF, darkHex: 0x333333)
        case .surfaceCanvas:
            return DynamicColor(lightHex: 0xFDFDFD, darkHex: 0x1C1C1C)
        case .backdrop:
            return DynamicColor(lightHex: 0xE4E4E4, darkHex: 0x050505)
        case .decorationPrimary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.09, darkHex: 0xFFFFFF, darkOpacity: 0.12)
        case .decorationSecondary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.16, darkHex: 0xFFFFFF, darkOpacity: 0.2)
        case .decorationTertiary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.24, darkHex: 0xFFFFFF, darkOpacity: 0.32)
        case .textPrimary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.96, darkHex: 0xFFFFFF, darkOpacity: 1)
        case .textSecondary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.6, darkHex: 0xFFFFFF, darkOpacity: 0.7)
        case .textTertiary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.36, darkHex: 0xFFFFFF, darkOpacity: 0.4)
        case .icons:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.84, darkHex: 0xFFFFFF, darkOpacity: 0.78)
        case .iconsSecondary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.6, darkHex: 0xFFFFFF, darkOpacity: 0.48)
        case .controlsFillPrimary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.06, darkHex: 0xFFFFFF, darkOpacity: 0.06)
        case .controlsFillSecondary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.09, darkHex: 0xFFFFFF, darkOpacity: 0.09)
        case .controlsFillTertiary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.12, darkHex: 0xFFFFFF, darkOpacity: 0.12)
        case .shadowPrimary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.05, darkHex: 0x000000, darkOpacity: 0.16)
        case .shadowSecondary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.08, darkHex: 0x000000, darkOpacity: 0.24)
        case .shadowTertiary:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.16, darkHex: 0x000000, darkOpacity: 0.32)
        default:
            return DefaultColorPalette.dynamicColor(for: designSystemColor)
        }
    }

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        DefaultColorPalette.dynamicColor(for: singleUseColor)
    }
}

#endif
