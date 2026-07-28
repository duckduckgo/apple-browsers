//
//  SharedColorPaletteDefinition+SingleUseColors.swift
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

import Foundation
import SwiftUI

/// Single-use colours are hand-written and don't have matching Figma tokens
/// so can't be automatically generated.
extension SharedColorPaletteDefinition {

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        switch singleUseColor {
        case .fireModeAccent:
            return DynamicColor(lightColor: PrimitiveColor.Mandarin.mandarin50, darkColor: PrimitiveColor.Mandarin.mandarin40)

#if os(iOS)
        case .controlWidgetBackground:
            return DynamicColor(staticColor: .x818387)
        case .unifiedFeedbackFieldBackground:
            return DynamicColor(lightColor: surfaceSecondary.lightColor, darkColor: .x1C1C1E)
        case .privacyDashboardBackground:
            return DynamicColor(lightColor: surfaceSecondary.lightColor, darkColor: surfacePrimary.darkColor)
        case .inputContentSeparator:
            return DynamicColor(lightColor: shadowTertiary.lightColor, darkColor: highlightPrimary.darkColor)
        case .whatsNewBackground:
            return DynamicColor(lightColor: .white, darkColor: surfacePrimary.darkColor)
        case .duckAIContextualSheetBackground:
            return DynamicColor(lightColor: .white, darkColor: .x161616)
        case .duckAIWebViewBackground:
            return DynamicColor(lightColor: .white, darkColor: .x111111)
        case .unifiedToggleInputStopButtonBackground:
            return DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.12))
        case .floatingAddressBarBackground:
            return DynamicColor(lightColor: .shade(0.05), darkColor: .tint(0.08))
        case .unifiedToggleInputAttachmentErrorBannerBackground:
            return DynamicColor(lightColor: Color(0xF6CDD1), darkColor: Color(0x5A2A2A))
        case .unifiedToggleInputAttachmentErrorText:
            return DynamicColor(lightColor: .black.opacity(0.84), darkColor: .white.opacity(0.88))
        case .unifiedToggleInputAttachmentErrorIcon:
            return DynamicColor(staticColor: Color(0xD4452F))
        case .tabSwitcherTrackerCountBackground:
            return DynamicColor(lightColor: .green0, darkColor: .x2C3A2A)
        case .toolbarButton:
            return DynamicColor(lightColor: Color(0x1F1F1F).opacity(0.918), darkColor: .tint(0.905))

        case .fireModeAccentDark:
            return DynamicColor(staticColor: PrimitiveColor.Mandarin.mandarin40)
        case .fireModeBackground:
            return DynamicColor(lightColor: Color(0x3D3D3D), darkColor: Color(0x080808))
        case .fireModeCardBackground:
            return DynamicColor(lightColor: Color(0x3D3D3D), darkColor: Color(0x1C1C1C))

        case .duckAIVoiceCellBackground:
            return DynamicColor(staticColor: PrimitiveColor.Pondwater.pondwater90)

        case let .rebranding(rebrandingColor):
            return dynamicColor(for: rebrandingColor)

#elseif os(macOS)

        case .fireButtonGradientStart:
            return DynamicColor(staticColor: PrimitiveColor.Mandarin.mandarin50)
        case .fireButtonGradientEnd:
            return DynamicColor(staticColor: PrimitiveColor.Red.red50)
        case .fireButtonPressedGradientStart:
            return DynamicColor(staticColor: PrimitiveColor.Mandarin.mandarin60)
        case .fireButtonPressedGradientEnd:
            return DynamicColor(staticColor: PrimitiveColor.Red.red70)
#endif
        }
    }
}

#if os(iOS)

// MARK: - Onboarding Rebranding 2026

/// Temporary. To be removed once the rebranded palette is rolled out across the whole app;
/// these are palette-independent so onboarding renders rebranded even with the flag off.
private extension SharedColorPaletteDefinition {

    static func dynamicColor(for rebrandingColor: SingleUseColor.Rebranding) -> DynamicColor {
        switch rebrandingColor {
        case .textPrimary:
            return DynamicColor(lightColor: PrimitiveColor.Eggshell.eggshell90, darkColor: PrimitiveColor.GrayScale.white)
        case .textSecondary:
            return DynamicColor(lightColor: PrimitiveColor.Eggshell.eggshell70, darkColor: PrimitiveColor.Eggshell.eggshell30)
        case .backdrop:
            return DynamicColor(lightColor: PrimitiveColor.GrayScale.white, darkColor: .blue80)
        case .buttonsSecondaryDefault:
            return DynamicColor(lightColor: PrimitiveColor.GrayScale.black.opacity(0.06), darkColor: PrimitiveColor.GrayScale.white.opacity(0.04))
        case .buttonsSecondaryPressed:
            return DynamicColor(lightColor: PrimitiveColor.GrayScale.black.opacity(0.12), darkColor: PrimitiveColor.GrayScale.white.opacity(0.08))
        case .buttonsSecondaryText:
            return DynamicColor(lightColor: PrimitiveColor.Eggshell.eggshell90, darkColor: PrimitiveColor.GrayScale.white)
        case .buttonsSecondaryDisabledBackground:
            return DynamicColor(lightColor: PrimitiveColor.GrayScale.black.opacity(0.06), darkColor: .clear)
        case .buttonsSecondaryDisabledText:
            return DynamicColor(lightColor: PrimitiveColor.GrayScale.black.opacity(0.36), darkColor: Color(0x707070))
        case .controlsFillPrimary:
            return DynamicColor(lightColor: PrimitiveColor.GrayScale.black.opacity(0.06), darkColor: PrimitiveColor.GrayScale.white.opacity(0.12))
        case .decorationPrimary:
            return DynamicColor(lightColor: PrimitiveColor.Eggshell.eggshell90.opacity(0.09), darkColor: PrimitiveColor.GrayScale.white.opacity(0.06))
        case .decorationSecondary:
            return DynamicColor(lightColor: PrimitiveColor.Eggshell.eggshell90.opacity(0.16), darkColor: PrimitiveColor.GrayScale.white.opacity(0.09))
        case .calendarStripYellow:
            return DynamicColor(staticColor: PrimitiveColor.Pollen.pollen20)
        }
    }
}

#endif
