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
    static let x1F1F1F = Color(0x1F1F1F)
    static let x141415 = Color(0x141415)
    static let x181818 = Color(0x181818)
    static let x27282A = Color(0x27282A)
    static let x333538 = Color(0x333538)
    static let x404145 = Color(0x404145)
    static let xE0E0E0 = Color(0xE0E0E0)
    static let xF2F2F2 = Color(0xF2F2F2)
    static let xF9F9F9 = Color(0xF9F9F9)
    static let x000000 = Color(0x000000)
    static let xFFFFFF = Color(0xFFFFFF)
    static let x3969EF = Color(0x3969EF)

    // New dark mode colors
    static let x080808 = Color(0x080808)
    static let x282828 = Color(0x282828)
    static let x373737 = Color(0x373737)
    static let x474747 = Color(0x474747)
    static let x7295F6 = Color(0x7295F6)

    // Additional hex colors for new semantic colors
    static let x070707 = Color(0x070707)
    static let x1C1C1C = Color(0x1C1C1C)
    static let x161617 = Color(0x161617)
    static let x03091A = Color(0x03091A)
    static let xE5EDFF = Color(0xE5EDFF)
    static let xD11527 = Color(0xD11527)
    static let xAA1926 = Color(0xAA1926)

    // URL bar
    static let urlBar = DynamicColor(lightColor: .white, darkColor: x474747)

    // Surfaces
    static let surface = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    static let surfaceTertiary = DynamicColor(lightColor: .white, darkColor: .x474747)

    // Backgrounds
    static let backdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x080808)
    static let background = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    static let backgroundTertiary = DynamicColor(lightColor: .white, darkColor: x474747)
    static let backgroundSheets = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    static let backgroundBlur = DynamicColor(staticColor: .gray90.opacity(0.7))

    // Shadow
    static let shadowPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.04), darkColor: .shade(0.16))
    static let shadowSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.08), darkColor: .shade(0.24))
    static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.16), darkColor: .shade(0.32))

    // Controls
    static let controlsFillPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))
    static let controlsFillSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.12), darkColor: xF9F9F9.opacity(0.18))
    static let controlsFillTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.18), darkColor: xF9F9F9.opacity(0.24))

    // Icons
    static let icons = DynamicColor(lightColor: x1F1F1F.opacity(0.84), darkColor: .tint(0.78))
    static let iconsPrimary = DynamicColor(lightColor: x000000.opacity(0.8), darkColor: xFFFFFF.opacity(0.78))
    static let iconsSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: .tint(0.48))
    static let iconsTertiary = DynamicColor(lightColor: x000000.opacity(0.36), darkColor: xFFFFFF.opacity(0.24))

    // Text
    static let textPrimary = DynamicColor(lightColor: x1F1F1F, darkColor: .tint(0.9))
    static let textSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.72), darkColor: .tint(0.6))
    static let textTertiary = DynamicColor(lightColor: x000000.opacity(0.4), darkColor: xFFFFFF.opacity(0.4))
    static let textPlaceholder = DynamicColor(lightColor: x1F1F1F.opacity(0.4), darkColor: .tint(0.4))

    // System
    static let lines = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

    // Decorations
    static let decorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.36))
    static let decorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.48), darkColor: xF9F9F9.opacity(0.64))
    static let decorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.60), darkColor: xF9F9F9.opacity(0.74))

    // Highlight
    static let highlightDecoration = DynamicColor(lightColor: .tint(0.24), darkColor: xF9F9F9.opacity(0.12))
    static let highlightPrimary = DynamicColor(lightColor: xFFFFFF.opacity(0.24), darkColor: xF9F9F9.opacity(0.12))

    // Accents
    static let accentContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)

    // Various
    static let variousIPadTabs = DynamicColor(lightColor: .gray20, darkColor: .black)
    static let variousOutline = DynamicColor(lightColor: .shade(0.24), darkColor: .tint(0.24))

    // Text
    static let textLink = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    static let textSelectionFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))

    // Brand
    static let accent = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    static let accentGlowSecondary = DynamicColor(lightColor: x3969EF.opacity(0.12), darkColor: x7295F6.opacity(0.12))

    // System
    static let border = DynamicColor(lightColor: .gray30, darkColor: .gray40)

    // Alert
    static let alertGreen = DynamicColor(lightColor: .alertGreen, darkColor: .alertGreen)
    static let alertYellow = DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow)

    // Buttons/Primary
    static let buttonsPrimaryDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    static let buttonsPrimaryPressed = DynamicColor(lightColor: .blue70, darkColor: .blue50)
    static let buttonsPrimaryDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    static let buttonsPrimaryText = DynamicColor(lightColor: .white, darkColor: .shade(0.84))
    static let buttonsPrimaryTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryFill
    static let buttonsSecondaryFillDefault = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    static let buttonsSecondaryFillPressed = DynamicColor(lightColor: .shade(0.18), darkColor: .tint(0.3))
    static let buttonsSecondaryFillDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    static let buttonsSecondaryFillText = DynamicColor(lightColor: .shade(0.84), darkColor: .white)
    static let buttonsSecondaryFillTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryWire
    static let buttonsSecondaryWireDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    static let buttonsSecondaryWirePressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    static let buttonsSecondaryWireDisabledStroke = DynamicColor(lightColor: .shade(0.12), darkColor: .tint(0.24))
    static let buttonsSecondaryWireText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    static let buttonsSecondaryWireTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    static let buttonsSecondaryWireTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Ghost
    static let buttonsGhostPressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    static let buttonsGhostText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    static let buttonsGhostTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    static let buttonsGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Color
    static let buttonsBlack = DynamicColor(lightColor: .black, darkColor: .white)
    static let buttonsWhite = DynamicColor(lightColor: .white, darkColor: .black)

    // Buttons/DeleteGhost
    static let buttonsDeleteGhostPressedFill = DynamicColor(lightColor: .alertRed50.opacity(0.12), darkColor: .alertRed20.opacity(0.18))
    static let buttonsDeleteGhostTextPressed = DynamicColor(lightColor: .alertRed70, darkColor: .alertRed10)
    static let buttonsDeleteGhostText = DynamicColor(lightColor: .alertRedOnLight, darkColor: .alertRedOnDark)
    static let buttonsDeleteGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Controls
    static let controlsDecorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.4))
    static let controlsDecorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.5), darkColor: xF9F9F9.opacity(0.6))
    static let controlsDecorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: xF9F9F9.opacity(0.7))
    static let controlsDecorationQuaternary = DynamicColor(lightColor: x1F1F1F.opacity(0.7), darkColor: xF9F9F9.opacity(0.8))

    // Accent
    static let accentContentSecondary = DynamicColor(lightColor: .blue0, darkColor: x03091A)
    static let accentContentTertiary = DynamicColor(lightColor: .blue10, darkColor: x000000)
    static let accentGlowPrimary = DynamicColor(lightColor: x3969EF.opacity(0.2), darkColor: x7295F6.opacity(0.2))
    static let accentPrimary = DynamicColor(lightColor: x3969EF, darkColor: x7295F6)
    static let accentSecondary = DynamicColor(lightColor: .blue60, darkColor: .blue40)
    static let accentTertiary = DynamicColor(lightColor: .blue70, darkColor: x3969EF)
    static let accentTextPrimary = DynamicColor(lightColor: x3969EF, darkColor: .blue10)
    static let accentTextSecondary = DynamicColor(lightColor: .blue60, darkColor: .blue20)
    static let accentTextTertiary = DynamicColor(lightColor: .blue70, darkColor: x7295F6)

    // Accent Alt
    static let accentAltContentPrimary = DynamicColor(lightColor: .blue70, darkColor: .blue0)
    static let accentAltContentSecondary = DynamicColor(lightColor: .blue90, darkColor: xE5EDFF)
    static let accentAltContentTertiary = DynamicColor(lightColor: .blue100, darkColor: xFFFFFF)
    static let accentAltGlowPrimary = DynamicColor(lightColor: x7295F6.opacity(0.2), darkColor: .blue20.opacity(0.2))
    static let accentAltPrimary = DynamicColor(lightColor: .blue0, darkColor: .blue60)
    static let accentAltSecondary = DynamicColor(lightColor: .blue10, darkColor: .blue70)
    static let accentAltTertiary = DynamicColor(lightColor: .blue20, darkColor: .blue80)
    static let accentAltTextPrimary = DynamicColor(lightColor: .blue70, darkColor: .blue0)
    static let accentAltTextSecondary = DynamicColor(lightColor: .blue80, darkColor: .blue10)
    static let accentAltTextTertiary = DynamicColor(lightColor: .blue90, darkColor: .blue20)

    // Destructive
    static let destructiveContentPrimary = DynamicColor(lightColor: xFFFFFF, darkColor: x000000)
    static let destructiveContentSecondary = DynamicColor(lightColor: xFFFFFF.opacity(0.9), darkColor: x000000.opacity(0.9))
    static let destructiveContentTertiary = DynamicColor(lightColor: xFFFFFF.opacity(0.6), darkColor: x000000.opacity(0.6))
    static let destructiveGlow = DynamicColor(lightColor: .alertRed.opacity(0.2), darkColor: .alertRed.opacity(0.2))
    static let destructivePrimary = DynamicColor(lightColor: .alertRed, darkColor: .alertRed)
    static let destructiveSecondary = DynamicColor(lightColor: xD11527, darkColor: xD11527)
    static let destructiveTertiary = DynamicColor(lightColor: xAA1926, darkColor: xAA1926)
    static let destructiveTextPrimary = DynamicColor(lightColor: .alertRed, darkColor: .alertRed)
    static let destructiveTextSecondary = DynamicColor(lightColor: xD11527, darkColor: xD11527)
    static let destructiveTextTertiary = DynamicColor(lightColor: xAA1926, darkColor: xAA1926)

    // Surfaces
    static let surfaceBackdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x070707)
    static let surfaceCanvas = DynamicColor(lightColor: .gray0, darkColor: x1C1C1C)
    static let surfacePrimary = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    static let surfaceSecondary = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)

    // Tone
    static let toneShadePrimary = DynamicColor(lightColor: x000000.opacity(0.1), darkColor: x161617.opacity(0.32))
    static let toneTintPrimary = DynamicColor(lightColor: xFFFFFF.opacity(0.5), darkColor: xF9F9F9.opacity(0.12))

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
