//
//  ProductSurfaceTelemetry.swift
//  DuckDuckGo
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

import PrivacyConfig

/// Product surface telemetry sends anonymous pixels about areas of the app that are being used so that we can we make future product decisions.  These pixels are not linked to any identifiable data.  The pixels are also enabled / disabled by config and we only enable them during the periods of product roadmap development in order to assist decision making.
public protocol ProductSurfaceTelemetry {

    ///  Called when the menu is used, either on new tab page or when browsing.
    func menuUsed()

    /// Daily active user indicator.
    func dailyActiveUser()

    /// Indicates the app is running on iPad.
    func iPadUsed(isPad: Bool)

    /// Indicates device is in landscape mode.
    func landscapeModeUsed()

    /// Indicates keyboard is focused (visible).
    func keyboardActive()

    /// Autocomplete surface used.
    func autocompleteUsed()

    /// Fires a pixel depending on the URL, either a search or a regular website
    func navigationCompleted(url: URL?)

    /// Duck.ai surface used.
    func duckAIUsed()

    /// Tab manager surface used.
    func tabManagerUsed()

    /// Data clearing from any source.
    func dataClearingUsed()

    /// New Tab Page surface used.
    func newTabPageUsed()

    /// Settings used (not re-fired on navigation within settings).
    func settingsUsed()

    /// Bookmarks page used.
    func bookmarksPageUsed()

    /// Passwords page used.
    func passwordsPageUsed()
}

public struct PixelProductSurfaceTelemetry: ProductSurfaceTelemetry {

    private let featureFlagger: FeatureFlagger
    private let dailyPixelFiring: DailyPixelFiring.Type

    public init(featureFlagger: FeatureFlagger, dailyPixelFiring: DailyPixelFiring.Type) {
        self.featureFlagger = featureFlagger
        self.dailyPixelFiring = dailyPixelFiring
    }

    public func menuUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageMenu, error: nil, withAdditionalParameters: [:])
    }

    public func dailyActiveUser() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDaily(.productTelemeterySurfaceUsageDAU)
    }

    public func iPadUsed(isPad: Bool) {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage),
              isPad else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageIPad, error: nil, withAdditionalParameters: [:])
    }

    public func landscapeModeUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageLandscapeMode, error: nil, withAdditionalParameters: [:])
    }

    public func keyboardActive() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageKeyboardActive, error: nil, withAdditionalParameters: [:])
    }

    public func autocompleteUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageAutocomplete, error: nil, withAdditionalParameters: [:])
    }

    public func navigationCompleted(url: URL?) {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage),
              let url else { return }

        if url.isDuckDuckGoSearch {
            dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageSERP, error: nil, withAdditionalParameters: [:])
        } else {
            // Regular DDG pages count as a websites too
            dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageWebsite, error: nil, withAdditionalParameters: [:])
        }
    }

    public func duckAIUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageDuckAI, error: nil, withAdditionalParameters: [:])
    }

    public func tabManagerUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageTabManager, error: nil, withAdditionalParameters: [:])
    }

    public func dataClearingUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageDataClearing, error: nil, withAdditionalParameters: [:])
    }

    public func newTabPageUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageNewTabPage, error: nil, withAdditionalParameters: [:])
    }

    public func settingsUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageSettings, error: nil, withAdditionalParameters: [:])
    }

    public func bookmarksPageUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsageBookmarksPage, error: nil, withAdditionalParameters: [:])
    }

    public func passwordsPageUsed() {
        guard featureFlagger.isFeatureOn(.productTelemeterySurfaceUsage) else { return }
        dailyPixelFiring.fireDailyAndCount(.productTelemeterySurfaceUsagePasswordsPage, error: nil, withAdditionalParameters: [:])
    }
}
