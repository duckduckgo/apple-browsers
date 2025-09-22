//
//  ColorPalette+DynamicColors.swift
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

extension ColorPaletteDefinition {

    static func dynamicColor(for designSystemColor: DesignSystemColor) -> DynamicColor {
        switch designSystemColor {

        case .urlBar: return urlBar
        case .background: return background
        case .backgroundTertiary: return backgroundTertiary
        case .backgroundSheets: return backgroundSheets
        case .backgroundBlur: return backgroundBlur
        case .backdrop: return backdrop
        case .panel: return background
        case .surface: return surface
        case .icons: return icons
        case .iconsPrimary: return iconsPrimary
        case .iconsSecondary: return iconsSecondary
        case .iconsTertiary: return iconsTertiary
        case .textPrimary: return textPrimary
        case .lines: return lines
        case .shadowPrimary: return shadowPrimary
        case .shadowSecondary: return shadowSecondary
        case .shadowTertiary: return shadowTertiary
        case .surfaceTertiary: return surfaceTertiary
        case .controlsFillPrimary: return controlsFillPrimary
        case .controlsFillSecondary: return controlsFillSecondary
        case .controlsFillTertiary: return controlsFillTertiary
        case .controlsDecorationPrimary: return controlsDecorationPrimary
        case .controlsDecorationSecondary: return controlsDecorationSecondary
        case .controlsDecorationTertiary: return controlsDecorationTertiary
        case .decorationPrimary: return decorationPrimary
        case .decorationSecondary: return decorationSecondary
        case .decorationTertiary: return decorationTertiary
        case .highlightDecoration: return highlightDecoration
        case .highlightPrimary: return highlightPrimary
        case .accentContentPrimary: return accentContentPrimary
        case .accentContentSecondary: return accentContentSecondary
        case .accentContentTertiary: return accentContentTertiary

        case .accent: return accent
        case .accentGlowPrimary: return accentGlowPrimary
        case .accentGlowSecondary: return accentGlowSecondary
        case .accentPrimary: return accentPrimary
        case .accentSecondary: return accentSecondary
        case .accentTertiary: return accentTertiary
        case .accentTextPrimary: return accentTextPrimary
        case .accentTextSecondary: return accentTextSecondary
        case .accentTextTertiary: return accentTextTertiary

        case .accentAltContentPrimary: return accentAltContentPrimary
        case .accentAltContentSecondary: return accentAltContentSecondary
        case .accentAltContentTertiary: return accentAltContentTertiary
        case .accentAltGlowPrimary: return accentAltGlowPrimary
        case .accentAltPrimary: return accentAltPrimary
        case .accentAltSecondary: return accentAltSecondary
        case .accentAltTertiary: return accentAltTertiary
        case .accentAltTextPrimary: return accentAltTextPrimary
        case .accentAltTextSecondary: return accentAltTextSecondary
        case .accentAltTextTertiary: return accentAltTextTertiary

        case .alertGreen: return alertGreen
        case .alertYellow: return alertYellow
        case .border: return border
        case .textLink: return textLink
        case .textPlaceholder: return textPlaceholder
        case .textSecondary: return textSecondary
        case .textTertiary: return textTertiary
        case .textSelectionFill: return textSelectionFill

        // Buttons/SecondaryFill
        case .buttonsSecondaryFillDefault: return buttonsSecondaryFillDefault
        case .buttonsSecondaryFillPressed: return buttonsSecondaryFillPressed
        case .buttonsSecondaryFillDisabled: return buttonsSecondaryFillDisabled
        case .buttonsSecondaryFillText: return buttonsSecondaryFillText
        case .buttonsSecondaryFillTextDisabled: return buttonsSecondaryFillTextDisabled

        // Buttons/Primary
        case .buttonsPrimaryDefault: return buttonsPrimaryDefault
        case .buttonsPrimaryPressed: return buttonsPrimaryPressed
        case .buttonsPrimaryDisabled: return buttonsPrimaryDisabled
        case .buttonsPrimaryText: return buttonsPrimaryText
        case .buttonsPrimaryTextDisabled: return buttonsPrimaryTextDisabled

        // Buttons/SecondaryWire
        case .buttonsSecondaryWireDefault: return buttonsSecondaryWireDefault
        case .buttonsSecondaryWirePressedFill: return buttonsSecondaryWirePressedFill
        case .buttonsSecondaryWireDisabledStroke: return buttonsSecondaryWireDisabledStroke
        case .buttonsSecondaryWireText: return buttonsSecondaryWireText
        case .buttonsSecondaryWireTextPressed: return buttonsSecondaryWireTextPressed
        case .buttonsSecondaryWireTextDisabled: return buttonsSecondaryWireTextDisabled

        // Buttons/Ghost
        case .buttonsGhostPressedFill: return buttonsGhostPressedFill
        case .buttonsGhostText: return buttonsGhostText
        case .buttonsGhostTextPressed: return buttonsGhostTextPressed
        case .buttonsGhostTextDisabled: return buttonsGhostTextDisabled

        // Buttons/Color
        case .buttonsBlack: return buttonsBlack
        case .buttonsWhite: return buttonsWhite

        // Various
        case .variousOutline: return variousOutline

        // Destructive
        case .destructiveContentPrimary: return destructiveContentPrimary
        case .destructiveContentSecondary: return destructiveContentSecondary
        case .destructiveContentTertiary: return destructiveContentTertiary
        case .destructiveGlow: return destructiveGlow
        case .destructivePrimary: return destructivePrimary
        case .destructiveSecondary: return destructiveSecondary
        case .destructiveTertiary: return destructiveTertiary
        case .destructiveTextPrimary: return destructiveTextPrimary
        case .destructiveTextSecondary: return destructiveTextSecondary
        case .destructiveTextTertiary: return destructiveTextTertiary

        // Surfaces
        case .surfaceBackdrop: return surfaceBackdrop
        case .surfaceCanvas: return surfaceCanvas
        case .surfacePrimary: return surfacePrimary
        case .surfaceSecondary: return surfaceSecondary

        // Tone
        case .toneShadePrimary: return toneShadePrimary
        case .toneTintPrimary: return toneTintPrimary

        // Buttons/DeleteGhost
        case .buttonsDeleteGhostPressedFill: return buttonsDeleteGhostPressedFill
        case .buttonsDeleteGhostText: return buttonsDeleteGhostText
        case .buttonsDeleteGhostTextPressed: return buttonsDeleteGhostTextPressed
        case .buttonsDeleteGhostTextDisabled: return buttonsDeleteGhostTextDisabled
        }
    }
}
