//
//  ColorPalette.swift
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

public struct DesignSystemPalette {
    /// The current color palette set globally.
    ///
    /// Used as a default parameter value when creating colors via public color extensions.
    public static var current: ColorPalette = .default
}

public enum ColorPalette {
    case `default`

#if os(macOS)
    case coolGray
    case desert
    case green
    case orange
    case rose
    case slateBlue
    case violet

    var paletteDefinition: SharedColorPaletteDefinition.Type {
        switch self {
        case .default:
            return FigmaColorPalette.self
        case .coolGray:
            return CoolGrayColorPalette.self
        case .desert:
            return DesertColorPalette.self
        case .green:
            return GreenColorPalette.self
        case .orange:
            return OrangeColorPalette.self
        case .rose:
            return RoseColorPalette.self
        case .slateBlue:
            return SlateBlueColorPalette.self
        case .violet:
            return VioletColorPalette.self
        }
    }
#endif

#if os(iOS)
    var paletteDefinition: ColorPaletteDefinition.Type {
        switch self {
        case .default:
            DefaultColorPalette.self
        }
    }
#endif
}
