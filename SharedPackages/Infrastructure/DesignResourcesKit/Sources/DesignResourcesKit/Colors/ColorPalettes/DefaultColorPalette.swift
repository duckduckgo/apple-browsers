//
//  DefaultColorPalette.swift
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

/// See [Figma](https://www.figma.com/design/3W4vi0zX8hrpQc7zInQQB6/🎨-Global-Colors---Styles?node-id=11-1&p=f&vars=1&var-id=5476-10186&m=dev)
struct DefaultColorPalette: ColorPaletteDefinition {
    private static let x1F1F1F = Color(0x1F1F1F)
    private static let x141415 = Color(0x141415)
    private static let x181818 = Color(0x181818)
    private static let x27282A = Color(0x27282A)
    private static let x333333 = Color(0x333333)
    private static let x333538 = Color(0x333538)
    private static let x404145 = Color(0x404145)
    private static let xE0E0E0 = Color(0xE0E0E0)
    private static let xF2F2F2 = Color(0xF2F2F2)
    private static let xF3F6FF = Color(0xF3F6FF)
    private static let xF9F9F9 = Color(0xF9F9F9)
    private static let x000000 = Color(0x000000)
    private static let xFFFFFF = Color(0xFFFFFF)
    private static let xFAFAFA = Color(0xFAFAFA)
    private static let x3969EF = Color(0x3969EF)
    private static let x8FABF9 = Color(0x8FABF9)
    private static let x0B2059 = Color(0x0B2059)

    // New dark mode colors
    private static let x080808 = Color(0x080808)
    private static let x282828 = Color(0x282828)
    private static let x373737 = Color(0x373737)
    private static let x3D3D3D = Color(0x3D3D3D)
    private static let x474747 = Color(0x474747)
    private static let x4D4D4D = Color(0x4D4D4D)
    private static let x1C1C1C = Color(0x1C1C1C)
    private static let x7295F6 = Color(0x7295F6)
    private static let xF6CDD1 = Color(0xF6CDD1)
    private static let x5A2A2A = Color(0x5A2A2A)
    private static let xD4452F = Color(0xD4452F)

    // URL bar
    private static let urlBar = DynamicColor(lightColor: .white, darkColor: x474747)

    // Surfaces
    private static let surface = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let surfaceSecondary = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let surfaceTertiary = DynamicColor(lightColor: .white, darkColor: x474747)
    private static let surfaceCanvas = DynamicColor(lightColor: xFAFAFA, darkColor: x1C1C1C)

    // Backgrounds
    private static let backdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x080808)
    private static let background = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    private static let backgroundTertiary = DynamicColor(lightColor: .white, darkColor: x3D3D3D)
    private static let backgroundSheets = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let backgroundPromptMessage = DynamicColor(lightColor: xF3F6FF, darkColor: xFFFFFF.opacity(0.09))

    // Shadow
    private static let shadowPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.04), darkColor: .shade(0.16))
    private static let shadowSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.08), darkColor: .shade(0.24))
    private static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.16), darkColor: .shade(0.32))

    // Controls
    private static let controlsFillPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))
    private static let controlsFillSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.12), darkColor: xF9F9F9.opacity(0.18))
    private static let controlsFillTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.18), darkColor: xF9F9F9.opacity(0.24))
    private static let controlsRaisedBackdrop = DynamicColor(lightColor: x000000.opacity(0.09), darkColor: xFFFFFF.opacity(0.12))

    private static let controlsRaisedFillPrimary = DynamicColor(lightColor: .white, darkColor: xFFFFFF.opacity(0.18))

    // Icons
    private static let icons = DynamicColor(lightColor: x1F1F1F.opacity(0.84), darkColor: .tint(0.78))
    private static let iconsSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: .tint(0.48))
    private static let iconsTertiary = DynamicColor(lightColor: x000000.opacity(0.36), darkColor: xFFFFFF.opacity(0.24))

    // Text
    private static let textPrimary = DynamicColor(lightColor: x1F1F1F, darkColor: .tint(0.9))
    private static let textSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.72), darkColor: .tint(0.6))
    private static let textTertiary = DynamicColor(lightColor: x000000.opacity(0.36), darkColor: xFFFFFF.opacity(0.36))
    private static let textPlaceholder = DynamicColor(lightColor: x1F1F1F.opacity(0.4), darkColor: .tint(0.4))

    // Container
    private static let containerBorderPrimary = DynamicColor(lightColor: x000000.opacity(0.06), darkColor: xFFFFFF.opacity(0.09))

    // System
    private static let lines = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

    // Decorations
    private static let decorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.36))
    private static let decorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.48), darkColor: xF9F9F9.opacity(0.64))
    private static let decorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.60), darkColor: xF9F9F9.opacity(0.74))
    private static let decorationQuaternary = DynamicColor(lightColor: x1F1F1F.opacity(0.03), darkColor: xF9F9F9.opacity(0.03))

    // Fire Tabs
    private static let fireModeAccent = DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin50, darkColor: RebrandingColor.Mandarin.mandarin40)
    private static let fireModeAccentDark = DynamicColor(staticColor: RebrandingColor.Mandarin.mandarin40)
    private static let fireModeAccentTertiary = DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin70, darkColor: RebrandingColor.Mandarin.mandarin60)
    private static let fireModeBackground = DynamicColor(lightColor: x3D3D3D, darkColor: x080808)
    private static let fireModeCardBackground = DynamicColor(lightColor: x3D3D3D, darkColor: x1C1C1C)

    // DuckAI Cells
    private static let duckAIVoiceCellBackground = DynamicColor(staticColor: RebrandingColor.Pondwater.pondwater90)

    // Highlight
    private static let highlightDecoration = DynamicColor(lightColor: .tint(0.24), darkColor: xF9F9F9.opacity(0.12))

    // Accents
    private static let accentContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)

    private static let accentTertiary = DynamicColor(lightColor: .blue70, darkColor: .blue50)

    // Text
    private static let accentTextPrimary = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let textSelectionFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))

    // Brand
    private static let accentPrimary = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let accentGlowSecondary = DynamicColor(lightColor: .blue50.opacity(0.12), darkColor: x7295F6.opacity(0.12))
    // Unused in the default palette (rebrand only). Falls back to the legacy ghost glow.
    private static let accentGlowPrimary = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let accentAltGlowPrimary = DynamicColor(lightColor: x7295F6.opacity(0.20), darkColor: x8FABF9.opacity(0.20))
    private static let accentAltContentPrimary = DynamicColor(staticColor: x0B2059)

    // Unused in the default palette (rebrand only). Falls back to the primary accent blue.
    private static let accentBrandPrimary = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let accentBrandTertiary = DynamicColor(lightColor: .blue70, darkColor: .blue50)
    private static let accentBrandContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)

    // System
    private static let border = DynamicColor(lightColor: .gray30, darkColor: .gray40)

    // Alert
    private static let alertGreen = DynamicColor(lightColor: .alertGreen, darkColor: .alertGreen)
    private static let alertYellow = DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow)
    private static let shieldPrivacy = DynamicColor(lightColor: RebrandingColor.Lilypad.lilypad70, darkColor: RebrandingColor.Lilypad.lilypad50)

    // Destructive
    private static let destructivePrimary = DynamicColor(lightColor: .alertRed, darkColor: .alertRed20)
    private static let destructiveContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)
    // Unused in the default palette (rebrand only). Falls back to the legacy destructove pressed / glow.
    private static let destructiveTertiary = DynamicColor(lightColor: .alertRed80, darkColor: .alertRed40)
    private static let destructiveGlowPrimary = DynamicColor(lightColor: Color(0xE5244B).opacity(0.2), darkColor: Color(0xE5244B).opacity(0.2))

    // Buttons/Primary
    private static let buttonsPrimaryDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsPrimaryPressed = DynamicColor(lightColor: .blue70, darkColor: .blue50)
    private static let buttonsPrimaryDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    private static let buttonsPrimaryText = DynamicColor(lightColor: .white, darkColor: .shade(0.84))
    private static let buttonsPrimaryTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryFill
    private static let buttonsSecondaryFillDefault = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    private static let buttonsSecondaryFillPressed = DynamicColor(lightColor: .shade(0.18), darkColor: .tint(0.3))
    private static let buttonsSecondaryFillDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    private static let buttonsSecondaryFillText = DynamicColor(lightColor: .shade(0.84), darkColor: .white)
    private static let buttonsSecondaryFillTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryWire
    private static let buttonsSecondaryWireDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsSecondaryWirePressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let buttonsSecondaryWireDisabledStroke = DynamicColor(lightColor: .shade(0.12), darkColor: .tint(0.24))
    private static let buttonsSecondaryWireText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsSecondaryWireTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    private static let buttonsSecondaryWireTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Ghost
    private static let buttonsGhostPressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let buttonsGhostText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsGhostTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    private static let buttonsGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Color
    private static let buttonsWhite = DynamicColor(lightColor: .white, darkColor: .black)

    // Buttons/DeleteGhost
    private static let buttonsDeleteGhostPressedFill = DynamicColor(lightColor: .alertRed50.opacity(0.12), darkColor: .alertRed20.opacity(0.18))
    private static let buttonsDeleteGhostTextPressed = DynamicColor(lightColor: .alertRed70, darkColor: .alertRed10)
    private static let buttonsDeleteGhostText = DynamicColor(lightColor: .alertRedOnLight, darkColor: .alertRedOnDark)
    private static let buttonsDeleteGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/DestructivePrimary
    private static let buttonsDestructivePrimaryPressed = DynamicColor(lightColor: .alertRed80, darkColor: .alertRed40)

    static func dynamicColor(for designSystemColor: DesignSystemColor) -> DynamicColor {
        switch designSystemColor {

        case .urlBar: return urlBar
        case .background: return background
        case .backgroundTertiary: return backgroundTertiary
        case .backgroundSheets: return backgroundSheets
        case .backgroundPromptMessage: return backgroundPromptMessage
        case .backdrop: return backdrop
        case .panel: return background
        case .icons: return icons
        case .iconsSecondary: return iconsSecondary
        case .iconsTertiary: return iconsTertiary
        case .textPrimary: return textPrimary
        case .containerBorderPrimary: return containerBorderPrimary
        case .lines: return lines
        case .shadowPrimary: return shadowPrimary
        case .shadowSecondary: return shadowSecondary
        case .shadowTertiary: return shadowTertiary
        case .controlsFillPrimary: return controlsFillPrimary
        case .controlsFillSecondary: return controlsFillSecondary
        case .controlsFillTertiary: return controlsFillTertiary
        case .controlsRaisedBackdrop: return controlsRaisedBackdrop
        case .controlsRaisedFillPrimary: return controlsRaisedFillPrimary
        case .decorationPrimary: return decorationPrimary
        case .decorationSecondary: return decorationSecondary
        case .decorationTertiary: return decorationTertiary
        case .decorationQuaternary: return decorationQuaternary
        case .highlightDecoration: return highlightDecoration
        case .accentContentPrimary: return accentContentPrimary
        case .accentTertiary: return accentTertiary

        case .surface: return surface
        case .surfaceSecondary: return surfaceSecondary
        case .surfaceTertiary: return surfaceTertiary
        case .surfaceCanvas: return surfaceCanvas

        case .accentPrimary: return accentPrimary
        case .accentGlowPrimary: return accentGlowPrimary
        case .accentGlowSecondary: return accentGlowSecondary
        case .accentAltGlowPrimary: return accentAltGlowPrimary
        case .accentAltContentPrimary: return accentAltContentPrimary
        case .accentBrandPrimary: return accentBrandPrimary
        case .accentBrandTertiary: return accentBrandTertiary
        case .accentBrandContentPrimary: return accentBrandContentPrimary
        case .alertGreen: return alertGreen
        case .alertYellow: return alertYellow
        case .shieldPrivacy: return shieldPrivacy
        case .border: return border
        case .accentTextPrimary: return accentTextPrimary
        case .textPlaceholder: return textPlaceholder
        case .textSecondary: return textSecondary
        case .textTertiary: return textTertiary
        case .textSelectionFill: return textSelectionFill

        // Destructive
        case .destructivePrimary: return destructivePrimary
        case .destructiveTertiary: return destructiveTertiary
        case .destructiveContentPrimary: return destructiveContentPrimary
        case .destructiveGlowPrimary: return destructiveGlowPrimary

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
        case .buttonsWhite: return buttonsWhite

            // Buttons/DeleteGhost
        case .buttonsDeleteGhostPressedFill: return buttonsDeleteGhostPressedFill
        case .buttonsDeleteGhostText: return buttonsDeleteGhostText
        case .buttonsDeleteGhostTextPressed: return buttonsDeleteGhostTextPressed
        case .buttonsDeleteGhostTextDisabled: return buttonsDeleteGhostTextDisabled

            // Buttons/DestructivePrimary
        case .buttonsDestructivePrimaryPressed: return buttonsDestructivePrimaryPressed
        }
    }

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        switch singleUseColor {
        case .controlWidgetBackground:
            return DynamicColor(staticColor: .x818387)
        case .unifiedFeedbackFieldBackground:
            return DynamicColor(lightColor: surface.lightColor, darkColor: .x1C1C1E)
        case .privacyDashboardBackground:
            return DynamicColor(lightColor: surface.lightColor, darkColor: background.darkColor)
        case .inputContentSeparator:
            return DynamicColor(lightColor: shadowTertiary.lightColor, darkColor: highlightDecoration.darkColor)
        case .whatsNewBackground:
            return DynamicColor(lightColor: .white, darkColor: background.darkColor)
        case .duckAIContextualSheetBackground:
            return DynamicColor(lightColor: .white, darkColor: .x161616)
        case .duckAIWebViewBackground:
            return DynamicColor(lightColor: .white, darkColor: .x111111)
        case .unifiedToggleInputCardBackground:
            return DynamicColor(lightColor: .white, darkColor: x3D3D3D)
        case .unifiedToggleInputStopButtonBackground:
            return DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.12))
        case .floatingAddressBarBackground:
            return DynamicColor(lightColor: .shade(0.05), darkColor: .tint(0.08))
        case .unifiedToggleInputAttachmentErrorBannerBackground:
            return DynamicColor(lightColor: xF6CDD1, darkColor: x5A2A2A)
        case .unifiedToggleInputAttachmentErrorText:
            return DynamicColor(lightColor: .black.opacity(0.84), darkColor: .white.opacity(0.88))
        case .unifiedToggleInputAttachmentErrorIcon:
            return DynamicColor(staticColor: xD4452F)
        case .tabSwitcherTrackerCountBackground:
            return DynamicColor(lightColor: .green0, darkColor: .x2C3A2A)
        case let .rebranding(rebrandingColor):
            return dynamicColor(for: rebrandingColor)
        case .toolbarButton:
            return DynamicColor(lightColor: x1F1F1F.opacity(0.918), darkColor: .tint(0.905))
        case .fireModeAccent: return fireModeAccent
        case .fireModeAccentDark: return fireModeAccentDark
        case .fireModeAccentTertiary: return fireModeAccentTertiary
        case .fireModeBackground: return fireModeBackground
        case .fireModeCardBackground: return fireModeCardBackground
        case .duckAIVoiceCellBackground: return duckAIVoiceCellBackground
        }
    }
}

// MARK: - Rebranding 2026

// Temporary. To be removed after Rebranding Color Palette is rolled out across the whole app.
private extension DefaultColorPalette {

    private static func dynamicColor(for rebrandingColor: SingleUseColor.Rebranding) -> DynamicColor {
        switch rebrandingColor {
        case .textPrimary:
            return DynamicColor(lightColor: RebrandingColor.Eggshell.eggshell90, darkColor: RebrandingColor.GrayScale.white)
        case .textSecondary:
            return DynamicColor(lightColor: RebrandingColor.Eggshell.eggshell70, darkColor: RebrandingColor.Eggshell.eggshell30)
        case .textLink:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60, darkColor: RebrandingColor.Pondwater.pondwater40)
        case .accentPrimary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60, darkColor: RebrandingColor.Pondwater.pondwater40)
        case .accentPrimaryPressed:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater80, darkColor: RebrandingColor.Pondwater.pondwater60)
        case .accentPrimaryText:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.white, darkColor: RebrandingColor.Pollen.pollen100)
        case .accentGlowPrimary:
            return DynamicColor(lightColor: RebrandingColor.Pondwater.pondwater60.opacity(0.2), darkColor: RebrandingColor.Pondwater.pondwater40.opacity(0.2))
        case .backdrop:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.white, darkColor: .blue80)
        case .buttonsPrimaryDefault:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin50, darkColor: RebrandingColor.Pollen.pollen40)
        case .buttonsPrimaryPressed:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin70, darkColor: RebrandingColor.Pollen.pollen60)
        case .buttonsPrimaryText:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.white, darkColor: RebrandingColor.Pollen.pollen100)
        case .buttonsContentDisabled:
            return DynamicColor(lightColor: Color(0xF5F4F6), darkColor: Color(0x212020))
        case .buttonsSecondaryDefault:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.black.opacity(0.06), darkColor: RebrandingColor.GrayScale.white.opacity(0.04))
        case .buttonsSecondaryPressed:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.black.opacity(0.12), darkColor: RebrandingColor.GrayScale.white.opacity(0.08))
        case .buttonsSecondaryText:
            return DynamicColor(lightColor: RebrandingColor.Eggshell.eggshell90, darkColor: RebrandingColor.GrayScale.white)
        case .buttonsSecondaryDisabledBackground:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.black.opacity(0.06), darkColor: .clear)
        case .buttonsSecondaryDisabledText:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.black.opacity(0.36), darkColor: Color(0x707070))
        case .destructivePrimary:
            return DynamicColor(lightColor: RebrandingColor.Red.red50, darkColor: RebrandingColor.Red.red40)
        case .destructivePrimaryPressed:
            return DynamicColor(lightColor: RebrandingColor.Red.red70, darkColor: RebrandingColor.Red.red60)
        case .destructivePrimaryText:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.white, darkColor: RebrandingColor.Pollen.pollen100)
        case .destructiveGlowPrimary:
            return DynamicColor(lightColor: Color(0xE5244B).opacity(0.2), darkColor: Color(0xE5244B).opacity(0.2))
        case .controlsFillPrimary:
            return DynamicColor(lightColor: RebrandingColor.GrayScale.black.opacity(0.06), darkColor: RebrandingColor.GrayScale.white.opacity(0.12))
        case .decorationPrimary:
            return DynamicColor(lightColor: RebrandingColor.Eggshell.eggshell90.opacity(0.09), darkColor: RebrandingColor.GrayScale.white.opacity(0.06))
        case .decorationSecondary:
            return DynamicColor(lightColor: RebrandingColor.Eggshell.eggshell90.opacity(0.16), darkColor: RebrandingColor.GrayScale.white.opacity(0.09))
        case .alertGreen:
            return DynamicColor(staticColor: RebrandingColor.Green.green40)
        }
    }

}

#endif
