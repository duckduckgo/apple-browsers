//
//  RedesignedNewTabPageModuleBackground.swift
//  DuckDuckGo
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

import DesignResourcesKit
import SwiftUI

/// Surface shared by redesigned NTP modules. It matches the search input card: Liquid Glass when
/// `redesignedNewTabPageUsesLiquidGlass` is on, the raised card otherwise.
struct RedesignedNewTabPageModuleBackground: View {
    @Environment(\.redesignedNewTabPageUsesLiquidGlass) private var usesLiquidGlass

    var body: some View {
        RedesignedNewTabPageCardBackground(usesLiquidGlass: usesLiquidGlass)
    }
}

private struct RedesignedNewTabPageUsesLiquidGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether redesigned New Tab Page modules draw Liquid Glass surfaces, matching the floating input.
    var redesignedNewTabPageUsesLiquidGlass: Bool {
        get { self[RedesignedNewTabPageUsesLiquidGlassKey.self] }
        set { self[RedesignedNewTabPageUsesLiquidGlassKey.self] = newValue }
    }
}
