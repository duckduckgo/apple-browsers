//
//  AIChatBonusFactsProvider.swift
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

import AIChat
import Foundation
import FoundationExtensions

/// The install facts Duck.ai uses to decide whether to show the bonus limit extension offer.
struct AIChatBonusFactsProvider: AIChatBonusFactsProviding {
    /// How long after install the offer can be claimed, in full days.
    static let defaultInstallWindowDays = 7

    private let installDateProvider: () -> Date?
    private let isReinstallingUserProvider: () -> Bool
    private let isAIChatEnabledProvider: () -> Bool
    private let installWindowDays: Int
    private let now: () -> Date

    /// - Parameters:
    ///   - installDateProvider: The install date, set by the first ATB request.
    ///   - isReinstallingUserProvider: Whether this install is a reinstall. It stays `true` for good once detected.
    ///   - isAIChatEnabledProvider: Whether Duck.ai is enabled.
    ///   - installWindowDays: How long after install the offer can be claimed, in full days.
    ///   - now: A date provider, injectable for tests.
    init(installDateProvider: @escaping () -> Date? = { LocalStatisticsStore().installDate },
         isReinstallingUserProvider: @escaping () -> Bool = {
             DefaultReinstallUserDetection(keyValueStore: Application.appDelegate.keyValueStore).isReinstallingUser
         },
         isAIChatEnabledProvider: @escaping () -> Bool = { DefaultAIChatPreferencesStorage().isAIFeaturesEnabled },
         installWindowDays: Int = Self.defaultInstallWindowDays,
         now: @escaping () -> Date = Date.init) {
        self.installDateProvider = installDateProvider
        self.isReinstallingUserProvider = isReinstallingUserProvider
        self.isAIChatEnabledProvider = isAIChatEnabledProvider
        self.installWindowDays = installWindowDays
        self.now = now
    }

    var isNewInstall: Bool {
        // No install date yet means the first ATB request hasn't succeeded, so the install window can't be checked.
        guard !isReinstallingUserProvider(),
              let installDate = installDateProvider(),
              let daysSinceInstall = Calendar.current.numberOfDaysBetween(installDate, and: now()) else {
            return false
        }
        return daysSinceInstall < installWindowDays
    }

    var isAIChatEnabled: Bool {
        isAIChatEnabledProvider()
    }

}
