//
//  ColorPaletteDefinition.swift
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

/// Color palette definition that logically collects all colors that work properly with each other.
protocol ColorPaletteDefinition {

    /// Gets dynamic color proxy for a specific semantic color.
    static func dynamicColor(for designSystemColor: DesignSystemColor) -> DynamicColor

    /// Gets dynamic color proxy for a single use semantic color.
    static func dynamicColor(for singleUseColor: SingleUseColor) -> DynamicColor

    /// Returns a base color.
    static func color(for baseColor: BaseColor) -> Color
}
