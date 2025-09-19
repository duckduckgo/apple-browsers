//
//  DefaultThemeColors.swift
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

import Foundation

public struct DefaultThemeColors: ThemeColors {
    public let accentAltContentPrimary      = PlatformColor(darkHex: "ccdaff", lightHex: "1e42a4")
    public let accentAltContentSecondary    = PlatformColor(darkHex: "e5edff", lightHex: "0b2059")
    public let accentAltContentTertiary     = PlatformColor(darkHex: "ffffff", lightHex: "051133")
    public let accentAltGlowPrimary         = PlatformColor(darkHex: "8fabf933", lightHex: "7295f633")
    public let accentAltGlowSecondary       = PlatformColor(darkHex: "8fabf91e", lightHex: "7295f61e")
    public let accentAltPrimary             = PlatformColor(darkHex: "2b55ca", lightHex: "ccdaff")
    public let accentAltSecondary           = PlatformColor(darkHex: "1e42a4", lightHex: "adc2fc")
    public let accentAltTertiary            = PlatformColor(darkHex: "14307e", lightHex: "8fabf9")
    public let accentAltTextPrimary         = PlatformColor(darkHex: "ccdaff", lightHex: "1e42a4")
    public let accentAltTextSecondary       = PlatformColor(darkHex: "adc2fc", lightHex: "14307e")
    public let accentAltTextTertiary        = PlatformColor(darkHex: "8fabf9", lightHex: "0b2059")
    public let accentContentPrimary         = PlatformColor(darkHex: "051133", lightHex: "ffffff")
    public let accentContentSecondary       = PlatformColor(darkHex: "03091a", lightHex: "ccdaff")
    public let accentContentTertiary        = PlatformColor(darkHex: "000000", lightHex: "adc2fc")
    public let accentGlowPrimary            = PlatformColor(darkHex: "7295f633", lightHex: "3969ef33")
    public let accentGlowSecondary          = PlatformColor(darkHex: "7295f61e", lightHex: "3969ef1e")
    public let accentPrimary                = PlatformColor(darkHex: "7295f6", lightHex: "3969ef")
    public let accentQuarternary            = PlatformColor(darkHex: "2b55ca", lightHex: "14307e")
    public let accentSecondary              = PlatformColor(darkHex: "557ff3", lightHex: "2b55ca")
    public let accentTertiary               = PlatformColor(darkHex: "3969ef", lightHex: "1e42a4")
    public let accentTextPrimary            = PlatformColor(darkHex: "adc2fc", lightHex: "3969ef")
    public let accentTextSecondary          = PlatformColor(darkHex: "8fabf9", lightHex: "2b55ca")
    public let accentTextTertiary           = PlatformColor(darkHex: "7295f6", lightHex: "1e42a4")
    public let containerDecorationPrimary   = PlatformColor(darkHex: "ffffff1e", lightHex: "00000016")
    public let containerDecorationSecondary = PlatformColor(darkHex: "ffffff16", lightHex: "0000000f")
    public let containerDecorationTertiary  = PlatformColor(darkHex: "ffffff16", lightHex: "0000000f")
    public let containerFillPrimary         = PlatformColor(darkHex: "ffffff16", lightHex: "0000000f")
    public let containerFillSecondary       = PlatformColor(darkHex: "ffffff0f", lightHex: "00000007")
    public let containerFillTertiary        = PlatformColor(darkHex: "ffffff07", lightHex: "00000002")
    public let controlsBase                 = PlatformColor(darkHex: "f8f8f8", lightHex: "1f1f1f")
    public let controlsDecorationPrimary    = PlatformColor(darkHex: "f9f9f95b", lightHex: "1f1f1f4c")
    public let controlsDecorationQuarternary = PlatformColor(darkHex: "f9f9f9cc", lightHex: "1f1f1fb7")
    public let controlsDecorationSecondary  = PlatformColor(darkHex: "f9f9f9a3", lightHex: "1f1f1f7a")
    public let controlsDecorationTertiary   = PlatformColor(darkHex: "f9f9f9b7", lightHex: "1f1f1f99")
    public let controlsFillPrimary          = PlatformColor(darkHex: "f9f9f91e", lightHex: "1f1f1f16")
    public let controlsFillSecondary        = PlatformColor(darkHex: "f9f9f92d", lightHex: "1f1f1f1e")
    public let controlsFillTertiary         = PlatformColor(darkHex: "f9f9f93d", lightHex: "1f1f1f2d")
    public let controlsRaisedBackdrop       = PlatformColor(darkHex: "ffffff1e", lightHex: "00000016")
    public let controlsRaisedFillPrimary    = PlatformColor(darkHex: "ffffff2d", lightHex: "ffffff")
    public let decorationPrimary            = PlatformColor(darkHex: "ffffff8e", lightHex: "0000008e")
    public let decorationQuaternary         = PlatformColor(darkHex: "ffffff0f", lightHex: "00000007")
    public let decorationSecondary          = PlatformColor(darkHex: "ffffff33", lightHex: "0000003d")
    public let decorationTertiary           = PlatformColor(darkHex: "ffffff1e", lightHex: "00000016")
    public let destructiveContentPrimary    = PlatformColor(darkHex: "000000", lightHex: "ffffff")
    public let destructiveContentSecondary  = PlatformColor(darkHex: "000000e5", lightHex: "ffffffe5")
    public let destructiveContentTertiary   = PlatformColor(darkHex: "00000099", lightHex: "ffffff99")
    public let destructiveGlow              = PlatformColor(darkHex: "ee102533", lightHex: "ee102533")
    public let destructivePrimary           = PlatformColor(darkHex: "ee1025", lightHex: "ee1025")
    public let destructiveSecondary         = PlatformColor(darkHex: "d11527", lightHex: "d11527")
    public let destructiveTertiary          = PlatformColor(darkHex: "aa1926", lightHex: "aa1926")
    public let destructiveTextPrimary       = PlatformColor(darkHex: "ee1025", lightHex: "ee1025")
    public let destructiveTextSecondary     = PlatformColor(darkHex: "d11527", lightHex: "d11527")
    public let destructiveTextTertiary      = PlatformColor(darkHex: "aa1926", lightHex: "aa1926")
    public let highlightPrimary             = PlatformColor(darkHex: "f9f9f91e", lightHex: "ffffff3d")
    public let iconsPrimary                 = PlatformColor(darkHex: "ffffffc6", lightHex: "000000d6")
    public let iconsSecondary               = PlatformColor(darkHex: "ffffff7a", lightHex: "00000099")
    public let iconsTertiary                = PlatformColor(darkHex: "ffffff3d", lightHex: "0000005b")
    public let shadowPrimary                = PlatformColor(darkHex: "00000028", lightHex: "0000000c")
    public let shadowSecondary              = PlatformColor(darkHex: "0000003d", lightHex: "00000014")
    public let shadowTertiary               = PlatformColor(darkHex: "00000051", lightHex: "00000028")
    public let surfaceBackdrop              = PlatformColor(darkHex: "070707", lightHex: "e0e0e0")
    public let surfaceCanvas                = PlatformColor(darkHex: "1c1c1c", lightHex: "fafafa")
    public let surfacePrimary               = PlatformColor(darkHex: "282828", lightHex: "f2f2f2")
    public let surfaceSecondary             = PlatformColor(darkHex: "373737", lightHex: "f9f9f9")
    public let surfaceTertiary              = PlatformColor(darkHex: "474747", lightHex: "ffffff")
    public let textPrimary                  = PlatformColor(darkHex: "fffffff4", lightHex: "000000f4")
    public let textSecondary                = PlatformColor(darkHex: "ffffffa8", lightHex: "000000a8")
    public let textTertiary                 = PlatformColor(darkHex: "ffffff5b", lightHex: "0000005b")
    public let toneShadePrimary             = PlatformColor(darkHex: "16161751", lightHex: "0000000f")
    public let toneTintPrimary              = PlatformColor(darkHex: "f9f9f91e", lightHex: "ffffff7a")

    public init() { }
}
