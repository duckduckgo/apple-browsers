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
    public static let urlBar = DynamicColor(lightColor: .white, darkColor: x474747)

    // Surfaces
    public static let surface = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    public static let surfaceTertiary = DynamicColor(lightColor: .white, darkColor: .x474747)

    // Backgrounds
    public static let backdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x080808)
    public static let background = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    public static let backgroundTertiary = DynamicColor(lightColor: .white, darkColor: x474747)
    public static let backgroundSheets = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    public static let backgroundBlur = DynamicColor(staticColor: .gray90.opacity(0.7))

    // Shadow
    public static let shadowPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.04), darkColor: .shade(0.16))
    public static let shadowSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.08), darkColor: .shade(0.24))
    public static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.16), darkColor: .shade(0.32))

    // Controls
    public static let controlsFillPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))
    public static let controlsFillSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.12), darkColor: xF9F9F9.opacity(0.18))
    public static let controlsFillTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.18), darkColor: xF9F9F9.opacity(0.24))

    // Icons
    public static let icons = DynamicColor(lightColor: x1F1F1F.opacity(0.84), darkColor: .tint(0.78))
    public static let iconsPrimary = DynamicColor(lightColor: x000000D6, darkColor: xFFFFFFC6)
    public static let iconsSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: .tint(0.48))
    public static let iconsTertiary = DynamicColor(lightColor: x000000.opacity(0.36), darkColor: xFFFFFF.opacity(0.24))

    // Text
    public static let textPrimary = DynamicColor(lightColor: x1F1F1F, darkColor: .tint(0.9))
    public static let textSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.72), darkColor: .tint(0.6))
    public static let textTertiary = DynamicColor(lightColor: x0000005B, darkColor: xFFFFFF5B)
    public static let textPlaceholder = DynamicColor(lightColor: x1F1F1F.opacity(0.4), darkColor: .tint(0.4))

    // System
    public static let lines = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

    // Decorations
    public static let decorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.36))
    public static let decorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.48), darkColor: xF9F9F9.opacity(0.64))
    public static let decorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.60), darkColor: xF9F9F9.opacity(0.74))

    // Highlight
    public static let highlightDecoration = DynamicColor(lightColor: .tint(0.24), darkColor: xF9F9F9.opacity(0.12))
    public static let highlightPrimary = DynamicColor(lightColor: xFFFFFF3D, darkColor: xF9F9F91E)

    // Accents
    public static let accentContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)

    // Various
    public static let variousIPadTabs = DynamicColor(lightColor: .gray20, darkColor: .black)
    public static let variousOutline = DynamicColor(lightColor: .shade(0.24), darkColor: .tint(0.24))

    // Text
    public static let textLink = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    public static let textSelectionFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))

    // Brand
    public static let accent = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    public static let accentGlowSecondary = DynamicColor(lightColor: x3969EF.opacity(0.12), darkColor: x7295F6.opacity(0.12))

    // System
    public static let border = DynamicColor(lightColor: .gray30, darkColor: .gray40)

    // Alert
    public static let alertGreen = DynamicColor(lightColor: .alertGreen, darkColor: .alertGreen)
    public static let alertYellow = DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow)

    // Buttons/Primary
    public static let buttonsPrimaryDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    public static let buttonsPrimaryPressed = DynamicColor(lightColor: .blue70, darkColor: .blue50)
    public static let buttonsPrimaryDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    public static let buttonsPrimaryText = DynamicColor(lightColor: .white, darkColor: .shade(0.84))
    public static let buttonsPrimaryTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryFill
    public static let buttonsSecondaryFillDefault = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    public static let buttonsSecondaryFillPressed = DynamicColor(lightColor: .shade(0.18), darkColor: .tint(0.3))
    public static let buttonsSecondaryFillDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    public static let buttonsSecondaryFillText = DynamicColor(lightColor: .shade(0.84), darkColor: .white)
    public static let buttonsSecondaryFillTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryWire
    public static let buttonsSecondaryWireDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    public static let buttonsSecondaryWirePressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    public static let buttonsSecondaryWireDisabledStroke = DynamicColor(lightColor: .shade(0.12), darkColor: .tint(0.24))
    public static let buttonsSecondaryWireText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    public static let buttonsSecondaryWireTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    public static let buttonsSecondaryWireTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Ghost
    public static let buttonsGhostPressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    public static let buttonsGhostText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    public static let buttonsGhostTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    public static let buttonsGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Color
    public static let buttonsBlack = DynamicColor(lightColor: .black, darkColor: .white)
    public static let buttonsWhite = DynamicColor(lightColor: .white, darkColor: .black)

    // Buttons/DeleteGhost
    public static let buttonsDeleteGhostPressedFill = DynamicColor(lightColor: .alertRed50.opacity(0.12), darkColor: .alertRed20.opacity(0.18))
    public static let buttonsDeleteGhostTextPressed = DynamicColor(lightColor: .alertRed70, darkColor: .alertRed10)
    public static let buttonsDeleteGhostText = DynamicColor(lightColor: .alertRedOnLight, darkColor: .alertRedOnDark)
    public static let buttonsDeleteGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Controls
    public static let controlsDecorationPrimary = DynamicColor(lightColor: x1F1F1F4C, darkColor: xF9F9F95B)
    public static let controlsDecorationSecondary = DynamicColor(lightColor: x1F1F1F7A, darkColor: xF9F9F9A3)
    public static let controlsDecorationTertiary = DynamicColor(lightColor: x1F1F1F99, darkColor: xF9F9F9B7)

    // Accent
    public static let accentContentSecondary = DynamicColor(lightColor: xCCDAFF, darkColor: x03091A)
    public static let accentContentTertiary = DynamicColor(lightColor: xADC2FC, darkColor: x000000)
    public static let accentGlowPrimary = DynamicColor(lightColor: x3969EF33, darkColor: x7295F633)
    public static let accentPrimary = DynamicColor(lightColor: x3969EF, darkColor: x7295F6)
    public static let accentSecondary = DynamicColor(lightColor: x2B55CA, darkColor: x557FF3)
    public static let accentTertiary = DynamicColor(lightColor: x1E42A4, darkColor: x3969EF)
    public static let accentTextPrimary = DynamicColor(lightColor: x3969EF, darkColor: xADC2FC)
    public static let accentTextSecondary = DynamicColor(lightColor: x2B55CA, darkColor: x8FABF9)
    public static let accentTextTertiary = DynamicColor(lightColor: x1E42A4, darkColor: x7295F6)

    // Accent Alt
    public static let accentAltContentPrimary = DynamicColor(lightColor: x1E42A4, darkColor: xCCDAFF)
    public static let accentAltContentSecondary = DynamicColor(lightColor: x0B2059, darkColor: xE5EDFF)
    public static let accentAltContentTertiary = DynamicColor(lightColor: x051133, darkColor: xFFFFFF)
    public static let accentAltGlowPrimary = DynamicColor(lightColor: x7295F633, darkColor: x8FABF933)
    public static let accentAltPrimary = DynamicColor(lightColor: xCCDAFF, darkColor: x2B55CA)
    public static let accentAltSecondary = DynamicColor(lightColor: xADC2FC, darkColor: x1E42A4)
    public static let accentAltTertiary = DynamicColor(lightColor: x8FABF9, darkColor: x14307E)
    public static let accentAltTextPrimary = DynamicColor(lightColor: x1E42A4, darkColor: xCCDAFF)
    public static let accentAltTextSecondary = DynamicColor(lightColor: x14307E, darkColor: xADC2FC)
    public static let accentAltTextTertiary = DynamicColor(lightColor: x0B2059, darkColor: x8FABF9)

    // Destructive
    public static let destructiveContentPrimary = DynamicColor(lightColor: xFFFFFF, darkColor: x000000)
    public static let destructiveContentSecondary = DynamicColor(lightColor: xFFFFFFE5, darkColor: x000000E5)
    public static let destructiveContentTertiary = DynamicColor(lightColor: xFFFFFF99, darkColor: x00000099)
    public static let destructiveGlow = DynamicColor(lightColor: xEE102533, darkColor: xEE102533)
    public static let destructivePrimary = DynamicColor(lightColor: xEE1025, darkColor: xEE1025)
    public static let destructiveSecondary = DynamicColor(lightColor: xD11527, darkColor: xD11527)
    public static let destructiveTertiary = DynamicColor(lightColor: xAA1926, darkColor: xAA1926)
    public static let destructiveTextPrimary = DynamicColor(lightColor: xEE1025, darkColor: xEE1025)
    public static let destructiveTextSecondary = DynamicColor(lightColor: xD11527, darkColor: xD11527)
    public static let destructiveTextTertiary = DynamicColor(lightColor: xAA1926, darkColor: xAA1926)

    // Surfaces
    public static let surfaceBackdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x070707)
    public static let surfaceCanvas = DynamicColor(lightColor: xFAFAFA, darkColor: x1C1C1C)
    public static let surfacePrimary = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    public static let surfaceSecondary = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)

    // Tone
    public static let toneShadePrimary = DynamicColor(lightColor: x0000000F, darkColor: x16161751)
    public static let toneTintPrimary = DynamicColor(lightColor: xFFFFFF7A, darkColor: xF9F9F91E)

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
