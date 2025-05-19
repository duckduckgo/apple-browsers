//
//  ColorsProviding.swift
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

protocol ColorsProviding {
    var navigationBackgroundColor: NSColor { get }
    var baseBackgroundColor: NSColor { get }
    var textPrimaryColor: NSColor { get }
    var textSecondaryColor: NSColor { get }
    var backgroundTertiaryColor: NSColor { get }
    var accentPrimaryColor: NSColor { get }
    var addressBarOutlineShadow: NSColor { get }
    var iconsColor: NSColor { get }
    var buttonMouseOverColor: NSColor { get }
    var addressBarSuffixTextColor: NSColor { get }
    var addressBarTextFieldColor: NSColor { get }
    var settingsBackgroundColor: NSColor { get }
    var bookmarksManagerBackgroundColor: NSColor { get }
    var bookmarksPanelBackgroundColor: NSColor { get }
    var downloadsPanelBackgroundColor: NSColor { get }
    var passwordManagerBackgroundColor: NSColor { get }
    var passwordManagerLockScreenBackgroundColor: NSColor { get }

    /// New Tab Page
    var ntpLightBackgroundColor: String { get }
    var ntpDarkBackgroundColor: String { get }
}

final class LegacyColorsProviding: ColorsProviding {
    var navigationBackgroundColor: NSColor { .navigationBarBackground }
    var baseBackgroundColor: NSColor { .windowBackground }
    var textPrimaryColor: NSColor { .labelColor }
    var textSecondaryColor: NSColor { .secondaryLabelColor }
    var backgroundTertiaryColor: NSColor { .inactiveSearchBarBackground }
    var accentPrimaryColor: NSColor { .controlAccentColor.withAlphaComponent(0.8) }
    var addressBarOutlineShadow: NSColor { .controlColor.withAlphaComponent(0.2) }
    var iconsColor: NSColor { .button }
    var buttonMouseOverColor: NSColor { .buttonMouseOver }
    var addressBarSuffixTextColor: NSColor { .addressBarSuffix }
    var addressBarTextFieldColor: NSColor { .suggestionText }
    var settingsBackgroundColor: NSColor { .preferencesBackground }
    var bookmarksManagerBackgroundColor: NSColor { .bookmarkPageBackground}
    var bookmarksPanelBackgroundColor: NSColor { .popoverBackground }
    var downloadsPanelBackgroundColor: NSColor { .popoverBackground }
    var passwordManagerBackgroundColor: NSColor { .popoverBackground }
    var passwordManagerLockScreenBackgroundColor: NSColor { .neutralBackground }
    var ntpLightBackgroundColor: String { "#FAFAFA" }
    var ntpDarkBackgroundColor: String { "#333333" }

}

final class NewColorsProviding: ColorsProviding {
    private let palette: ColorPalette

    var navigationBackgroundColor: NSColor { palette.surfacePrimary }
    var baseBackgroundColor: NSColor { palette.surfaceBackdrop }
    var textPrimaryColor: NSColor { palette.textPrimary }
    var textSecondaryColor: NSColor { palette.textSecondary }
    var backgroundTertiaryColor: NSColor { palette.surfaceTertiary }
    var accentPrimaryColor: NSColor { palette.accentPrimary }
    var addressBarOutlineShadow: NSColor { palette.accentAltGlow }
    var addressBarSuffixTextColor: NSColor { palette.textSecondary }
    var addressBarTextFieldColor: NSColor { palette.textPrimary }
    var settingsBackgroundColor: NSColor { palette.surfacePrimary }
    var iconsColor: NSColor { palette.iconsPrimary }
    var buttonMouseOverColor: NSColor { palette.controlsFillPrimary }
    var bookmarksManagerBackgroundColor: NSColor { palette.surfacePrimary }
    var bookmarksPanelBackgroundColor: NSColor { palette.surfacePrimary }
    var downloadsPanelBackgroundColor: NSColor { palette.surfacePrimary }
    var passwordManagerBackgroundColor: NSColor { palette.surfacePrimary }
    var passwordManagerLockScreenBackgroundColor: NSColor { palette.surfacePrimary }
    var ntpLightBackgroundColor: String { "#F2F2F2" }
    var ntpDarkBackgroundColor: String { "#27282A" }

    init(palette: ColorPalette) {
        self.palette = palette
    }
}
