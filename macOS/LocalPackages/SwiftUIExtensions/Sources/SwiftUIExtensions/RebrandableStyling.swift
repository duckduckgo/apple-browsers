//
//  RebrandableStyling.swift
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
import DesignResourcesKit

public extension Color {

    /// Link / accent-text foreground color that follows the app-rebrand state, resolved against `palette`.
    ///
    /// Rebranded builds use the design-system `accentTextPrimary`; legacy builds keep `linkBlue`.
    static func rebrandableLink(palette: ColorPalette) -> Color {
        DesignSystemRebrand.isAppRebranded() ? Color(designSystemColor: .accentTextPrimary, palette: palette) : Color(.linkBlue)
    }
}

public extension View {

    /// Tints controls with the rebrand accent color when rebranded; applies the system default tint otherwise.
    ///
    /// Reads the palette from `\.designSystemPalette`, so the tint refreshes when the theme changes.
    func rebrandedControlTint() -> some View {
        modifier(RebrandedControlTintModifier())
    }

    /// Applies the rebrandable link color as the foreground, tracking the active theme via `\.designSystemPalette`.
    func rebrandableLinkForeground() -> some View {
        modifier(RebrandableLinkForegroundModifier())
    }
}

private struct RebrandedControlTintModifier: ViewModifier {
    @Environment(\.designSystemPalette) private var palette

    func body(content: Content) -> some View {
        content.tint(DesignSystemRebrand.isAppRebranded() ? Color(designSystemColor: .accentPrimary, palette: palette) : nil)
    }
}

private struct RebrandableLinkForegroundModifier: ViewModifier {
    @Environment(\.designSystemPalette) private var palette

    func body(content: Content) -> some View {
        content.foregroundColor(.rebrandableLink(palette: palette))
    }
}
