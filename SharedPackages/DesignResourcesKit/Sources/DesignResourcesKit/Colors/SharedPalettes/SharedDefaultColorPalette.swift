//
//  SharedDefaultColorPalette.swift
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

#if canImport(AppKit)

/// Based on DefaultColorPalette, for compatibility. This class will be removed as soon as `FigmaColorPalette` is validated
struct SharedDefaultColorPalette: SharedColorPaletteDefinition {
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
    private static let x282828 = Color(0x282828)
    private static let x373737 = Color(0x373737)
    private static let x7295F6 = Color(0x7295F6)

    // Accents
    static let accentContentPrimary = DynamicColor(lightColor: .white, darkColor: .black)
    static let accentGlowPrimary = DynamicColor(lightHex: 0x3969ef, lightOpacityHex: 0x33, darkHex: 0x7295f6, darkOpacityHex: 0x33)
    static let accentGlowSecondary = DynamicColor(lightColor: x3969EF.opacity(0.12), darkColor: x7295F6.opacity(0.12))
    static let accentContentSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0xb2, darkHex: 0x051133, darkOpacityHex: 0xb2)
    static let accentContentTertiary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x7f, darkHex: 0x051133, darkOpacityHex: 0x7f)
    static let accentPrimary = DynamicColor(lightHex: 0x3969ef, darkHex: 0x7295f6)
    static let accentQuaternary = DynamicColor(lightHex: 0x14307e, darkHex: 0x2b55ca)
    static let accentSecondary = DynamicColor(lightHex: 0x2b55ca, darkHex: 0x557ff3)
    static let accentTertiary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0x3969ef)
    static let accentTextPrimary = DynamicColor(lightHex: 0x3969ef, darkHex: 0xadc2fc)
    static let accentTextSecondary = DynamicColor(lightHex: 0x2b55ca, darkHex: 0x8fabf9)
    static let accentTextTertiary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0x7295f6)

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

    // Buttons/Color
    static let buttonsWhite = DynamicColor(lightColor: .white, darkColor: .black)

    // Container Colors
    static let containerDecorationPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x16, darkHex: 0xffffff, darkOpacityHex: 0x1e)
    static let containerDecorationSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0xffffff, darkOpacityHex: 0x16)
    static let containerDecorationTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0xffffff, darkOpacityHex: 0x16)
    static let containerFillPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x02, darkHex: 0xffffff, darkOpacityHex: 0x07)
    static let containerFillSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x07, darkHex: 0xffffff, darkOpacityHex: 0x0f)
    static let containerFillTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0xffffff, darkOpacityHex: 0x16)
    static let containerBorderTertiary = FigmaColorPalette.containerBorderTertiary

    // Controls Colors
    static let controlsBase = DynamicColor(lightHex: 0x1f1f1f, darkHex: 0xf8f8f8)
    static let controlsDecorationPrimary = DynamicColor(lightHex: 0x1f1f1f, lightOpacityHex: 0x4c, darkHex: 0xf9f9f9, darkOpacityHex: 0x5b)
    static let controlsDecorationSecondary = DynamicColor(lightHex: 0x1f1f1f, lightOpacityHex: 0x7a, darkHex: 0xf9f9f9, darkOpacityHex: 0xa3)
    static let controlsDecorationTertiary = DynamicColor(lightHex: 0x1f1f1f, lightOpacityHex: 0x99, darkHex: 0xf9f9f9, darkOpacityHex: 0xb7)
    static let controlsDecorationQuaternary = DynamicColor(lightHex: 0x1f1f1f, lightOpacityHex: 0xb7, darkHex: 0xf9f9f9, darkOpacityHex: 0xcc)

    // Controls
    static let controlsFillPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))
    static let controlsFillSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.12), darkColor: xF9F9F9.opacity(0.18))
    static let controlsFillTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.18), darkColor: xF9F9F9.opacity(0.24))

    // Decorations
    static let surfaceDecorationPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.3), darkColor: xF9F9F9.opacity(0.36))
    static let surfaceDecorationSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.48), darkColor: xF9F9F9.opacity(0.64))
    static let surfaceDecorationTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

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

    // Highlight
    static let highlightPrimary = DynamicColor(lightColor: .tint(0.24), darkColor: xF9F9F9.opacity(0.12))

    // Icons Colors
    static let icons = DynamicColor(lightColor: x1F1F1F.opacity(0.84), darkColor: .tint(0.78))
    static let iconsPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0xd6, darkHex: 0xffffff, darkOpacityHex: 0xc6)
    static let iconsSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.6), darkColor: .tint(0.48))
    static let iconsTertiary = DynamicColor(lightColor: x000000.opacity(0.36), darkColor: xFFFFFF.opacity(0.24))

    // System
    static let lines = DynamicColor(lightColor: x1F1F1F.opacity(0.09), darkColor: xF9F9F9.opacity(0.12))

    // Shadow Colors
    static let shadowPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.04), darkColor: .shade(0.16))
    static let shadowSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.08), darkColor: .shade(0.24))
    static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.16), darkColor: .shade(0.32))

    // Surface Colors
    static let surface = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    static let surfaceBackdrop = DynamicColor(lightHex: 0xe0e0e0, darkHex: 0x070707)
    static let surfaceCanvas = DynamicColor(lightHex: 0xfafafa, darkHex: 0x1c1c1c)
    static let surfacePrimary = DynamicColor(lightHex: 0xf2f2f2, darkHex: 0x282828)
    static let surfaceSecondary = DynamicColor(lightHex: 0xf9f9f9, darkHex: 0x373737)
    static let surfaceTertiary = DynamicColor(lightColor: .white, darkColor: .x474747)

    // Text
    static let textPrimary = DynamicColor(lightColor: x1F1F1F, darkColor: .tint(0.9))
    static let textSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.72), darkColor: .tint(0.6))
    static let textTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x5b, darkHex: 0xffffff, darkOpacityHex: 0x5b)

    // Tone Colors
    static let toneShadePrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0x161617, darkOpacityHex: 0x51)
    static let toneTintPrimary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x7a, darkHex: 0xf9f9f9, darkOpacityHex: 0x1e)
}

#endif
