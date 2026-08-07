//
//  EnvironmentValues+DesignSystemPalette.swift
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

import SwiftUI

private struct DesignSystemPaletteKey: EnvironmentKey {
    static var defaultValue: ColorPalette { DesignSystemPalette.current }
}

public extension EnvironmentValues {

    /// The active design-system color palette for the view subtree.
    ///
    /// Host apps should inject this from their theme manager, e.g.
    /// `.environment(\.designSystemPalette, themeManager.designColorPalette)`, so that SwiftUI views
    /// reading it are re-evaluated when the palette changes with the theme.
    ///
    /// When not injected it falls back to the global `DesignSystemPalette.current`, matching the previous
    /// (non-reactive) behavior.
    var designSystemPalette: ColorPalette {
        get { self[DesignSystemPaletteKey.self] }
        set { self[DesignSystemPaletteKey.self] = newValue }
    }
}
