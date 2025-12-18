//
//  SharedColorPaletteDefinition+DynamicColors.swift
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
import SwiftUI

#if os(macOS)
extension SharedColorPaletteDefinition {

    /// Gets dynamic color proxy for a specific semantic color based on the JSON import
    static func dynamicColor(for designSystemColor: SharedDesignSystemColor) -> DynamicColor {

        switch designSystemColor {
        /// Accent Colors
        case .accentContentPrimary:
            return accentContentPrimary
        case .accentContentSecondary:
            return accentContentSecondary
        case .accentContentTertiary:
            return accentContentTertiary
        case .accentGlowPrimary:
            return accentGlowPrimary
        case .accentGlowSecondary:
            return accentGlowSecondary
        case .accentPrimary:
            return accentPrimary
        case .accentQuaternary:
            return accentQuaternary
        case .accentSecondary:
            return accentSecondary
        case .accentTertiary:
            return accentTertiary
        case .accentTextPrimary:
            return accentTextPrimary
        case .accentTextSecondary:
            return accentTextSecondary
        case .accentTextTertiary:
            return accentTextTertiary

        /// Accent Alt Colors
        case .accentAltContentPrimary:
            return accentAltContentPrimary
        case .accentAltContentSecondary:
            return accentAltContentSecondary
        case .accentAltContentTertiary:
            return accentAltContentTertiary
        case .accentAltGlowPrimary:
            return accentAltGlowPrimary
        case .accentAltGlowSecondary:
            return accentAltGlowSecondary
        case .accentAltPrimary:
            return accentAltPrimary
        case .accentAltSecondary:
            return accentAltSecondary
        case .accentAltTertiary:
            return accentAltTertiary
        case .accentAltTextPrimary:
            return accentAltTextPrimary
        case .accentAltTextSecondary:
            return accentAltTextSecondary
        case .accentAltTextTertiary:
            return accentAltTextTertiary

        /// Alert
        case .alertGreen:
            return alertGreen
        case .alertYellow:
            return alertYellow

        /// Buttons/Primary
        case .buttonsPrimaryDefault:
            return buttonsPrimaryDefault
        case .buttonsPrimaryPressed:
            return buttonsPrimaryPressed
        case .buttonsPrimaryDisabled:
            return buttonsPrimaryDisabled
        case .buttonsPrimaryText:
            return buttonsPrimaryText
        case .buttonsPrimaryTextDisabled:
            return buttonsPrimaryTextDisabled

        /// Buttons/SecondaryFill
        case .buttonsSecondaryFillDefault:
            return buttonsSecondaryFillDefault
        case .buttonsSecondaryFillPressed:
            return buttonsSecondaryFillPressed
        case .buttonsSecondaryFillDisabled:
            return buttonsSecondaryFillDisabled
        case .buttonsSecondaryFillText:
            return buttonsSecondaryFillText
        case .buttonsSecondaryFillTextDisabled:
            return buttonsSecondaryFillTextDisabled

        case .buttonsWhite:
            return buttonsWhite

        /// Container Colors
        case .containerFillPrimary:
            return containerFillPrimary
        case .containerFillSecondary:
            return containerFillSecondary
        case .containerFillTertiary:
            return containerFillTertiary
        case .containerBorderPrimary:
            return containerBorderPrimary
        case .containerBorderSecondary:
            return containerBorderSecondary
        case .containerBorderTertiary:
            return containerBorderTertiary

        /// Controls Colors
        case .controlsBorderPrimary:
            return controlsBorderPrimary
        case .controlsBorderSecondary:
            return controlsBorderSecondary
        case .controlsBorderTertiary:
            return controlsBorderTertiary
        case .controlsBorderQuaternary:
            return controlsBorderQuaternary
        case .controlsFillPrimary:
            return controlsFillPrimary
        case .controlsFillSecondary:
            return controlsFillSecondary
        case .controlsFillTertiary:
            return controlsFillTertiary
        case .controlsRaisedBackdrop:
            return FigmaColorPalette.controlsRaisedBackdrop
        case .controlsRaisedFillPrimary:
            return FigmaColorPalette.controlsRaisedFillPrimary

        /// Destructive Colors
        case .destructiveContentPrimary:
            return destructiveContentPrimary
        case .destructiveContentSecondary:
            return destructiveContentSecondary
        case .destructiveContentTertiary:
            return destructiveContentTertiary
        case .destructiveGlow:
            return destructiveGlow
        case .destructivePrimary:
            return destructivePrimary
        case .destructiveSecondary:
            return destructiveSecondary
        case .destructiveTertiary:
            return destructiveTertiary
        case .destructiveTextPrimary:
            return destructiveTextPrimary
        case .destructiveTextSecondary:
            return destructiveTextSecondary
        case .destructiveTextTertiary:
            return destructiveTextTertiary

        /// Highlight Colors
        case .highlightPrimary:
            return highlightPrimary

        /// Icons Colors
        case .iconsPrimary:
            return iconsPrimary
        case .iconsSecondary:
            return iconsSecondary
        case .iconsTertiary:
            return iconsTertiary

        /// System
        case .lines:
            return lines
        case .spinnerStart:
            // Non-specialized, we'll always use the default
            return FigmaColorPalette.spinnerStart
        case .spinnerFinal:
            // Non-specialized, we'll always use the default
            return FigmaColorPalette.spinnerFinal

        /// Shadow Colors
        case .shadowPrimary:
            return shadowPrimary
        case .shadowSecondary:
            return shadowSecondary
        case .shadowTertiary:
            return shadowTertiary

        /// Surface Colors
        case .surfaceBackdrop:
            return surfaceBackdrop
        case .surfaceCanvas:
            return surfaceCanvas
        case .surfacePrimary:
            return surfacePrimary
        case .surfaceSecondary:
            return surfaceSecondary
        case .surfaceTertiary:
            return surfaceTertiary

        /// Surface Decoration
        case .surfaceDecorationPrimary:
            return surfaceDecorationPrimary
        case .surfaceDecorationSecondary:
            return surfaceDecorationSecondary
        case .surfaceDecorationTertiary:
            return surfaceDecorationTertiary

        /// Text Colors
        case .textLink:
            return DynamicColor(lightHex: 0x3969EF, darkHex: 0x7295F6)
        case .textPrimary:
            return textPrimary
        case .textSecondary:
            return textSecondary
        case .textSuccess:
            return DynamicColor(lightColor: .green60, darkColor: .green30)
        case .textTertiary:
            return textTertiary

        /// Tone Colors
        case .toneShadePrimary:
            return toneShadePrimary

        /// Permission Center
        case .permissionCenterBackground:
            return DynamicColor(lightColor: .white, darkColor: Color(0x333333))
        case .permissionCenterContainerBackground:
            return DynamicColor(lightColor: Color(0x000000).opacity(0.03), darkColor: Color(0xFFFFFF).opacity(0.06))
        case .permissionWarningBackground:
            return DynamicColor(lightColor: Color(0xFFF0C2), darkColor: Color(0xC18010).opacity(0.16))
        case .permissionReloadButtonBackground:
            return DynamicColor(lightColor: .white, darkColor: Color(0x857A6E))
        case .permissionReloadButtonText:
            return DynamicColor(lightColor: Color(0x333333), darkColor: Color(0xE8E8E8))
        }
    }
}

#endif
