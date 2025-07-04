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

struct DefaultColorPalette: ColorPaletteDefinition {

    // Backgrounds
    private static let background = DynamicColor(lightColor: .gray10, darkColor: .gray90)
    private static let surface = DynamicColor(lightColor: .white, darkColor: .x2F2F2F)
    private static let backgroundSheets = DynamicColor(lightColor: .white, darkColor: .gray90)
    private static let panel = DynamicColor(lightColor: .gray0, darkColor: .gray85)
    private static let container = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.12))
    private static let urlBar = DynamicColor(lightColor: .xEAEAEA, darkColor: .gray80)

    // Various
    private static let variousIPadTabs = DynamicColor(lightColor: .gray20, darkColor: .black)
    private static let variousOutline = DynamicColor(lightColor: .shade(0.24), darkColor: .tint(0.24))
    private static let backdrop = DynamicColor(lightColor: .x1E1E1E.opacity(0.75), darkColor: .gray15.opacity(0.8))
    private static let backgroundBlur = DynamicColor(staticColor: .gray90.opacity(0.7))

    // Text
    private static let textPrimary = DynamicColor(lightColor: .shade(0.84), darkColor: .tint(0.84))
    private static let textSecondary = DynamicColor(lightColor: .shade(0.6), darkColor: .tint(0.6))
    private static let textLink = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let textSelectionFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let textPlaceholder = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Brand
    private static let accent = DynamicColor(lightColor: .blue50, darkColor: .blue30)

    // System
    private static let lines = DynamicColor(lightColor: .shade(0.09), darkColor: .tint(0.09))
    private static let border = DynamicColor(lightColor: .gray30, darkColor: .gray40)

    // Alert
    private static let alertGreen = DynamicColor(lightColor: .alertGreen, darkColor: .alertGreen)
    private static let alertYellow = DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow)

    // Icons
    private static let icons = DynamicColor(lightColor: .shade(0.84), darkColor: .tint(0.84))
    private static let iconsSecondary = DynamicColor(lightColor: .shade(0.6), darkColor: .tint(0.6))

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
        case .accent: return accent
        case .alertGreen: return alertGreen
        case .alertYellow: return alertYellow
        case .background: return background
        case .backgroundTertiary:
            assertionFailure("This color should be used in experimental palette only.")
            return background
        case .backgroundSheets: return backgroundSheets
        case .container: return container
        case .icons: return icons
        case .iconsSecondary: return iconsSecondary
        case .lines: return lines
        case .border: return border
        case .panel: return panel
        case .surface: return surface
        case .textLink: return textLink
        case .textPrimary: return textPrimary
        case .textPlaceholder: return textPlaceholder
        case .textSecondary: return textSecondary
        case .textSelectionFill: return textSelectionFill
        case .backdrop: return backdrop
        case .backgroundBlur: return backgroundBlur

        case .shadowPrimary, .shadowSecondary, .shadowTertiary:
            assertionFailure("This color should be used in experimental palette only.")
            return lines
        case .controlsFillPrimary, .controlsFillSecondary, .controlsFillTertiary:
            assertionFailure("This color should be used in experimental palette only.")
            return surface

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
        case .variousIPadTabs: return variousIPadTabs
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
