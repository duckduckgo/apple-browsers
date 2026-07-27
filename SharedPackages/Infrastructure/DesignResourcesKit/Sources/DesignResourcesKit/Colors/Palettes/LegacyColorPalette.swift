//
//  LegacyColorPalette.swift
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

/// The pre-2026 colours, frozen.
///
/// Unlike every other palette this one is not regenerated from Figma. It is deleted when the
/// rebrand flag goes away, so re-deriving it would only change what non-rebranded users see.
/// Property renames and tokens Figma has newly added are applied by hand; values are not.
struct LegacyColorPalette: SharedColorPaletteDefinition {
    static let accentAltContentPrimary = DynamicColor(lightHex: 0x0b2059, darkHex: 0xccdaff)
    static let accentAltContentSecondary = DynamicColor(lightHex: 0x0b2059, lightOpacityHex: 0xb2, darkHex: 0xe5edff)
    static let accentAltContentTertiary = DynamicColor(lightHex: 0x0b2059, lightOpacityHex: 0x7f, darkHex: 0xffffff)
    static let accentAltGlowPrimary = DynamicColor(lightHex: 0x7295f6, lightOpacityHex: 0x33, darkHex: 0x8fabf9, darkOpacityHex: 0x33)
    static let accentAltGlowSecondary = DynamicColor(lightHex: 0x7295f6, lightOpacityHex: 0x1e, darkHex: 0x8fabf9, darkOpacityHex: 0x1e)
    static let accentAltPrimary = DynamicColor(lightHex: 0xccdaff, darkHex: 0x2b55ca)
    static let accentAltSecondary = DynamicColor(lightHex: 0xadc2fc, darkHex: 0x1e42a4)
    static let accentAltTertiary = DynamicColor(lightHex: 0x8fabf9, darkHex: 0x14307e)
    static let accentAltTextPrimary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0xccdaff)
    static let accentAltTextSecondary = DynamicColor(lightHex: 0x14307e, darkHex: 0xadc2fc)
    static let accentAltTextTertiary = DynamicColor(lightHex: 0x0b2059, darkHex: 0x8fabf9)
    static let accentBrandContentPrimary = DynamicColor(lightHex: 0xffffff, darkHex: 0x240f04)
    static let accentBrandContentSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0xb2, darkHex: 0x1a0b03, darkOpacityHex: 0xb7)
    static let accentBrandContentTertiary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x7f, darkHex: 0x1a0b03, darkOpacityHex: 0x7a)
    static let accentBrandGlowPrimary = DynamicColor(lightHex: 0xf05f2b, lightOpacityHex: 0x33, darkHex: 0xffc95c, darkOpacityHex: 0x33)
    static let accentBrandGlowSecondary = DynamicColor(lightHex: 0xf05f2b, lightOpacityHex: 0x1e, darkHex: 0xffc95c, darkOpacityHex: 0x1e)
    static let accentBrandPrimary = DynamicColor(lightHex: 0xf05f2a, darkHex: 0xffc95c)
    static let accentBrandSecondary = DynamicColor(lightHex: 0xcc3b0a, darkHex: 0xfab341)
    static let accentBrandTertiary = DynamicColor(lightHex: 0x9e2b08, darkHex: 0xf5a031)
    static let accentBrandTextPrimary = DynamicColor(lightHex: 0xf05f2a, darkHex: 0xffd885)
    static let accentBrandTextSecondary = DynamicColor(lightHex: 0xcc3b0a, darkHex: 0xffc95c)
    static let accentBrandTextTertiary = DynamicColor(lightHex: 0x9e2b08, darkHex: 0xfab341)
    static let accentContentPrimary = DynamicColor(lightHex: 0xffffff, darkHex: 0x051133)
    static let accentContentSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0xb2, darkHex: 0x051133, darkOpacityHex: 0xb2)
    static let accentContentTertiary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x7f, darkHex: 0x051133, darkOpacityHex: 0x7f)
    static let accentFireContentPrimary = DynamicColor(lightHex: 0xffffff, darkHex: 0xffffff)
    static let accentFireContentSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0xb2, darkHex: 0xffffff, darkOpacityHex: 0xb2)
    static let accentFireContentTertiary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x7f, darkHex: 0xffffff, darkOpacityHex: 0x7f)
    static let accentFireGlowPrimary = DynamicColor(lightHex: 0xf05f2b, lightOpacityHex: 0x33, darkHex: 0xff8d5c, darkOpacityHex: 0x33)
    static let accentFireGlowSecondary = DynamicColor(lightHex: 0xf05f2b, lightOpacityHex: 0x1e, darkHex: 0xff8d5c, darkOpacityHex: 0x1e)
    static let accentFirePrimary = DynamicColor(lightHex: 0xf05f2a, darkHex: 0xff8c5b)
    static let accentFireSecondary = DynamicColor(lightHex: 0xcc3b0a, darkHex: 0xf05f2a)
    static let accentFireTertiary = DynamicColor(lightHex: 0x9e2b08, darkHex: 0xcc3b0a)
    static let accentFireTextPrimary = DynamicColor(lightHex: 0xf05f2a, darkHex: 0xff8c5b)
    static let accentFireTextSecondary = DynamicColor(lightHex: 0xcc3b0a, darkHex: 0xf05f2a)
    static let accentFireTextTertiary = DynamicColor(lightHex: 0x9e2b08, darkHex: 0xcc3b0a)
    static let accentGlowPrimary = DynamicColor(lightHex: 0x3969ef, lightOpacityHex: 0x33, darkHex: 0x7295f6, darkOpacityHex: 0x33)
    static let accentGlowSecondary = DynamicColor(lightHex: 0x3969ef, lightOpacityHex: 0x1e, darkHex: 0x7295f6, darkOpacityHex: 0x1e)
    static let accentPrimary = DynamicColor(lightHex: 0x3869ef, darkHex: 0x8fabf9)
    static let accentQuaternary = DynamicColor(lightHex: 0x14307e, darkHex: 0x2b55ca)
    static let accentSecondary = DynamicColor(lightHex: 0x2b55ca, darkHex: 0x7295f6)
    static let accentTertiary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0x557ff3)
    static let accentTextPrimary = DynamicColor(lightHex: 0x3869ef, darkHex: 0xadc2fc)
    static let accentTextSecondary = DynamicColor(lightHex: 0x2b55ca, darkHex: 0x8fabf9)
    static let accentTextTertiary = DynamicColor(lightHex: 0x1e42a4, darkHex: 0x7295f6)
    static let containerBorderPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0xffffff, darkOpacityHex: 0x16)
    static let containerBorderSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x16, darkHex: 0xffffff, darkOpacityHex: 0x1e)
    static let containerBorderTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x1e, darkHex: 0xffffff, darkOpacityHex: 0x28)
    static let containerFillPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x02, darkHex: 0xffffff, darkOpacityHex: 0x07)
    static let containerFillSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x07, darkHex: 0xffffff, darkOpacityHex: 0x0f)
    static let containerFillTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0xffffff, darkOpacityHex: 0x16)
    static let controlBorderPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x4c, darkHex: 0xffffff, darkOpacityHex: 0x5b)
    static let controlBorderQuaternary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0xb7, darkHex: 0xffffff, darkOpacityHex: 0xcc)
    static let controlBorderSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x7a, darkHex: 0xffffff, darkOpacityHex: 0xa3)
    static let controlBorderTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x99, darkHex: 0xffffff, darkOpacityHex: 0xb7)
    static let controlFillPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0f, darkHex: 0xffffff, darkOpacityHex: 0x1e)
    static let controlFillSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x16, darkHex: 0xffffff, darkOpacityHex: 0x2d)
    static let controlFillTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x1e, darkHex: 0xffffff, darkOpacityHex: 0x3d)
    static let controlRaisedBackdrop = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x16, darkHex: 0xffffff, darkOpacityHex: 0x1e)
    static let controlRaisedFillPrimary = DynamicColor(lightHex: 0xffffff, darkHex: 0xffffff, darkOpacityHex: 0x2d)
    static let controlRaisedFillSecondary = DynamicColor(lightHex: 0xffffff, darkHex: 0xffffff, darkOpacityHex: 0x2d)
    static let controlRaisedFillTertiary = DynamicColor(lightHex: 0xffffff, darkHex: 0xffffff, darkOpacityHex: 0x2d)
    static let controlSubtleBorderPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x1e, darkHex: 0xffffff, darkOpacityHex: 0x1e)
    static let controlSubtleBorderSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x2d, darkHex: 0xffffff, darkOpacityHex: 0x2d)
    static let controlSubtleBorderTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x5b, darkHex: 0xffffff, darkOpacityHex: 0x5b)
    static let controlSubtleFillSecondary = DynamicColor(lightHex: 0x000000, lightOpacity: 0.04, darkHex: 0xffffff, darkOpacity: 0.06)
    static let destructiveContentPrimary = DynamicColor(lightHex: 0xffffff, darkHex: 0x000000)
    static let destructiveContentSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0xe5, darkHex: 0x000000, darkOpacityHex: 0xe5)
    static let destructiveContentTertiary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x99, darkHex: 0x000000, darkOpacityHex: 0x99)
    static let destructiveGlowSecondary = DynamicColor(lightHex: 0xee1025, lightOpacityHex: 0x33, darkHex: 0xff545a, darkOpacityHex: 0x1e)
    static let destructivePrimary = DynamicColor(lightHex: 0xee1025, darkHex: 0xff5359)
    static let destructiveSecondary = DynamicColor(lightHex: 0xd11527, darkHex: 0xd11527)
    static let destructiveTertiary = DynamicColor(lightHex: 0xaa1826, darkHex: 0xaa1926)
    static let destructiveTextPrimary = DynamicColor(lightHex: 0xee1025, darkHex: 0xff5359)
    static let destructiveTextSecondary = DynamicColor(lightHex: 0xd11527, darkHex: 0xd11527)
    static let destructiveTextTertiary = DynamicColor(lightHex: 0xaa1926, darkHex: 0xaa1926)
    static let highlightPrimary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x3d, darkHex: 0xf9f9f9, darkOpacityHex: 0x1e)
    static let iconsPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0xd6, darkHex: 0xffffff, darkOpacityHex: 0xc6)
    static let iconsSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x99, darkHex: 0xffffff, darkOpacityHex: 0x7a)
    static let iconsTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x5b, darkHex: 0xffffff, darkOpacityHex: 0x3d)
    static let unifiedInputFieldFillActive = DynamicColor(lightHex: 0xffffff, darkHex: 0x3d3d3d)
    static let unifiedInputFieldFillResting = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0c, darkHex: 0xffffff, darkOpacityHex: 0x14)
    static let shadowPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x0c, darkHex: 0x000000, darkOpacityHex: 0x28)
    static let shadowSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x14, darkHex: 0x000000, darkOpacityHex: 0x3d)
    static let shadowTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x28, darkHex: 0x000000, darkOpacityHex: 0x51)
    static let statusGray = DynamicColor(lightHex: 0xaaaaaa, darkHex: 0xaaaaaa)
    static let statusGreen = DynamicColor(lightHex: 0x38b26a, darkHex: 0x38b26a)
    static let statusRed = DynamicColor(lightHex: 0xea0f2c, darkHex: 0xff5359)
    static let statusWarningContentPrimary = DynamicColor(lightHex: 0x191101, darkHex: 0x191101)
    static let statusWarningFillPrimary = DynamicColor(lightHex: 0xffe699, lightOpacityHex: 0x51, darkHex: 0xffb200, darkOpacityHex: 0x1e)
    static let statusWarningPrimary = DynamicColor(lightHex: 0xffc95c, darkHex: 0xffd885)
    static let statusYellowPrimary = DynamicColor(lightHex: 0xfab341, darkHex: 0xfab341)
    static let statusYellowSecondary = DynamicColor(lightHex: 0xFFC95C, darkHex: 0xFFC95C)
    static let statusYellowTertiary = DynamicColor(lightHex: 0xFFD885, darkHex: 0xFFD885)
    static let surfaceBackdrop = DynamicColor(lightHex: 0xe0e0e0, darkHex: 0x050505)
    static let surfaceCanvas = DynamicColor(lightHex: 0xfafafa, darkHex: 0x1c1c1c)
    static let surfaceContrast = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0xf4, darkHex: 0xffffff, darkOpacityHex: 0xf4)
    static let surfaceDecorationPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x16, darkHex: 0xffffff, darkOpacityHex: 0x1e)
    static let surfaceDecorationSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x28, darkHex: 0xffffff, darkOpacityHex: 0x33)
    static let surfaceDecorationTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x3d, darkHex: 0xffffff, darkOpacityHex: 0x51)
    static let surfacePrimary = DynamicColor(lightHex: 0xf2f2f2, darkHex: 0x282828)
    static let surfaceSecondary = DynamicColor(lightHex: 0xfafafa, darkHex: 0x333333)
    static let surfaceTertiary = DynamicColor(lightHex: 0xffffff, darkHex: 0x3d3d3d)
    static let textPrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0xf4, darkHex: 0xffffff, darkOpacityHex: 0xf4)
    static let textSecondary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x99, darkHex: 0xffffff, darkOpacityHex: 0x99)
    static let textTertiary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x5b, darkHex: 0xffffff, darkOpacityHex: 0x5b)
    static let toneShadePrimary = DynamicColor(lightHex: 0x000000, lightOpacityHex: 0x07, darkHex: 0x000000, darkOpacityHex: 0x1e)
    static let toneTintPrimary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x51, darkHex: 0xffffff, darkOpacityHex: 0x0f)
    static let toneTintSecondary = DynamicColor(lightHex: 0xffffff, lightOpacityHex: 0x99, darkHex: 0xffffff, darkOpacityHex: 0x1e)

    // MARK: - Not Specialized

    static let destructiveGlowPrimary = DynamicColor(lightHex: 0xee1025, lightOpacityHex: 0x33, darkHex: 0xee1025, darkOpacityHex: 0x33)

    // MARK: - Added by Figma (not yet used by any call site)
    static let controlSubtleFillPrimary = DynamicColor(lightHex: 0x000000, lightOpacity: 0.02, darkHex: 0xFFFFFF, darkOpacity: 0.03)
    static let controlSubtleFillTertiary = DynamicColor(lightHex: 0x000000, lightOpacity: 0.08, darkHex: 0xFFFFFF, darkOpacity: 0.12)
    static let unifiedInputFillPrimary = DynamicColor(lightHex: 0xFFFFFF, darkHex: 0xFFFFFF)  // light-only in Figma; dark mirrors light
}
