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
        case .containerDecorationPrimary:
            return containerDecorationPrimary
        case .containerDecorationSecondary:
            return containerDecorationSecondary
        case .containerDecorationTertiary:
            return containerDecorationTertiary
        case .containerFillPrimary:
            return containerFillPrimary
        case .containerFillSecondary:
            return containerFillSecondary
        case .containerFillTertiary:
            return containerFillTertiary

        /// Controls Colors
        case .controlsDecorationPrimary:
            return controlsDecorationPrimary
        case .controlsDecorationSecondary:
            return controlsDecorationSecondary
        case .controlsDecorationTertiary:
            return controlsDecorationTertiary
        case .controlsDecorationQuaternary:
            return controlsDecorationQuaternary
        case .controlsFillPrimary:
            return controlsFillPrimary
        case .controlsFillSecondary:
            return controlsFillSecondary
        case .controlsFillTertiary:
            return controlsFillTertiary

        /// Decoration Colors
        case .decorationPrimary:
            return decorationPrimary
        case .decorationSecondary:
            return decorationSecondary
        case .decorationTertiary:
            return decorationTertiary

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
        case .icons:
            return icons
        case .iconsPrimary:
            return iconsPrimary
        case .iconsSecondary:
            return iconsSecondary
        case .iconsTertiary:
            return iconsTertiary

        /// System
        case .lines:
            return lines

        /// Shadow Colors
        case .shadowPrimary:
            return shadowPrimary
        case .shadowSecondary:
            return shadowSecondary
        case .shadowTertiary:
            return shadowTertiary

        /// Surface Colors
        case .surface:
            return surface
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

        /// Text Colors
        case .textPrimary:
            return textPrimary
        case .textSecondary:
            return textSecondary
        case .textTertiary:
            return textTertiary

        /// Tone Colors
        case .toneShadePrimary:
            return toneShadePrimary
        case .toneTintPrimary:
            return toneTintPrimary
        }
    }
}

#endif
