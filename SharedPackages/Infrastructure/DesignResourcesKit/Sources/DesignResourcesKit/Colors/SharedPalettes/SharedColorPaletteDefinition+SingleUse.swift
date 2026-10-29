//
//  SharedColorPaletteDefinition+SingleUse.swift
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
import SwiftUI

#if os(macOS)
extension SharedColorPaletteDefinition {

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        switch singleUseColor {

        /// Fire
        case .fireModeAccent:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin50, darkColor: RebrandingColor.Mandarin.mandarin40)
        case .fireButtonGradientStart:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin50, darkColor: RebrandingColor.Mandarin.mandarin40)
        case .fireButtonGradientEnd:
            return DynamicColor(lightColor: RebrandingColor.Red.red50, darkColor: RebrandingColor.Red.red40)
        case .fireButtonPressedGradientStart:
            return DynamicColor(staticColor: RebrandingColor.Mandarin.mandarin60)
        case .fireButtonPressedGradientEnd:
            return DynamicColor(staticColor: RebrandingColor.Red.red70)
        case .fireDialogKnobFill:
            return DynamicColor(staticColor: Color(0xFFFFFF))
        case .fireDialogTabBackground:
            return DynamicColor(lightColor: Color(designSystemColor: .controlsFillPrimary), darkColor: Color(designSystemColor: .surfaceCanvas))
        case .fireDialogTabBackgroundSelected:
            return DynamicColor(lightColor: Color(designSystemColor: .surfaceTertiary), darkColor: Color(designSystemColor: .surfaceSecondary))
        case .fireDialogTabShadowPrimary:
            return DynamicColor(lightColor: Color(designSystemColor: .shadowPrimary), darkColor: .shade(0.06))
        case .fireDialogTabShadowSecondary:
            return DynamicColor(lightColor: Color(designSystemColor: .shadowTertiary), darkColor: .shade(0.16))

        /// Spinner
        case .spinnerStart:
            return DynamicColor(lightHex: 0x000000, lightOpacity: 0.42, darkHex: 0xffffff, darkOpacity: 0.6)
        case .spinnerFinal:
            return DynamicColor(lightColor: .green60, darkColor: .green30)
        }
    }
}

#endif
