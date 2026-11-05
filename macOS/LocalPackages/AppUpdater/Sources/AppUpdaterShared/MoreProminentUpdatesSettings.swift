//
//  MoreProminentUpdatesSettings.swift
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
import FoundationExtensions
import PrivacyConfig

/// Remotely configurable timings for the `moreProminentUpdates` feature, read from the
/// `macOSBrowserConfig.moreProminentUpdates` subfeature settings.
///
/// Internal users read the `internal`-prefixed settings, which have shorter defaults.
/// A missing or negative value falls back to its default, and if the second prompt would come
/// before the first, both prompt timings fall back to their defaults.
public struct MoreProminentUpdatesSettings: Equatable {

    public struct Defaults {
        public let hoursUntilFirstPrompt: Double
        public let hoursUntilSecondPrompt: Double
        public let hoursUntilAppStoreUpdateAvailable: Double

        public static let external = Defaults(hoursUntilFirstPrompt: 48, hoursUntilSecondPrompt: 96, hoursUntilAppStoreUpdateAvailable: 24)
        public static let `internal` = Defaults(hoursUntilFirstPrompt: 2, hoursUntilSecondPrompt: 4, hoursUntilAppStoreUpdateAvailable: 1)
    }

    /// Time after day 0 before the first prompt shows.
    public let firstPromptDelay: TimeInterval

    /// Time after day 0 before the second prompt shows.
    public let secondPromptDelay: TimeInterval

    /// Time after an App Store release starts before the new version counts as available.
    public let appStoreUpdateAvailableDelay: TimeInterval

    public init(hoursUntilFirstPrompt: Double,
                hoursUntilSecondPrompt: Double,
                hoursUntilAppStoreUpdateAvailable: Double) {
        self.firstPromptDelay = .hours(hoursUntilFirstPrompt)
        self.secondPromptDelay = .hours(hoursUntilSecondPrompt)
        self.appStoreUpdateAvailableDelay = .hours(hoursUntilAppStoreUpdateAvailable)
    }

    public init(_ defaults: Defaults) {
        self.init(hoursUntilFirstPrompt: defaults.hoursUntilFirstPrompt,
                  hoursUntilSecondPrompt: defaults.hoursUntilSecondPrompt,
                  hoursUntilAppStoreUpdateAvailable: defaults.hoursUntilAppStoreUpdateAvailable)
    }

    public init(privacyConfig: PrivacyConfiguration, isInternalUser: Bool) {
        let settings = privacyConfig.settings(for: MacOSBrowserConfigSubfeature.moreProminentUpdates)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(RemoteSettings.self, from: $0) }

        let defaults: Defaults = isInternalUser ? .internal : .external
        let first = isInternalUser ? settings?.internalHoursUntilFirstPrompt : settings?.hoursUntilFirstPrompt
        let second = isInternalUser ? settings?.internalHoursUntilSecondPrompt : settings?.hoursUntilSecondPrompt
        let appStore = isInternalUser ? settings?.internalHoursUntilAppStoreUpdateAvailable : settings?.hoursUntilAppStoreUpdateAvailable

        var hoursUntilFirstPrompt = Self.validHours(first) ?? defaults.hoursUntilFirstPrompt
        var hoursUntilSecondPrompt = Self.validHours(second) ?? defaults.hoursUntilSecondPrompt
        if hoursUntilSecondPrompt < hoursUntilFirstPrompt {
            hoursUntilFirstPrompt = defaults.hoursUntilFirstPrompt
            hoursUntilSecondPrompt = defaults.hoursUntilSecondPrompt
        }

        self.init(hoursUntilFirstPrompt: hoursUntilFirstPrompt,
                  hoursUntilSecondPrompt: hoursUntilSecondPrompt,
                  hoursUntilAppStoreUpdateAvailable: Self.validHours(appStore) ?? defaults.hoursUntilAppStoreUpdateAvailable)
    }

    private static func validHours(_ value: Double?) -> Double? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

private extension MoreProminentUpdatesSettings {
    struct RemoteSettings: Decodable {
        let hoursUntilFirstPrompt: Double?
        let hoursUntilSecondPrompt: Double?
        let hoursUntilAppStoreUpdateAvailable: Double?
        let internalHoursUntilFirstPrompt: Double?
        let internalHoursUntilSecondPrompt: Double?
        let internalHoursUntilAppStoreUpdateAvailable: Double?
    }
}
