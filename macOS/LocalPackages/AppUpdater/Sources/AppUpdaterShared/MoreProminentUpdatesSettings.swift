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
import PrivacyConfig

/// Remotely configurable prompt thresholds for the `moreProminentUpdates` feature, read from the
/// `macOSBrowserConfig.moreProminentUpdates` subfeature settings.
///
/// Each value falls back to its default when the setting is missing or invalid.
public struct MoreProminentUpdatesSettings: Equatable {

    public static let defaultDaysUntilFirstPrompt = 2
    public static let defaultDaysUntilSecondPrompt = 4
    public static let defaultVersionsBehindBeforePrompt = 1

    /// Days after a new version becomes available before the first prompt shows.
    public let daysUntilFirstPrompt: Int

    /// Days after a new version becomes available before the second prompt shows.
    public let daysUntilSecondPrompt: Int

    /// Number of versions behind the latest release before prompting.
    public let versionsBehindBeforePrompt: Int

    public init(daysUntilFirstPrompt: Int = Self.defaultDaysUntilFirstPrompt,
                daysUntilSecondPrompt: Int = Self.defaultDaysUntilSecondPrompt,
                versionsBehindBeforePrompt: Int = Self.defaultVersionsBehindBeforePrompt) {
        self.daysUntilFirstPrompt = daysUntilFirstPrompt
        self.daysUntilSecondPrompt = daysUntilSecondPrompt
        self.versionsBehindBeforePrompt = versionsBehindBeforePrompt
    }

    public init(privacyConfig: PrivacyConfiguration) {
        let settings = privacyConfig.settings(for: MacOSBrowserConfigSubfeature.moreProminentUpdates)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(RemoteSettings.self, from: $0) }

        self.init(daysUntilFirstPrompt: Self.validThreshold(settings?.daysUntilFirstPrompt) ?? Self.defaultDaysUntilFirstPrompt,
                  daysUntilSecondPrompt: Self.validThreshold(settings?.daysUntilSecondPrompt) ?? Self.defaultDaysUntilSecondPrompt,
                  versionsBehindBeforePrompt: Self.validThreshold(settings?.versionsBehindBeforePrompt) ?? Self.defaultVersionsBehindBeforePrompt)
    }

    private static func validThreshold(_ value: Int?) -> Int? {
        guard let value, value >= 0 else { return nil }
        return value
    }
}

private extension MoreProminentUpdatesSettings {
    struct RemoteSettings: Decodable {
        let daysUntilFirstPrompt: Int?
        let daysUntilSecondPrompt: Int?
        let versionsBehindBeforePrompt: Int?
    }
}
