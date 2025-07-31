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

    // New dark mode colors
    private static let x080808 = Color(0x080808)
    private static let x282828 = Color(0x282828)
    private static let x373737 = Color(0x373737)
    private static let x474747 = Color(0x474747)

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
    private static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.16), darkColor: .shade(0.48))

    // Controls
    private static let controlsFillPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))
    private static let controlsFillSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.12), darkColor: xF9F9F9.opacity(0.18))
    private static let controlsFillTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.18), darkColor: xF9F9F9.opacity(0.24))

    // Icons
    private static let icons = DynamicColor(lightColor: x1F1F1F.opacity(0.84), darkColor: .tint(0.78))
    private static let iconsSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: .tint(0.48))

    // Text
    private static let textPrimary = DynamicColor(lightColor: x1F1F1F, darkColor: .tint(0.9))
    private static let textSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.72), darkColor: .tint(0.6))
    private static let textPlaceholder = DynamicColor(lightColor: x1F1F1F.opacity(0.4), darkColor: .tint(0.4))

    // System
    private static let lines = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

    // Decorations
    private static let decorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.36))
    private static let decorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.48), darkColor: xF9F9F9.opacity(0.64))
    private static let decorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.60), darkColor: xF9F9F9.opacity(0.74))

    // Highlight
    private static let highlightDecoration = DynamicColor(lightColor: .tint(0.24), darkColor: xF9F9F9.opacity(0.12))

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
        case .iconsSecondary: return iconsSecondary
        case .textPrimary: return textPrimary
        case .lines: return lines
        case .shadowPrimary: return shadowPrimary
        case .shadowSecondary: return shadowSecondary
        case .shadowTertiary: return shadowTertiary
        case .surfaceTertiary: return surfaceTertiary
        case .controlsFillPrimary: return controlsFillPrimary
        case .controlsFillSecondary: return controlsFillSecondary
        case .controlsFillTertiary: return controlsFillTertiary
        case .decorationPrimary: return decorationPrimary
        case .decorationSecondary: return decorationSecondary
        case .decorationTertiary: return decorationTertiary
        case .highlightDecoration: return highlightDecoration
        case .accentContentPrimary: return accentContentPrimary

        case .accent: return accent
        case .alertGreen: return alertGreen
        case .alertYellow: return alertYellow
        case .border: return border
        case .textLink: return textLink
        case .textPlaceholder: return textPlaceholder
        case .textSecondary: return textSecondary
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
