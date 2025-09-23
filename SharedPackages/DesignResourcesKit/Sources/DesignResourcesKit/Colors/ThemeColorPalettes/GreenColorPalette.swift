//
//  GreenColorPalette.swift
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

struct GreenColorPalette: ColorPaletteDefinition {

    // Accent Colors
    static let accentContentPrimary = DynamicColor(lightHex: 0xf5fbf4, darkHex: 0x0b1914)
    static let accentContentSecondary = DynamicColor(lightHex: 0xf5fbf4, lightOpacityHex: 0xb2, darkHex: 0x0b1914, darkOpacityHex: 0xb2)
    static let accentContentTertiary = DynamicColor(lightHex: 0xf5fbf4, lightOpacityHex: 0x7f, darkHex: 0x0b1914, darkOpacityHex: 0x7f)
    static let accentGlowPrimary = DynamicColor(lightHex: 0x388056, lightOpacityHex: 0x33, darkHex: 0x6ec7a2, darkOpacityHex: 0x33)
    static let accentGlowSecondary = DynamicColor(lightHex: 0x388056, lightOpacityHex: 0x1e, darkHex: 0x6ec7a2, darkOpacityHex: 0x1e)
    static let accentPrimary = DynamicColor(lightHex: 0x377f55, darkHex: 0x6ec7a2)
    static let accentQuaternary = DynamicColor(lightHex: 0x183826, darkHex: 0x21815a)
    static let accentSecondary = DynamicColor(lightHex: 0x2c6645, darkHex: 0x48b186)
    static let accentTertiary = DynamicColor(lightHex: 0x235136, darkHex: 0x299c6d)
    static let accentTextPrimary = DynamicColor(lightHex: 0x2c6645, darkHex: 0x85e0ba)
    static let accentTextSecondary = DynamicColor(lightHex: 0x235136, darkHex: 0x6ec7a2)
    static let accentTextTertiary = DynamicColor(lightHex: 0x193926, darkHex: 0x48b186)

    // Accent Alt Colors
    static let accentAltContentPrimary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0xccdaff)
    static let accentAltContentSecondary = DynamicColor(lightHex: 0x0b2059, darkHex: 0xe5edff)
    static let accentAltContentTertiary = DynamicColor(lightHex: 0x051133, darkHex: 0xffffff)
    static let accentAltGlowPrimary = DynamicColor(lightHex: 0x7295f6, lightOpacityHex: 0x33, darkHex: 0x8fabf9, darkOpacityHex: 0x33)
    static let accentAltGlowSecondary = DynamicColor(lightHex: 0x7295f6, lightOpacityHex: 0x1e, darkHex: 0x8fabf9, darkOpacityHex: 0x1e)
    static let accentAltPrimary = DynamicColor(lightHex: 0xccdaff, darkHex: 0x2b55ca)
    static let accentAltSecondary = DynamicColor(lightHex: 0xadc2fc, darkHex: 0x1e42a4)
    static let accentAltTertiary = DynamicColor(lightHex: 0x8fabf9, darkHex: 0x14307e)
    static let accentAltTextPrimary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0xccdaff)
    static let accentAltTextSecondary = DynamicColor(lightHex: 0x14307e, darkHex: 0xadc2fc)
    static let accentAltTextTertiary = DynamicColor(lightHex: 0x0b2059, darkHex: 0x8fabf9)

    // Container Colors
    static let containerDecorationPrimary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x16, darkHex: 0xf5fbf4, darkOpacityHex: 0x1e)
    static let containerDecorationSecondary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x0f, darkHex: 0xf5fbf4, darkOpacityHex: 0x16)
    static let containerDecorationTertiary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x0f, darkHex: 0xf5fbf4, darkOpacityHex: 0x16)
    static let containerFillPrimary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x0f, darkHex: 0xf5fbf4, darkOpacityHex: 0x16)
    static let containerFillSecondary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x07, darkHex: 0xf5fbf4, darkOpacityHex: 0x0f)
    static let containerFillTertiary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x02, darkHex: 0xf5fbf4, darkOpacityHex: 0x07)

    // Controls Colors
    static let controlsBase = DynamicColor(lightHex: 0x288a51, darkHex: 0x88dcb9)
    static let controlsDecorationPrimary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x51, darkHex: 0x88ddba, darkOpacityHex: 0x3d)
    static let controlsDecorationSecondary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x8e, darkHex: 0x88ddba, darkOpacityHex: 0xa3)
    static let controlsDecorationTertiary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0xa3, darkHex: 0x88ddba, darkOpacityHex: 0xb7)
    static let controlsDecorationQuaternary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0xb7, darkHex: 0x88ddba, darkOpacityHex: 0xcc)
    static let controlsFillPrimary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x16, darkHex: 0x88ddba, darkOpacityHex: 0x1e)
    static let controlsFillSecondary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x1e, darkHex: 0x88ddba, darkOpacityHex: 0x2d)
    static let controlsFillTertiary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x2d, darkHex: 0x88ddba, darkOpacityHex: 0x3d)

    // Decoration Colors
    static let decorationPrimary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x3d, darkHex: 0x88ddba, darkOpacityHex: 0x33)
    static let decorationSecondary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x66, darkHex: 0x88ddba, darkOpacityHex: 0x3d)
    static let decorationTertiary = DynamicColor(lightHex: 0x288a51, lightOpacityHex: 0x8e, darkHex: 0x88ddba, darkOpacityHex: 0x51)

    // Destructive Colors
    static let destructiveContentPrimary = DynamicColor(lightHex: 0xffffff, darkHex: 0x000000)
    static let destructiveContentSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0xe5, darkHex: 0x000000, darkOpacityHex: 0xe5)
    static let destructiveContentTertiary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x99, darkHex: 0x000000, darkOpacityHex: 0x99)
    static let destructiveGlow = DynamicColor(staticColorHex: 0xee1025, opacity: 0.2)
    static let destructivePrimary = DynamicColor(staticColorHex: 0xee1025)
    static let destructiveSecondary = DynamicColor(staticColorHex: 0xd11527)
    static let destructiveTertiary = DynamicColor(staticColorHex: 0xaa1926)
    static let destructiveTextPrimary = DynamicColor(staticColorHex: 0xee1025)
    static let destructiveTextSecondary = DynamicColor(staticColorHex: 0xd11527)
    static let destructiveTextTertiary = DynamicColor(staticColorHex: 0xaa1926)

    // Highlight Colors
    static let highlightPrimary = DynamicColor(lightHex: 0xf5fbf4, lightOpacityHex: 0x3d, darkHex: 0xe6f2ea, darkOpacityHex: 0x1e)

    // Icons Colors
    static let icons = DynamicColor(lightColor: Color(0x1F1F1F).opacity(0.84), darkColor: .tint(0.78))
    static let iconsPrimary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0xd6, darkHex: 0xe6f2ea, darkOpacityHex: 0xc6)
    static let iconsSecondary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x99, darkHex: 0xe6f2ea, darkOpacityHex: 0x7a)
    static let iconsTertiary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x5b, darkHex: 0xe6f2ea, darkOpacityHex: 0x3d)

    // Shadow Colors
    static let shadowPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0c, darkHex: 0x000000, darkOpacityHex: 0x28)
    static let shadowSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x14, darkHex: 0x000000, darkOpacityHex: 0x3d)
    static let shadowTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x28, darkHex: 0x000000, darkOpacityHex: 0x51)

    // Surface Colors
    static let surface = DynamicColor(lightHex: 0xF9F9F9, darkHex: 0x373737)
    static let surfaceBackdrop = DynamicColor(lightHex: 0xb5d0ad, darkHex: 0x0f241c)
    static let surfaceCanvas = DynamicColor(lightHex: 0xf8fbf7, darkHex: 0x1e3329)
    static let surfacePrimary = DynamicColor(lightHex: 0xe3eee1, darkHex: 0x203b30)
    static let surfaceSecondary = DynamicColor(lightHex: 0xecf4eb, darkHex: 0x2d4d3e)
    static let surfaceTertiary = DynamicColor(lightHex: 0xf2f8f0, darkHex: 0x39604e)

    // Text Colors
    static let textPrimary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0xf4, darkHex: 0xe6f2ea, darkOpacityHex: 0xf4)
    static let textSecondary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0xa8, darkHex: 0xe6f2ea, darkOpacityHex: 0xa8)
    static let textTertiary = DynamicColor(lightHex: 0x062504, lightOpacityHex: 0x5b, darkHex: 0xe6f2ea, darkOpacityHex: 0x5b)

    // Tone Colors
    static let toneShadePrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0x161617, darkOpacityHex: 0x51)
    static let toneTintPrimary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x7a, darkHex: 0xf9f9f9, darkOpacityHex: 0x1e)

    // MARK: - Defaults / Non Customized

    // URL Bar
    static let urlBar = FigmaColorPalette.urlBar

    // Backgrounds
    static let background = FigmaColorPalette.background
    static let backgroundTertiary = FigmaColorPalette.backgroundTertiary
    static let backgroundSheets = FigmaColorPalette.backgroundSheets
    static let backdrop = FigmaColorPalette.backdrop
    static let backgroundBlur = FigmaColorPalette.backgroundBlur

    // System
    static let lines = FigmaColorPalette.lines
    static let highlightDecoration = FigmaColorPalette.highlightPrimary

    // Various
    static let variousOutline = FigmaColorPalette.variousOutline
    static let variousIPadTabs = FigmaColorPalette.variousIPadTabs

    // Accent
    static let accent = FigmaColorPalette.accent

    // System
    static let border = FigmaColorPalette.border

    // Alert
    static let alertGreen = FigmaColorPalette.alertGreen
    static let alertYellow = FigmaColorPalette.alertYellow

    // Text
    static let textLink = FigmaColorPalette.textLink
    static let textSelectionFill = FigmaColorPalette.textSelectionFill
    static let textPlaceholder = FigmaColorPalette.textPlaceholder

    // Buttons/Primary
    static let buttonsPrimaryDefault = FigmaColorPalette.buttonsPrimaryDefault
    static let buttonsPrimaryPressed = FigmaColorPalette.buttonsPrimaryPressed
    static let buttonsPrimaryDisabled = FigmaColorPalette.buttonsPrimaryDisabled
    static let buttonsPrimaryText = FigmaColorPalette.buttonsPrimaryText
    static let buttonsPrimaryTextDisabled = FigmaColorPalette.buttonsPrimaryTextDisabled

    // Buttons/SecondaryFill
    static let buttonsSecondaryFillDefault = FigmaColorPalette.buttonsSecondaryFillDefault
    static let buttonsSecondaryFillPressed = FigmaColorPalette.buttonsSecondaryFillPressed
    static let buttonsSecondaryFillDisabled = FigmaColorPalette.buttonsSecondaryFillDisabled
    static let buttonsSecondaryFillText = FigmaColorPalette.buttonsSecondaryFillText
    static let buttonsSecondaryFillTextDisabled = FigmaColorPalette.buttonsSecondaryFillTextDisabled

    // Buttons/SecondaryWire
    static let buttonsSecondaryWireDefault = FigmaColorPalette.buttonsSecondaryWireDefault
    static let buttonsSecondaryWirePressedFill = FigmaColorPalette.buttonsSecondaryWirePressedFill
    static let buttonsSecondaryWireDisabledStroke = FigmaColorPalette.buttonsSecondaryWireDisabledStroke
    static let buttonsSecondaryWireText = FigmaColorPalette.buttonsSecondaryWireText
    static let buttonsSecondaryWireTextPressed = FigmaColorPalette.buttonsSecondaryWireTextPressed
    static let buttonsSecondaryWireTextDisabled = FigmaColorPalette.buttonsSecondaryWireTextDisabled

    // Buttons/Ghost
    static let buttonsGhostPressedFill = FigmaColorPalette.buttonsGhostPressedFill
    static let buttonsGhostText = FigmaColorPalette.buttonsGhostText
    static let buttonsGhostTextPressed = FigmaColorPalette.buttonsGhostTextPressed
    static let buttonsGhostTextDisabled = FigmaColorPalette.buttonsGhostTextDisabled

    // Buttons/Color
    static let buttonsBlack = FigmaColorPalette.buttonsBlack
    static let buttonsWhite = FigmaColorPalette.buttonsWhite

    // Buttons/DeleteGhost
    static let buttonsDeleteGhostPressedFill = FigmaColorPalette.buttonsDeleteGhostPressedFill
    static let buttonsDeleteGhostTextPressed = FigmaColorPalette.buttonsDeleteGhostTextPressed
    static let buttonsDeleteGhostText = FigmaColorPalette.buttonsDeleteGhostText
    static let buttonsDeleteGhostTextDisabled = FigmaColorPalette.buttonsDeleteGhostTextDisabled

    // MARK: - ColorPaletteDefinition Implementation

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        FigmaColorPalette.dynamicColor(for: singleUseColor)
    }
}
