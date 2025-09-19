//
//  RoseThemeColors.swift
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

public struct RoseThemeColors: ThemeColors {
    public let accentContentPrimary         = PlatformColor(darkHex: "30031e", lightHex: "fffafe")
    public let accentContentSecondary       = PlatformColor(darkHex: "30031eb2", lightHex: "fffafeb2")
    public let accentContentTertiary        = PlatformColor(darkHex: "30031e7f", lightHex: "fffafe7f")
    public let accentGlowPrimary            = PlatformColor(darkHex: "fa7ddd33", lightHex: "d9009033")
    public let accentGlowSecondary          = PlatformColor(darkHex: "fa7ddd1e", lightHex: "d900901e")
    public let accentPrimary                = PlatformColor(darkHex: "fa7ddd", lightHex: "c1008e")
    public let accentQuaternary             = PlatformColor(darkHex: "d91ba0", lightHex: "660047")
    public let accentSecondary              = PlatformColor(darkHex: "f249c5", lightHex: "a30074")
    public let accentTertiary               = PlatformColor(darkHex: "e52eae", lightHex: "84005c")
    public let accentTextPrimary            = PlatformColor(darkHex: "ffa8ea", lightHex: "a30074")
    public let accentTextSecondary          = PlatformColor(darkHex: "fa7ddd", lightHex: "84005c")
    public let accentTextTertiary           = PlatformColor(darkHex: "f249c5", lightHex: "660047")
    public let containerDecorationPrimary   = PlatformColor(darkHex: "fffafe1e", lightHex: "11030b16")
    public let containerDecorationSecondary = PlatformColor(darkHex: "fffafe16", lightHex: "11030b0f")
    public let containerDecorationTertiary  = PlatformColor(darkHex: "fffafe16", lightHex: "11030b0f")
    public let containerFillPrimary         = PlatformColor(darkHex: "fffafe16", lightHex: "11030b0f")
    public let containerFillSecondary       = PlatformColor(darkHex: "fffafe0f", lightHex: "11030b07")
    public let containerFillTertiary        = PlatformColor(darkHex: "fffafe07", lightHex: "11030b02")
    public let controlsBase                 = PlatformColor(darkHex: "fc9be5", lightHex: "a30074")
    public let controlsDecorationPrimary    = PlatformColor(darkHex: "fc9ce67a", lightHex: "a3007551")
    public let controlsDecorationQuaternary = PlatformColor(darkHex: "fc9ce6cc", lightHex: "a30075b7")
    public let controlsDecorationSecondary  = PlatformColor(darkHex: "fc9ce6a3", lightHex: "a300758e")
    public let controlsDecorationTertiary   = PlatformColor(darkHex: "fc9ce6b7", lightHex: "a30075a3")
    public let controlsFillPrimary          = PlatformColor(darkHex: "fc9ce61e", lightHex: "a3007516")
    public let controlsFillSecondary        = PlatformColor(darkHex: "fc9ce62d", lightHex: "a300751e")
    public let controlsFillTertiary         = PlatformColor(darkHex: "fc9ce63d", lightHex: "a300752d")
    public let decorationPrimary            = PlatformColor(darkHex: "fa7ddd33", lightHex: "a3007533")
    public let decorationSecondary          = PlatformColor(darkHex: "fa7ddd3d", lightHex: "a3007566")
    public let decorationTertiary           = PlatformColor(darkHex: "fa7ddd51", lightHex: "a300758e")
    public let highlightPrimary             = PlatformColor(darkHex: "fffafe1e", lightHex: "fffafe3d")
    public let iconsPrimary                 = PlatformColor(darkHex: "fffafec6", lightHex: "30021ed6")
    public let iconsSecondary               = PlatformColor(darkHex: "fffafea8", lightHex: "30031ea8")
    public let iconsTertiary                = PlatformColor(darkHex: "fffafe5b", lightHex: "30031e5b")
    public let surfaceBackdrop              = PlatformColor(darkHex: "2d0525", lightHex: "ee9fd9")
    public let surfaceCanvas                = PlatformColor(darkHex: "59214a", lightHex: "fffafe")
    public let surfacePrimary               = PlatformColor(darkHex: "5b194b", lightHex: "f9eff7")
    public let surfaceSecondary             = PlatformColor(darkHex: "71275d", lightHex: "fbf2fa")
    public let surfaceTertiary              = PlatformColor(darkHex: "7e2e69", lightHex: "fff4fc")
    public let textPrimary                  = PlatformColor(darkHex: "fffafef4", lightHex: "30021ef4")
    public let textSecondary                = PlatformColor(darkHex: "fffafea8", lightHex: "30031ea8")
    public let textTertiary                 = PlatformColor(darkHex: "fffafe5b", lightHex: "30031e5b")

    // MARK: - Defaults / Non Customized
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
    public let shadowPrimary                = PlatformColor(darkHex: "00000028", lightHex: "0000000c")
    public let shadowSecondary              = PlatformColor(darkHex: "0000003d", lightHex: "00000014")
    public let shadowTertiary               = PlatformColor(darkHex: "00000051", lightHex: "00000028")
    public let toneShadePrimary             = PlatformColor(darkHex: "16161751", lightHex: "0000000f")
    public let toneTintPrimary              = PlatformColor(darkHex: "f9f9f91e", lightHex: "ffffff7a")
}
