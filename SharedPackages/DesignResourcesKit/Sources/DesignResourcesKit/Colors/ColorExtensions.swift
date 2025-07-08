//
//  ColorExtensions.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

#if canImport(UIKit)

public extension Color {
    init(designSystemColor: DesignSystemColor, palette: ColorPalette = DesignSystemPalette.current) {
        self = palette.paletteDefinition.dynamicColor(for: designSystemColor).color
    }

    init(singleUseColor: SingleUseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self = palette.paletteDefinition.dynamicColor(for: singleUseColor).color
    }

    init(baseColor: BaseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self = palette.paletteDefinition.color(for: baseColor)
    }
}

public extension UIColor {
    convenience init(designSystemColor: DesignSystemColor, palette: ColorPalette = DesignSystemPalette.current) {
        self.init(dynamicProvider: palette.paletteDefinition.dynamicColor(for: designSystemColor).dynamicProvider)
    }

    convenience init(singleUseColor: SingleUseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self.init(dynamicProvider: palette.paletteDefinition.dynamicColor(for: singleUseColor).dynamicProvider)
    }

    convenience init(baseColor: BaseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self.init(palette.paletteDefinition.color(for: baseColor))
    }
}

#endif

#if canImport(AppKit)

public extension Color {
    init(designSystemColor: DesignSystemColor, palette: ColorPalette = DesignSystemPalette.current) {
        self = palette.paletteDefinition.dynamicColor(for: designSystemColor).color
    }

    init(singleUseColor: SingleUseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self = palette.paletteDefinition.dynamicColor(for: singleUseColor).color
    }

    init(baseColor: BaseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self = palette.paletteDefinition.color(for: baseColor)
    }
}

public extension NSColor {
    convenience init(designSystemColor: DesignSystemColor, palette: ColorPalette = DesignSystemPalette.current) {
        self.init(name: nil, dynamicProvider: palette.paletteDefinition.dynamicColor(for: designSystemColor).dynamicProvider)
    }

    convenience init(singleUseColor: SingleUseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self.init(name: nil, dynamicProvider: palette.paletteDefinition.dynamicColor(for: singleUseColor).dynamicProvider)
    }

    convenience init(baseColor: BaseColor, palette: ColorPalette = DesignSystemPalette.current) {
        self.init(palette.paletteDefinition.color(for: baseColor))
    }
}
#endif
