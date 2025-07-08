//
//  ExperimentalColorPalette.swift
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

struct ExperimentalColorPalette: ColorPaletteDefinition {

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

    private static let urlBar = DynamicColor(lightColor: .white, darkColor: x474747)

    private static let surface = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let backdrop = DynamicColor(lightColor: xE0E0E0, darkColor: x080808)
    private static let background = DynamicColor(lightColor: xF2F2F2, darkColor: x282828)
    private static let backgroundTertiary = DynamicColor(lightColor: .white, darkColor: x474747)
    private static let backgroundSheets = DynamicColor(lightColor: xF9F9F9, darkColor: x373737)
    private static let backgroundBlur = DynamicColor(staticColor: .gray90.opacity(0.7))

    // Shadow
    private static let shadowPrimary = DynamicColor(lightColor: x1F1F1F.opacity(0.04), darkColor: .shade(0.16))
    private static let shadowSecondary = DynamicColor(lightColor: x1F1F1F.opacity(0.08), darkColor: .shade(0.24))
    private static let shadowTertiary = DynamicColor(lightColor: x1F1F1F.opacity(0.24), darkColor: .shade(0.48))

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

    static func dynamicColor(for color: DesignSystemColor) -> DynamicColor {
        switch color {
        case .urlBar: return urlBar
        case .background: return background
        case .backgroundTertiary: return backgroundTertiary
        case .backgroundSheets: return backgroundSheets
        case .backgroundBlur: return backgroundBlur
        case .backdrop: return backdrop
        case .panel: return background
        case .surface: return surface
        case .container: return controlsFillPrimary // Using controlsFillPrimary here is intentional (container is deprecated)
        case .icons: return icons
        case .iconsSecondary: return iconsSecondary
        case .textPrimary: return textPrimary
        case .lines: return lines
        case .variousIPadTabs: return backdrop // Using backdrop here is intentional (variousIPadTabs is deprecated)
        case .shadowPrimary: return shadowPrimary
        case .shadowSecondary: return shadowSecondary
        case .shadowTertiary: return shadowTertiary
        case .controlsFillPrimary: return controlsFillPrimary
        case .controlsFillSecondary: return controlsFillSecondary
        case .controlsFillTertiary: return controlsFillTertiary

        default:
            return DefaultColorPalette.dynamicColor(for: color)
        }
    }

    static func color(for baseColor: BaseColor) -> Color {
        DefaultColorPalette.color(for: baseColor)
    }

    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor {
        DefaultColorPalette.dynamicColor(for: singleUseColor)
    }
}
