//
//  SharedColorPaletteDefinition+SingleUseColors.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

/// Single-use colours are hand-written and don't have matching Figma tokens
/// so can't be automatically generated.
extension SharedColorPaletteDefinition {

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        switch singleUseColor {
        case .aiToggleBorder:
            return DynamicColor(staticColor: .clear)
        case .aiToggleBackground:
            return controlSubtleFillSecondary
        case .aiToggleSelectionBackground:
            return controlRaisedFillPrimary
        case .aiToggleSelectionBorder:
            return shadowTertiary

        case .fireModeAccent:
            return DynamicColor(lightColor: RebrandingColor.Mandarin.mandarin50, darkColor: RebrandingColor.Mandarin.mandarin40)
        case .fireButtonGradientStart:
            return DynamicColor(staticColor: RebrandingColor.Mandarin.mandarin50)
        case .fireButtonGradientEnd:
            return DynamicColor(staticColor: RebrandingColor.Red.red50)
        case .fireButtonPressedGradientStart:
            return DynamicColor(staticColor: RebrandingColor.Mandarin.mandarin60)
        case .fireButtonPressedGradientEnd:
            return DynamicColor(staticColor: RebrandingColor.Red.red70)
        }
    }
}

#endif
