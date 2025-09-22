//
//  FigmaColorPalette.swift
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

/// Color palette based on Figma design specifications converted from DefaultThemeColors
struct FigmaColorPalette: ColorPaletteDefinition {

    // MARK: - Hex Color Constants

    private static let x000000 = Color(0x000000)
    private static let x00000002 = Color(0x00000002)
    private static let x00000007 = Color(0x00000007)
    private static let x0000000c = Color(0x0000000c)
    private static let x0000000f = Color(0x0000000f)
    private static let x00000014 = Color(0x00000014)
    private static let x00000016 = Color(0x00000016)
    private static let x00000028 = Color(0x00000028)
    private static let x0000003d = Color(0x0000003d)
    private static let x00000051 = Color(0x00000051)
    private static let x0000005b = Color(0x0000005b)
    private static let x00000099 = Color(0x00000099)
    private static let x000000a8 = Color(0x000000a8)
    private static let x000000d6 = Color(0x000000d6)
    private static let x000000e5 = Color(0x000000e5)
    private static let x000000f4 = Color(0x000000f4)
    private static let x0000008e = Color(0x0000008e)
    private static let x03091a = Color(0x03091a)
    private static let x051133 = Color(0x051133)
    private static let x070707 = Color(0x070707)
    private static let x080808 = Color(0x080808)
    private static let x0b2059 = Color(0x0b2059)
    private static let x14307e = Color(0x14307e)
    private static let x16161751 = Color(0x16161751)
    private static let x1c1c1c = Color(0x1c1c1c)
    private static let x1e42a4 = Color(0x1e42a4)
    private static let x1f1f1f = Color(0x1f1f1f)
    private static let x1f1f1f16 = Color(0x1f1f1f16)
    private static let x1f1f1f1e = Color(0x1f1f1f1e)
    private static let x1f1f1f2d = Color(0x1f1f1f2d)
    private static let x1f1f1f4c = Color(0x1f1f1f4c)
    private static let x1f1f1f7a = Color(0x1f1f1f7a)
    private static let x1f1f1f99 = Color(0x1f1f1f99)
    private static let x1f1f1fb7 = Color(0x1f1f1fb7)
    private static let x282828 = Color(0x282828)
    private static let x2b55ca = Color(0x2b55ca)
    private static let x373737 = Color(0x373737)
    private static let x3969ef = Color(0x3969ef)
    private static let x3969ef1e = Color(0x3969ef1e)
    private static let x3969ef33 = Color(0x3969ef33)
    private static let x474747 = Color(0x474747)
    private static let x557ff3 = Color(0x557ff3)
    private static let x7295f6 = Color(0x7295f6)
    private static let x7295f61e = Color(0x7295f61e)
    private static let x7295f633 = Color(0x7295f633)
    private static let x8fabf9 = Color(0x8fabf9)
    private static let x8fabf91e = Color(0x8fabf91e)
    private static let x8fabf933 = Color(0x8fabf933)
    private static let xaa1926 = Color(0xaa1926)
    private static let xadc2fc = Color(0xadc2fc)
    private static let xccdaff = Color(0xccdaff)
    private static let xd11527 = Color(0xd11527)
    private static let xe0e0e0 = Color(0xe0e0e0)
    private static let xe5edff = Color(0xe5edff)
    private static let xee1025 = Color(0xee1025)
    private static let xee102533 = Color(0xee102533)
    private static let xf2f2f2 = Color(0xf2f2f2)
    private static let xf8f8f8 = Color(0xf8f8f8)
    private static let xf9f9f9 = Color(0xf9f9f9)
    private static let xf9f9f91e = Color(0xf9f9f91e)
    private static let xf9f9f92d = Color(0xf9f9f92d)
    private static let xf9f9f93d = Color(0xf9f9f93d)
    private static let xf9f9f95b = Color(0xf9f9f95b)
    private static let xf9f9f9a3 = Color(0xf9f9f9a3)
    private static let xf9f9f9b7 = Color(0xf9f9f9b7)
    private static let xf9f9f9cc = Color(0xf9f9f9cc)
    private static let xfafafa = Color(0xfafafa)
    private static let xffffff = Color(0xffffff)
    private static let xffffff07 = Color(0xffffff07)
    private static let xffffff0f = Color(0xffffff0f)
    private static let xffffff16 = Color(0xffffff16)
    private static let xffffff1e = Color(0xffffff1e)
    private static let xffffff2d = Color(0xffffff2d)
    private static let xffffff33 = Color(0xffffff33)
    private static let xffffff3d = Color(0xffffff3d)
    private static let xffffff5b = Color(0xffffff5b)
    private static let xffffff7a = Color(0xffffff7a)
    private static let xffffff8e = Color(0xffffff8e)
    private static let xffffff99 = Color(0xffffff99)
    private static let xffffffa8 = Color(0xffffffa8)
    private static let xffffffc6 = Color(0xffffffc6)
    private static let xffffffe5 = Color(0xffffffe5)
    private static let xfffffff4 = Color(0xfffffff4)

    // MARK: - Private Color Definitions

    // Accent Alt Colors
    private static let accentAltContentPrimary = DynamicColor(lightColor: x1e42a4, darkColor: xccdaff)
    private static let accentAltContentSecondary = DynamicColor(lightColor: x0b2059, darkColor: xe5edff)
    private static let accentAltContentTertiary = DynamicColor(lightColor: x051133, darkColor: xffffff)
    private static let accentAltGlowPrimary = DynamicColor(lightColor: x7295f633, darkColor: x8fabf933)
    private static let accentAltGlowSecondary = DynamicColor(lightColor: x7295f61e, darkColor: x8fabf91e)
    private static let accentAltPrimary = DynamicColor(lightColor: xccdaff, darkColor: x2b55ca)
    private static let accentAltSecondary = DynamicColor(lightColor: xadc2fc, darkColor: x1e42a4)
    private static let accentAltTertiary = DynamicColor(lightColor: x8fabf9, darkColor: x14307e)
    private static let accentAltTextPrimary = DynamicColor(lightColor: x1e42a4, darkColor: xccdaff)
    private static let accentAltTextSecondary = DynamicColor(lightColor: x14307e, darkColor: xadc2fc)
    private static let accentAltTextTertiary = DynamicColor(lightColor: x0b2059, darkColor: x8fabf9)

    // Accent Colors
    private static let accentContentPrimary = DynamicColor(lightColor: xffffff, darkColor: x051133)
    private static let accentContentSecondary = DynamicColor(lightColor: xccdaff, darkColor: x03091a)
    private static let accentContentTertiary = DynamicColor(lightColor: xadc2fc, darkColor: x000000)
    private static let accentGlowPrimary = DynamicColor(lightColor: x3969ef33, darkColor: x7295f633)
    private static let accentGlowSecondary = DynamicColor(lightColor: x3969ef1e, darkColor: x7295f61e)
    private static let accentPrimary = DynamicColor(lightColor: x3969ef, darkColor: x7295f6)
    private static let accentQuarternary = DynamicColor(lightColor: x14307e, darkColor: x2b55ca)
    private static let accentSecondary = DynamicColor(lightColor: x2b55ca, darkColor: x557ff3)
    private static let accentTertiary = DynamicColor(lightColor: x1e42a4, darkColor: x3969ef)
    private static let accentTextPrimary = DynamicColor(lightColor: x3969ef, darkColor: xadc2fc)
    private static let accentTextSecondary = DynamicColor(lightColor: x2b55ca, darkColor: x8fabf9)
    private static let accentTextTertiary = DynamicColor(lightColor: x1e42a4, darkColor: x7295f6)

    // Container Colors
    private static let containerDecorationPrimary = DynamicColor(lightColor: x00000016, darkColor: xffffff1e)
    private static let containerDecorationSecondary = DynamicColor(lightColor: x0000000f, darkColor: xffffff16)
    private static let containerDecorationTertiary = DynamicColor(lightColor: x0000000f, darkColor: xffffff16)
    private static let containerFillPrimary = DynamicColor(lightColor: x0000000f, darkColor: xffffff16)
    private static let containerFillSecondary = DynamicColor(lightColor: x00000007, darkColor: xffffff0f)
    private static let containerFillTertiary = DynamicColor(lightColor: x00000002, darkColor: xffffff07)

    // Controls Colors
    private static let controlsBase = DynamicColor(lightColor: x1f1f1f, darkColor: xf8f8f8)
    private static let controlsDecorationPrimary = DynamicColor(lightColor: x1f1f1f4c, darkColor: xf9f9f95b)
    private static let controlsDecorationQuarternary = DynamicColor(lightColor: x1f1f1fb7, darkColor: xf9f9f9cc)
    private static let controlsDecorationSecondary = DynamicColor(lightColor: x1f1f1f7a, darkColor: xf9f9f9a3)
    private static let controlsDecorationTertiary = DynamicColor(lightColor: x1f1f1f99, darkColor: xf9f9f9b7)
    private static let controlsFillPrimary = DynamicColor(lightColor: x1f1f1f16, darkColor: xf9f9f91e)
    private static let controlsFillSecondary = DynamicColor(lightColor: x1f1f1f1e, darkColor: xf9f9f92d)
    private static let controlsFillTertiary = DynamicColor(lightColor: x1f1f1f2d, darkColor: xf9f9f93d)
    private static let controlsRaisedBackdrop = DynamicColor(lightColor: x00000016, darkColor: xffffff1e)
    private static let controlsRaisedFillPrimary = DynamicColor(lightColor: xffffff, darkColor: xffffff2d)

    // Decoration Colors
    private static let decorationPrimary = DynamicColor(lightColor: x0000008e, darkColor: xffffff8e)
    private static let decorationQuaternary = DynamicColor(lightColor: x00000007, darkColor: xffffff0f)
    private static let decorationSecondary = DynamicColor(lightColor: x0000003d, darkColor: xffffff33)
    private static let decorationTertiary = DynamicColor(lightColor: x00000016, darkColor: xffffff1e)

    // Destructive Colors
    private static let destructiveContentPrimary = DynamicColor(lightColor: xffffff, darkColor: x000000)
    private static let destructiveContentSecondary = DynamicColor(lightColor: xffffffe5, darkColor: x000000e5)
    private static let destructiveContentTertiary = DynamicColor(lightColor: xffffff99, darkColor: x00000099)
    private static let destructiveGlow = DynamicColor(lightColor: xee102533, darkColor: xee102533)
    private static let destructivePrimary = DynamicColor(lightColor: xee1025, darkColor: xee1025)
    private static let destructiveSecondary = DynamicColor(lightColor: xd11527, darkColor: xd11527)
    private static let destructiveTertiary = DynamicColor(lightColor: xaa1926, darkColor: xaa1926)
    private static let destructiveTextPrimary = DynamicColor(lightColor: xee1025, darkColor: xee1025)
    private static let destructiveTextSecondary = DynamicColor(lightColor: xd11527, darkColor: xd11527)
    private static let destructiveTextTertiary = DynamicColor(lightColor: xaa1926, darkColor: xaa1926)

    // Highlight Colors
    private static let highlightPrimary = DynamicColor(lightColor: xffffff3d, darkColor: xf9f9f91e)

    // Icons Colors
    private static let iconsPrimary = DynamicColor(lightColor: x000000d6, darkColor: xffffffc6)
    private static let iconsSecondary = DynamicColor(lightColor: x00000099, darkColor: xffffff7a)
    private static let iconsTertiary = DynamicColor(lightColor: x0000005b, darkColor: xffffff3d)

    // Shadow Colors
    private static let shadowPrimary = DynamicColor(lightColor: x0000000c, darkColor: x00000028)
    private static let shadowSecondary = DynamicColor(lightColor: x00000014, darkColor: x0000003d)
    private static let shadowTertiary = DynamicColor(lightColor: x00000028, darkColor: x00000051)

    // Surface Colors
    private static let surfaceBackdrop = DynamicColor(lightColor: xe0e0e0, darkColor: x070707)
    private static let surfaceCanvas = DynamicColor(lightColor: xfafafa, darkColor: x1c1c1c)
    private static let surfacePrimary = DynamicColor(lightColor: xf2f2f2, darkColor: x282828)
    private static let surfaceSecondary = DynamicColor(lightColor: xf9f9f9, darkColor: x373737)
    private static let surfaceTertiary = DynamicColor(lightColor: xffffff, darkColor: x474747)

    // Text Colors
    private static let textPrimary = DynamicColor(lightColor: x000000f4, darkColor: xfffffff4)
    private static let textSecondary = DynamicColor(lightColor: x000000a8, darkColor: xffffffa8)
    private static let textTertiary = DynamicColor(lightColor: x0000005b, darkColor: xffffff5b)

    // Tone Colors
    private static let toneShadePrimary = DynamicColor(lightColor: x0000000f, darkColor: x16161751)
    private static let toneTintPrimary = DynamicColor(lightColor: xffffff7a, darkColor: xf9f9f91e)

    // MARK: - Missing Colors from DefaultColorPalette (added for completeness)

    // URL Bar - from DefaultColorPalette
    private static let urlBar = DynamicColor(lightColor: .white, darkColor: x474747)

    // Backgrounds - from DefaultColorPalette
    private static let background = DynamicColor(lightColor: xf2f2f2, darkColor: x282828)
    private static let backgroundTertiary = DynamicColor(lightColor: .white, darkColor: x474747)
    private static let backgroundSheets = DynamicColor(lightColor: xf9f9f9, darkColor: x373737)
    private static let backdrop = DynamicColor(lightColor: xe0e0e0, darkColor: x080808)
    private static let backgroundBlur = DynamicColor(staticColor: .gray90.opacity(0.7))

    // System - from DefaultColorPalette
    private static let lines = DynamicColor(lightColor: x1f1f1f.opacity(0.09), darkColor: xf9f9f9.opacity(0.12))
    private static let highlightDecoration = DynamicColor(lightColor: .tint(0.24), darkColor: xf9f9f9.opacity(0.12))

    // Various - from DefaultColorPalette
    private static let variousOutline = DynamicColor(lightColor: .shade(0.24), darkColor: .tint(0.24))

    // Accent Glow - from DefaultColorPalette
    private static let accent = DynamicColor(lightColor: .blue50, darkColor: .blue30)

    // System - from DefaultColorPalette
    private static let border = DynamicColor(lightColor: .gray30, darkColor: .gray40)

    // Alert - from DefaultColorPalette
    private static let alertGreen = DynamicColor(lightColor: .alertGreen, darkColor: .alertGreen)
    private static let alertYellow = DynamicColor(lightColor: .alertYellow, darkColor: .alertYellow)

    // Text - from DefaultColorPalette
    private static let textLink = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let textSelectionFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let textPlaceholder = DynamicColor(lightColor: x1f1f1f.opacity(0.4), darkColor: .tint(0.4))

    // Buttons/Primary - from DefaultColorPalette
    private static let buttonsPrimaryDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsPrimaryPressed = DynamicColor(lightColor: .blue70, darkColor: .blue50)
    private static let buttonsPrimaryDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    private static let buttonsPrimaryText = DynamicColor(lightColor: .white, darkColor: .shade(0.84))
    private static let buttonsPrimaryTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryFill - from DefaultColorPalette
    private static let buttonsSecondaryFillDefault = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    private static let buttonsSecondaryFillPressed = DynamicColor(lightColor: .shade(0.18), darkColor: .tint(0.3))
    private static let buttonsSecondaryFillDisabled = DynamicColor(lightColor: .shade(0.06), darkColor: .tint(0.18))
    private static let buttonsSecondaryFillText = DynamicColor(lightColor: .shade(0.84), darkColor: .white)
    private static let buttonsSecondaryFillTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/SecondaryWire - from DefaultColorPalette
    private static let buttonsSecondaryWireDefault = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsSecondaryWirePressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let buttonsSecondaryWireDisabledStroke = DynamicColor(lightColor: .shade(0.12), darkColor: .tint(0.24))
    private static let buttonsSecondaryWireText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsSecondaryWireTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    private static let buttonsSecondaryWireTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Ghost - from DefaultColorPalette
    private static let buttonsGhostPressedFill = DynamicColor(lightColor: .blue50.opacity(0.2), darkColor: .blue30.opacity(0.2))
    private static let buttonsGhostText = DynamicColor(lightColor: .blue50, darkColor: .blue30)
    private static let buttonsGhostTextPressed = DynamicColor(lightColor: .blue70, darkColor: .blue20)
    private static let buttonsGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // Buttons/Color - from DefaultColorPalette
    private static let buttonsBlack = DynamicColor(lightColor: .black, darkColor: .white)
    private static let buttonsWhite = DynamicColor(lightColor: .white, darkColor: .black)

    // Buttons/DeleteGhost - from DefaultColorPalette
    private static let buttonsDeleteGhostPressedFill = DynamicColor(lightColor: .alertRed50.opacity(0.12), darkColor: .alertRed20.opacity(0.18))
    private static let buttonsDeleteGhostTextPressed = DynamicColor(lightColor: .alertRed70, darkColor: .alertRed10)
    private static let buttonsDeleteGhostText = DynamicColor(lightColor: .alertRedOnLight, darkColor: .alertRedOnDark)
    private static let buttonsDeleteGhostTextDisabled = DynamicColor(lightColor: .shade(0.36), darkColor: .tint(0.36))

    // MARK: - ColorPaletteDefinition Implementation

    static func dynamicColor(for designSystemColor: DesignSystemColor) -> DynamicColor {
        switch designSystemColor {

        // Backgrounds
        case .urlBar: return urlBar
        case .background: return background
        case .backgroundTertiary: return backgroundTertiary
        case .backgroundSheets: return backgroundSheets
        case .backgroundBlur: return backgroundBlur
        case .backdrop: return backdrop
        case .panel: return background
        case .surface: return surfaceSecondary

        // Various
        case .variousOutline: return variousOutline

        // Shadows
        case .shadowPrimary: return shadowPrimary
        case .shadowSecondary: return shadowSecondary
        case .shadowTertiary: return shadowTertiary
        case .highlightDecoration: return highlightDecoration

        // Text
        case .textPrimary: return textPrimary
        case .textSecondary: return textSecondary
        case .textTertiary: return textTertiary
        case .textLink: return textLink
        case .textSelectionFill: return textSelectionFill
        case .textPlaceholder: return textPlaceholder

        // Controls
        case .controlsFillPrimary: return controlsFillPrimary
        case .controlsFillSecondary: return controlsFillSecondary
        case .controlsFillTertiary: return controlsFillTertiary
        case .controlsDecorationPrimary: return controlsDecorationPrimary
        case .controlsDecorationSecondary: return controlsDecorationSecondary
        case .controlsDecorationTertiary: return controlsDecorationTertiary

        // Brand / Accent
        case .accent: return accent
        case .accentGlowSecondary: return accentGlowSecondary
        case .accentContentPrimary: return accentContentPrimary
        case .accentContentSecondary: return accentContentSecondary
        case .accentContentTertiary: return accentContentTertiary
        case .accentGlowPrimary: return accentGlowPrimary
        case .accentPrimary: return accentPrimary
        case .accentSecondary: return accentSecondary
        case .accentTertiary: return accentTertiary
        case .accentTextPrimary: return accentTextPrimary
        case .accentTextSecondary: return accentTextSecondary
        case .accentTextTertiary: return accentTextTertiary

        // Accent Alt
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

        // System
        case .lines: return lines
        case .border: return border

        // Alert
        case .alertGreen: return alertGreen
        case .alertYellow: return alertYellow

        // Icons
        case .icons: return iconsPrimary
        case .iconsPrimary: return iconsPrimary
        case .iconsSecondary: return iconsSecondary
        case .iconsTertiary: return iconsTertiary

        // Surfaces
        case .surfaceBackdrop: return surfaceBackdrop
        case .surfaceCanvas: return surfaceCanvas
        case .surfacePrimary: return surfacePrimary
        case .surfaceSecondary: return surfaceSecondary
        case .surfaceTertiary: return surfaceTertiary

        // Tone
        case .toneShadePrimary: return toneShadePrimary
        case .toneTintPrimary: return toneTintPrimary

        // Highlight
        case .highlightPrimary: return highlightPrimary

        // Decorations
        case .decorationPrimary: return decorationPrimary
        case .decorationSecondary: return decorationSecondary
        case .decorationTertiary: return decorationTertiary

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

        // Buttons/Primary
        case .buttonsPrimaryDefault: return buttonsPrimaryDefault
        case .buttonsPrimaryPressed: return buttonsPrimaryPressed
        case .buttonsPrimaryDisabled: return buttonsPrimaryDisabled
        case .buttonsPrimaryText: return buttonsPrimaryText
        case .buttonsPrimaryTextDisabled: return buttonsPrimaryTextDisabled

        // Buttons/SecondaryFill
        case .buttonsSecondaryFillDefault: return buttonsSecondaryFillDefault
        case .buttonsSecondaryFillPressed: return buttonsSecondaryFillPressed
        case .buttonsSecondaryFillDisabled: return buttonsSecondaryFillDisabled
        case .buttonsSecondaryFillText: return buttonsSecondaryFillText
        case .buttonsSecondaryFillTextDisabled: return buttonsSecondaryFillTextDisabled

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
            return DynamicColor(staticColor: Color(0x818387))
        case .newTabPageItemAccessoryAddBackground:
            return DynamicColor(lightColor: surfaceSecondary.lightColor, darkColor: .gray85)
        case .unifiedFeedbackFieldBackground:
            return DynamicColor(lightColor: surfaceSecondary.lightColor, darkColor: Color(0x1C1C1E))
        case .downloadProgressBarBackground:
            return DynamicColor(lightColor: .gray85, darkColor: .gray70)
        case .privacyDashboardBackground:
            return DynamicColor(lightColor: surfaceSecondary.lightColor, darkColor: background.darkColor)
        case .duckPlayerPillBackground:
            return DynamicColor(lightColor: surfaceSecondary.lightColor, darkColor: .tint(0.12))
        }
    }
}
