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

/// See [Figma](https://www.figma.com/design/3W4vi0zX8hrpQc7zInQQB6/🎨-Global-Colors---Styles?node-id=11-1&p=f&vars=1&var-id=5476-10186&m=dev)
struct DefaultColorPalette: ColorPaletteDefinition {
    private static let x1F1F1F = Color(0x1F1F1F)
    private static let x141415 = Color(0x141415)
    private static let x181818 = Color(0x181818)
    private static let x27282A = Color(0x27282A)
    private static let x333538 = Color(0x333538)
    private static let x404145 = Color(0x404145)
    private static let xE0E0E0 = Color(0xE0E0E0)
    private static let xF2F2F2 = Color(0xF2F2F2)
    private static let xF9F9F9 = Color(0xF9F9F9)
    private static let x000000 = Color(0x000000)
    private static let xFFFFFF = Color(0xFFFFFF)
    private static let x3969EF = Color(0x3969EF)

    // New dark mode colors
    private static let x080808 = Color(0x080808)
    private static let x282828 = Color(0x282828)
    private static let x373737 = Color(0x373737)
    private static let x474747 = Color(0x474747)
    private static let x7295F6 = Color(0x7295F6)

    // Additional hex colors for new semantic colors
    private static let x070707 = Color(0x070707)
    private static let x1C1C1C = Color(0x1C1C1C)
    private static let x16161751 = Color(0x16161751)
    private static let x0000000F = Color(0x0000000F)
    private static let x0000005B = Color(0x0000005B)
    private static let xFFFFFF5B = Color(0xFFFFFF5B)
    private static let x1F1F1F4C = Color(0x1F1F1F4C)
    private static let xF9F9F95B = Color(0xF9F9F95B)
    private static let x1F1F1F7A = Color(0x1F1F1F7A)
    private static let xF9F9F9A3 = Color(0xF9F9F9A3)
    private static let x1F1F1F99 = Color(0x1F1F1F99)
    private static let xF9F9F9B7 = Color(0xF9F9F9B7)
    private static let xF9F9F9CC = Color(0xF9F9F9CC)
    private static let x1F1F1fB7 = Color(0x1F1F1fB7)
    private static let xCCDAFF = Color(0xCCDAFF)
    private static let x03091A = Color(0x03091A)
    private static let xADC2FC = Color(0xADC2FC)
    private static let x3969EF33 = Color(0x3969EF33)
    private static let x7295F633 = Color(0x7295F633)
    private static let x2B55CA = Color(0x2B55CA)
    private static let x557FF3 = Color(0x557FF3)
    private static let x1E42A4 = Color(0x1E42A4)
    private static let x8FABF9 = Color(0x8FABF9)
    private static let x0B2059 = Color(0x0B2059)
    private static let xE5EDFF = Color(0xE5EDFF)
    private static let x051133 = Color(0x051133)
    private static let x8FABF933 = Color(0x8FABF933)
    private static let x14307E = Color(0x14307E)
    private static let x000000D6 = Color(0x000000D6)
    private static let xFFFFFFE5 = Color(0xFFFFFFE5)
    private static let x000000E5 = Color(0x000000E5)
    private static let xFFFFFF99 = Color(0xFFFFFF99)
    private static let x00000099 = Color(0x00000099)
    private static let xEE102533 = Color(0xEE102533)
    private static let xEE1025 = Color(0xEE1025)
    private static let xD11527 = Color(0xD11527)
    private static let xAA1926 = Color(0xAA1926)
    private static let xFFFFFF3D = Color(0xFFFFFF3D)
    private static let xF9F9F91E = Color(0xF9F9F91E)
    private static let xFAFAFA = Color(0xFAFAFA)
    private static let xFFFFFF7A = Color(0xFFFFFF7A)
    private static let xFFFFFFC6 = Color(0xFFFFFFc6)

    // URL bar
    private static let urlBar = DynamicColor(lightColor: .white, darkColor: x474747)

    // Surfaces
    private static let surface = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let surfaceTertiary = DynamicColor(lightColor: .white, darkColor: .x474747)

    // Backgrounds
    private static let backdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x080808)
    private static let background = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    private static let backgroundTertiary = DynamicColor(lightColor: .white, darkColor: x474747)
    private static let backgroundSheets = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let backgroundBlur = DynamicColor(staticColor: .gray90.opacity(0.7))

    // Shadow
    private static let shadowPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.04), darkColor: .shade(0.16))
    private static let shadowSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.08), darkColor: .shade(0.24))
    private static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.16), darkColor: .shade(0.32))

    // Controls
    private static let controlsFillPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))
    private static let controlsFillSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.12), darkColor: xF9F9F9.opacity(0.18))
    private static let controlsFillTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.18), darkColor: xF9F9F9.opacity(0.24))

    // Icons
    private static let icons = DynamicColor(lightColor: x1F1F1F.opacity(0.84), darkColor: .tint(0.78))
    private static let iconsPrimary = DynamicColor(lightColor: x000000D6, darkColor: xFFFFFFC6)
    private static let iconsSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: .tint(0.48))
    private static let iconsTertiary = DynamicColor(lightColor: x000000.opacity(0.36), darkColor: xFFFFFF.opacity(0.24))

    // Text
    private static let textPrimary = DynamicColor(lightColor: x1F1F1F, darkColor: .tint(0.9))
    private static let textSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.72), darkColor: .tint(0.6))
    private static let textTertiary = DynamicColor(lightColor: x0000005B, darkColor: xFFFFFF5B)
    private static let textPlaceholder = DynamicColor(lightColor: x1F1F1F.opacity(0.4), darkColor: .tint(0.4))

    // System
    private static let lines = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

    // Decorations
    private static let decorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.36))
    private static let decorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.48), darkColor: xF9F9F9.opacity(0.64))
    private static let decorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.60), darkColor: xF9F9F9.opacity(0.74))

    // Highlight
    private static let highlightDecoration = DynamicColor(lightColor: .tint(0.24), darkColor: xF9F9F9.opacity(0.12))
    private static let highlightPrimary = DynamicColor(lightColor: xFFFFFF3D, darkColor: xF9F9F91E)

    // Accents
    private static let accentContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)

    // Various
    private static let variousIPadTabs = DynamicColor(lightColor: .gray20, darkColor: .black)
    private static let variousOutline = DynamicColor(lightColor: .shade(0.24), darkColor: .tint(0.24))

    // Text
    private static let textLink = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let textSelectionFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))

    // Brand
    private static let accent = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let accentGlowSecondary = DynamicColor(lightColor: x3969EF.opacity(0.12), darkColor: x7295F6.opacity(0.12))

    // System
    private static let border = DynamicColor(lightColor: .gray30, darkColor: .gray40)

    // Alert
    private static let alertGreen = DynamicColor(lightColor: .alertGreen, darkColor: .alertGreen)
    private static let alertYellow = DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow)

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
    private static let buttonsBlack = DynamicColor(lightColor: .black, darkColor: .white)
    private static let buttonsWhite = DynamicColor(lightColor: .white, darkColor: .black)

    // Buttons/DeleteGhost
    private static let buttonsDeleteGhostPressedFill = DynamicColor(lightColor: .alertRed50.opacity(0.12), darkColor: .alertRed20.opacity(0.18))
    private static let buttonsDeleteGhostTextPressed = DynamicColor(lightColor: .alertRed70, darkColor: .alertRed10)
    private static let buttonsDeleteGhostText = DynamicColor(lightColor: .alertRedOnLight, darkColor: .alertRedOnDark)
    private static let buttonsDeleteGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Controls
    private static let controlsDecorationPrimary = DynamicColor(lightColor: x1F1F1F4C, darkColor: xF9F9F95B)
    private static let controlsDecorationSecondary = DynamicColor(lightColor: x1F1F1F7A, darkColor: xF9F9F9A3)
    private static let controlsDecorationTertiary = DynamicColor(lightColor: x1F1F1F99, darkColor: xF9F9F9B7)
    private static let controlsDecorationQuaternary = DynamicColor(lightColor: x1F1F1fB7, darkColor: xF9F9F9CC)

    // Accent
    private static let accentContentSecondary = DynamicColor(lightColor: xCCDAFF, darkColor: x03091A)
    private static let accentContentTertiary = DynamicColor(lightColor: xADC2FC, darkColor: x000000)
    private static let accentGlowPrimary = DynamicColor(lightColor: x3969EF33, darkColor: x7295F633)
    private static let accentPrimary = DynamicColor(lightColor: x3969EF, darkColor: x7295F6)
    private static let accentSecondary = DynamicColor(lightColor: x2B55CA, darkColor: x557FF3)
    private static let accentTertiary = DynamicColor(lightColor: x1E42A4, darkColor: x3969EF)
    private static let accentTextPrimary = DynamicColor(lightColor: x3969EF, darkColor: xADC2FC)
    private static let accentTextSecondary = DynamicColor(lightColor: x2B55CA, darkColor: x8FABF9)
    private static let accentTextTertiary = DynamicColor(lightColor: x1E42A4, darkColor: x7295F6)

    // Accent Alt
    private static let accentAltContentPrimary = DynamicColor(lightColor: x1E42A4, darkColor: xCCDAFF)
    private static let accentAltContentSecondary = DynamicColor(lightColor: x0B2059, darkColor: xE5EDFF)
    private static let accentAltContentTertiary = DynamicColor(lightColor: x051133, darkColor: xFFFFFF)
    private static let accentAltGlowPrimary = DynamicColor(lightColor: x7295F633, darkColor: x8FABF933)
    private static let accentAltPrimary = DynamicColor(lightColor: xCCDAFF, darkColor: x2B55CA)
    private static let accentAltSecondary = DynamicColor(lightColor: xADC2FC, darkColor: x1E42A4)
    private static let accentAltTertiary = DynamicColor(lightColor: x8FABF9, darkColor: x14307E)
    private static let accentAltTextPrimary = DynamicColor(lightColor: x1E42A4, darkColor: xCCDAFF)
    private static let accentAltTextSecondary = DynamicColor(lightColor: x14307E, darkColor: xADC2FC)
    private static let accentAltTextTertiary = DynamicColor(lightColor: x0B2059, darkColor: x8FABF9)

    // Destructive
    private static let destructiveContentPrimary = DynamicColor(lightColor: xFFFFFF, darkColor: x000000)
    private static let destructiveContentSecondary = DynamicColor(lightColor: xFFFFFFE5, darkColor: x000000E5)
    private static let destructiveContentTertiary = DynamicColor(lightColor: xFFFFFF99, darkColor: x00000099)
    private static let destructiveGlow = DynamicColor(lightColor: xEE102533, darkColor: xEE102533)
    private static let destructivePrimary = DynamicColor(lightColor: xEE1025, darkColor: xEE1025)
    private static let destructiveSecondary = DynamicColor(lightColor: xD11527, darkColor: xD11527)
    private static let destructiveTertiary = DynamicColor(lightColor: xAA1926, darkColor: xAA1926)
    private static let destructiveTextPrimary = DynamicColor(lightColor: xEE1025, darkColor: xEE1025)
    private static let destructiveTextSecondary = DynamicColor(lightColor: xD11527, darkColor: xD11527)
    private static let destructiveTextTertiary = DynamicColor(lightColor: xAA1926, darkColor: xAA1926)

    // Surfaces
    private static let surfaceBackdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x070707)
    private static let surfaceCanvas = DynamicColor(lightColor: xFAFAFA, darkColor: x1C1C1C)
    private static let surfacePrimary = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    private static let surfaceSecondary = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)

    // Tone
    private static let toneShadePrimary = DynamicColor(lightColor: x0000000F, darkColor: x16161751)
    private static let toneTintPrimary = DynamicColor(lightColor: xFFFFFF7A, darkColor: xF9F9F91E)

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
        case .controlsDecorationQuaternary: return controlsDecorationQuaternary
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

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        switch singleUseColor {
        case .controlWidgetBackground:
            return DynamicColor(staticColor: .x818387)
        case .newTabPageItemAccessoryAddBackground:
            return DynamicColor(lightColor: surface.lightColor, darkColor: .gray85)
        case .unifiedFeedbackFieldBackground:
            return DynamicColor(lightColor: surface.lightColor, darkColor: .x1C1C1E)
        case .downloadProgressBarBackground: return DynamicColor(lightColor: .gray85, darkColor: .gray70)
        case .privacyDashboardBackground:
            return DynamicColor(lightColor: surface.lightColor, darkColor: background.darkColor)
        case .duckPlayerPillBackground:
            return DynamicColor(lightColor: surface.lightColor, darkColor: .tint(0.12))
        }
    }
}
