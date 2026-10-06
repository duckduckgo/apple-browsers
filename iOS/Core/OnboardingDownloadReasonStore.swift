//
//  OnboardingDownloadReasonStore.swift
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

import Foundation

/// Core-visible reader for the onboarding download reason the user selected.
///
/// The value is persisted by the app layer (`DefaultTutorialSettings`) as the reason's raw value in
/// `UserDefaults.app`. This store owns the storage key so the app (writer) and Core consumers (e.g.
/// `StatisticsLoader`, which fires the per-reason retention experiment pixels) share a single source of
/// truth without Core having to depend on the `Onboarding` module.
public enum OnboardingDownloadReasonStore {
    public static let key = "com.duckduckgo.tutorials.onboardingDownloadReason"

    /// The pixel token for the selected download reason (e.g. `"search"`, `"ad-blocking"`), or `nil` if none.
    public static func currentPixelToken(_ userDefaults: UserDefaults = .app) -> String? {
        userDefaults.string(forKey: key).flatMap(pixelToken(forRawValue:))
    }

    /// Maps a persisted `OnboardingDownloadReason` raw value to its pixel token.
    ///
    /// Kept here (keyed on the raw value) so Core stays free of the `Onboarding` module — importing it
    /// would invert the Core → Onboarding layering. Mirrors the download-reason tokens in the Onboarding
    /// pixel layer (`DownloadChoiceEvent.Value`); keep them in sync while the experiment is live.
    private static func pixelToken(forRawValue rawValue: String) -> String? {
        switch rawValue {
        case "browserPrivately": "search"
        case "privateAIChat": "ai-chat"
        case "noAI": "no-ai"
        case "blockAds": "ad-blocking"
        default: nil
        }
    }
}
