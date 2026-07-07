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

import AppKit
import DesignResourcesKit
import PrivacyConfig

protocol ColorsProviding {
    // MARK: - Address Bar
    var addressBarOutlineShadow: NSColor { get }
    var addressBarShadowColor: NSColor { get }
    var addressBarSuffixTextColor: NSColor { get }
    var addressBarTextFieldColor: NSColor { get }
    var addressBarActiveBorderColor: NSColor { get }
    var addressBarFireBorderColor: NSColor { get }
    var activeAddressBarBackgroundColor: NSColor { get }
    var inactiveAddressBarBackgroundColor: NSColor { get }

    // MARK: - Bookmarks
    var bookmarksManagerBackgroundColor: NSColor { get }
    var bookmarksPanelBackgroundColor: NSColor { get }

    // MARK: - Downloads
    var downloadsPanelBackgroundColor: NSColor { get }

    // MARK: - Navigation
    var navigationBackgroundColor: NSColor { get }

    // MARK: - Passwords
    var passwordManagerBackgroundColor: NSColor { get }
    var passwordManagerLockScreenBackgroundColor: NSColor { get }

    // MARK: - Settings
    var settingsBackgroundColor: NSColor { get }

    // MARK: - Suggestions
    var suggestionsBackgroundColor: NSColor { get }
    var suggestionsTextColor: NSColor { get }
    var suggestionsSuffixColor: NSColor { get }
    var suggestionsHighlightSuffixColor: NSColor { get }
    var suggestionsHighlightBackgroundColor: NSColor { get }
    var suggestionsHighlightTextColor: NSColor { get }

    // MARK: - Semantic
    var accentPrimaryColor: NSColor { get }
    var baseBackgroundColor: NSColor { get }
    var bannerBackgroundColor: NSColor { get }
    var buttonMouseOverColor: NSColor { get }
    var buttonMouseDownColor: NSColor { get }
    var buttonMouseDownPressedColor: NSColor { get }
    var fillButtonBackgroundColor: NSColor { get }
    var fillButtonMouseOverColor: NSColor { get }
    var iconsColor: NSColor { get }
    var popoverBackgroundColor: NSColor { get }
    var separatorColor: NSColor { get }
    var separatorActiveColor: NSColor { get }
    var textPrimaryColor: NSColor { get }
    var textSecondaryColor: NSColor { get }
    var textTertiaryColor: NSColor { get }
}

struct ColorsProvidingFactory {

    static func buildColorsProvider(featureFlagger: FeatureFlagger, palette: ThemeColors) -> ColorsProviding {
        if featureFlagger.isFeatureOn(.appRebranding) {
            return CurrentColorsProviding(palette: palette)
        }

        return LegacyColorsProviding(palette: palette)
    }
}

final class LegacyColorsProviding: ColorsProviding {

    private let palette: ThemeColors

    var navigationBackgroundColor: NSColor { palette.surfacePrimary }
    var baseBackgroundColor: NSColor { palette.surfaceBackdrop }
    var textPrimaryColor: NSColor { palette.textPrimary }
    var textSecondaryColor: NSColor { palette.textSecondary }
    var textTertiaryColor: NSColor { palette.textTertiary }
    var accentPrimaryColor: NSColor { palette.accentPrimary }
    var addressBarOutlineShadow: NSColor { palette.accentAltGlowPrimary }
    var addressBarShadowColor: NSColor { palette.shadowTertiary }
    var addressBarSuffixTextColor: NSColor { palette.textSecondary }
    var addressBarTextFieldColor: NSColor { palette.textPrimary }
    var addressBarActiveBorderColor: NSColor { palette.accentPrimary }
    var addressBarFireBorderColor: NSColor { NSColor.burnerAccent.withAlphaComponent(0.8) }

    var settingsBackgroundColor: NSColor { palette.surfaceCanvas }
    var iconsColor: NSColor { palette.iconsPrimary }
    var buttonMouseOverColor: NSColor { palette.controlsFillPrimary }
    var buttonMouseDownColor: NSColor { palette.controlsFillSecondary }
    var buttonMouseDownPressedColor: NSColor { palette.controlsFillTertiary }
    var separatorColor: NSColor { palette.surfaceDecorationPrimary }
    var separatorActiveColor: NSColor { palette.surfaceDecorationSecondary }
    var fillButtonBackgroundColor: NSColor { palette.controlsFillPrimary }
    var fillButtonMouseOverColor: NSColor { palette.controlsFillSecondary }
    var bookmarksManagerBackgroundColor: NSColor { palette.surfaceCanvas }
    var bookmarksPanelBackgroundColor: NSColor { palette.surfaceSecondary }
    var downloadsPanelBackgroundColor: NSColor { palette.surfaceSecondary }
    var passwordManagerBackgroundColor: NSColor { palette.surfaceSecondary }
    var passwordManagerLockScreenBackgroundColor: NSColor { palette.surfaceSecondary }
    var activeAddressBarBackgroundColor: NSColor { palette.surfaceTertiary }
    var inactiveAddressBarBackgroundColor: NSColor { palette.surfaceTertiary }
    var suggestionsBackgroundColor: NSColor { palette.surfaceTertiary }
    var suggestionsTextColor: NSColor { addressBarTextFieldColor }
    var suggestionsSuffixColor: NSColor { palette.accentPrimary }
    var suggestionsHighlightSuffixColor: NSColor { palette.accentContentSecondary }
    var suggestionsHighlightBackgroundColor: NSColor { palette.accentPrimary }
    var suggestionsHighlightTextColor: NSColor { palette.accentContentPrimary }
    var bannerBackgroundColor: NSColor { palette.surfacePrimary }
    var popoverBackgroundColor: NSColor { palette.surfaceSecondary }

    init(palette: ThemeColors) {
        self.palette = palette
    }
}

final class CurrentColorsProviding: ColorsProviding {

    private let palette: ThemeColors

    // MARK: - Address Bar
    var addressBarActiveBorderColor: NSColor { palette.accentPrimary }
    var addressBarFireBorderColor: NSColor { palette.accentFirePrimary }
    var addressBarOutlineShadow: NSColor { palette.accentAltGlowPrimary }
    var addressBarShadowColor: NSColor { palette.shadowTertiary }
    var addressBarSuffixTextColor: NSColor { palette.textSecondary }
    var addressBarTextFieldColor: NSColor { palette.textPrimary }
    var activeAddressBarBackgroundColor: NSColor { palette.inputActive }
    var inactiveAddressBarBackgroundColor: NSColor { palette.inputResting }

    // MARK: - Bookmarks
    var bookmarksManagerBackgroundColor: NSColor { palette.surfaceCanvas }
    var bookmarksPanelBackgroundColor: NSColor { palette.surfaceSecondary }

    // MARK: - Downloads
    var downloadsPanelBackgroundColor: NSColor { palette.surfaceSecondary }

    // MARK: - Navigation
    var navigationBackgroundColor: NSColor { palette.surfacePrimary }

    // MARK: - Passwords
    var passwordManagerBackgroundColor: NSColor { palette.surfaceSecondary }
    var passwordManagerLockScreenBackgroundColor: NSColor { palette.surfaceSecondary }

    // MARK: - Settings
    var settingsBackgroundColor: NSColor { palette.surfaceCanvas }

    // MARK: - Suggestions
    var suggestionsBackgroundColor: NSColor { palette.inputActive }
    var suggestionsTextColor: NSColor { palette.textPrimary }
    var suggestionsSuffixColor: NSColor { palette.accentTextPrimary }
    var suggestionsHighlightSuffixColor: NSColor { palette.accentTextPrimary }
    var suggestionsHighlightBackgroundColor: NSColor { palette.controlsFillPrimary }
    var suggestionsHighlightTextColor: NSColor { palette.textPrimary }

    // MARK: - Semantic
    var accentPrimaryColor: NSColor { palette.accentPrimary }
    var baseBackgroundColor: NSColor { palette.surfaceBackdrop }
    var bannerBackgroundColor: NSColor { palette.surfacePrimary }
    var buttonMouseOverColor: NSColor { palette.controlsFillPrimary }
    var buttonMouseDownColor: NSColor { palette.controlsFillSecondary }
    var buttonMouseDownPressedColor: NSColor { palette.controlsFillTertiary }
    var fillButtonBackgroundColor: NSColor { palette.controlsFillPrimary }
    var fillButtonMouseOverColor: NSColor { palette.controlsFillSecondary }
    var iconsColor: NSColor { palette.iconsPrimary }
    var popoverBackgroundColor: NSColor { palette.surfaceSecondary }
    var separatorColor: NSColor { palette.surfaceDecorationPrimary }
    var separatorActiveColor: NSColor { palette.surfaceDecorationSecondary }
    var textPrimaryColor: NSColor { palette.textPrimary }
    var textSecondaryColor: NSColor { palette.textSecondary }
    var textTertiaryColor: NSColor { palette.textTertiary }

    init(palette: ThemeColors) {
        self.palette = palette
    }
}
