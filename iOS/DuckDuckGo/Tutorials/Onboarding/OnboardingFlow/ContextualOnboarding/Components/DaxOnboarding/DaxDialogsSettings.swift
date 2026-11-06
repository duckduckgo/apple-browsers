//
//  DaxDialogsSettings.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Core
import CoreFoundation
import FeatureFlags_iOS
import Foundation
import Onboarding
import Persistence
import PrivacyConfig

protocol DaxDialogsSettings: AnyObject {

    var isDismissed: Bool { get set }

    // Used to understand if users completed the old onboarding flow and should not be prompted in-context dax dialogs.
    var homeScreenMessagesSeen: Int { get }

    var tryAnonymousSearchShown: Bool { get set }

    var tryVisitASiteShown: Bool { get set }

    var browsingAfterSearchShown: Bool { get set }
    
    var browsingWithTrackersShown: Bool { get set }
    
    var browsingWithoutTrackersShown: Bool { get set }
    
    var browsingMajorTrackingSiteShown: Bool { get set }
    
    var fireButtonEducationShownOrExpired: Bool { get set }

    var fireMessageExperimentShown: Bool { get set }

    var fireButtonPulseDateShown: Date? { get set }

    var privacyButtonPulseShown: Bool { get set }

    var browsingFinalDialogShown: Bool { get set }

    var subscriptionPromotionDialogShown: Bool { get set }

    /// Whether the user has seen the "try visiting a site" dialog in the chat-first (Duck.ai) onboarding path.
    var chatPathVisitSiteSeen: Bool { get set }

    /// Whether the user entered the Duck.ai chat-first onboarding path.
    /// Set when the user completes the fire-education step in the Duck.ai fire onboarding flow.
    var isChatFirstPath: Bool { get set }

    /// The current phase of the Duck.ai chat-first onboarding path, derived from persisted state flags.
    var chatPathPhase: DaxDialogs.ChatPathPhase { get }

}

final class ContextualOnboardingTimeLimit {
    private enum Key {
        static let startDate = "com.duckduckgo.ios.contextualOnboardingStartDate"
        static let appOpens = "com.duckduckgo.ios.contextualOnboardingAppOpens"
        static let ended = "com.duckduckgo.ios.contextualOnboardingEndedByTimeLimit"
        static let maxDaysOverride = "com.duckduckgo.ios.contextualOnboardingMaxDaysOverride"
        static let maxAppOpensOverride = "com.duckduckgo.ios.contextualOnboardingMaxAppOpensOverride"
    }

    private let store: KeyValueStoring
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let statisticsStore: StatisticsStore
    private let launchOptionsHandler: LaunchOptionsHandler
    private let dateProvider: () -> Date

    init(store: KeyValueStoring = UserDefaults.app,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         statisticsStore: StatisticsStore = StatisticsUserDefaults(),
         launchOptionsHandler: LaunchOptionsHandler = LaunchOptionsHandler(),
         dateProvider: @escaping () -> Date = Date.init) {
        self.store = store
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.statisticsStore = statisticsStore
        self.launchOptionsHandler = launchOptionsHandler
        self.dateProvider = dateProvider
    }

    var startDate: Date {
        get {
            if let override = launchOptionsHandler.contextualOnboardingStartDate { return override }
            if let stored = try? store.object(forKey: Key.startDate) as? Date { return stored }
            let date = statisticsStore.installDate ?? dateProvider()
            try? store.set(date, forKey: Key.startDate)
            return date
        }
        set { try? store.set(newValue, forKey: Key.startDate) }
    }

    var appOpens: Int {
        get { (try? store.object(forKey: Key.appOpens) as? Int) ?? 0 }
        set { try? store.set(newValue, forKey: Key.appOpens) }
    }

    var endedByTimeLimit: Bool {
        get { (try? store.object(forKey: Key.ended) as? Bool) ?? false }
        set { try? store.set(newValue, forKey: Key.ended) }
    }

    var maxDaysOverride: Int? {
        get { try? store.object(forKey: Key.maxDaysOverride) as? Int }
        set { try? store.set(newValue, forKey: Key.maxDaysOverride) }
    }

    var maxAppOpensOverride: Int? {
        get { try? store.object(forKey: Key.maxAppOpensOverride) as? Int }
        set { try? store.set(newValue, forKey: Key.maxAppOpensOverride) }
    }

    var maxDaysSinceInstall: Int {
        positive(launchOptionsHandler.contextualOnboardingMaxDays)
            ?? positive(maxDaysOverride)
            ?? remoteLimit(for: "maxDaysSinceInstall")
            ?? 7
    }

    var maxAppOpens: Int {
        positive(launchOptionsHandler.contextualOnboardingMaxAppOpens)
            ?? positive(maxAppOpensOverride)
            ?? remoteLimit(for: "maxAppOpens")
            ?? 28
    }

    func recordAppOpen() {
        _ = startDate
        if appOpens < Int.max { appOpens += 1 }
    }

    func reachedLimit() -> OnboardingSharedPixelEvent.TimeLimitReason? {
        let start = startDate
        guard !endedByTimeLimit,
              featureFlagger.isFeatureOn(for: FeatureFlag.contextualOnboardingTimeLimit) else { return nil }
        if dateProvider().timeIntervalSince(start) >= Double(maxDaysSinceInstall) * 24 * 60 * 60 {
            return .days
        }
        if appOpens > maxAppOpens { return .appOpens }
        return nil
    }

    func reset() {
        startDate = dateProvider()
        appOpens = 0
        endedByTimeLimit = false
    }

    func clear() {
        for key in [Key.startDate, Key.appOpens, Key.ended, Key.maxDaysOverride, Key.maxAppOpensOverride] {
            try? store.removeObject(forKey: key)
        }
    }

    private func positive(_ value: Int?) -> Int? {
        value.flatMap { $0 > 0 ? $0 : nil }
    }

    private func remoteLimit(for key: String) -> Int? {
        guard let json = privacyConfigurationManager.privacyConfig.settings(for: ContextualOnboardingSubfeature.timeLimit),
              let data = json.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = dictionary[key] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value > 0, value.rounded(.towardZero) == value, value < Double(Int.max) else { return nil }
        return Int(value)
    }
}

class DefaultDaxDialogsSettings: DaxDialogsSettings {
    
    @UserDefaultsWrapper(key: .daxIsDismissed, defaultValue: true)
    var isDismissed: Bool
    
    @UserDefaultsWrapper(key: .daxHomeScreenMessagesSeen, defaultValue: 0)
    var homeScreenMessagesSeen: Int

    @UserDefaultsWrapper(key: .daxTryAnonymousSearchShown, defaultValue: false)
    var tryAnonymousSearchShown: Bool

    @UserDefaultsWrapper(key: .daxTryVisitSiteShown, defaultValue: false)
    var tryVisitASiteShown: Bool

    @UserDefaultsWrapper(key: .daxBrowsingAfterSearchShown, defaultValue: false)
    var browsingAfterSearchShown: Bool
    
    @UserDefaultsWrapper(key: .daxBrowsingWithTrackersShown, defaultValue: false)
    var browsingWithTrackersShown: Bool
    
    @UserDefaultsWrapper(key: .daxBrowsingWithoutTrackersShown, defaultValue: false)
    var browsingWithoutTrackersShown: Bool
    
    @UserDefaultsWrapper(key: .daxBrowsingMajorTrackingSiteShown, defaultValue: false)
    var browsingMajorTrackingSiteShown: Bool
    
    @UserDefaultsWrapper(key: .daxFireButtonEducationShownOrExpired, defaultValue: false)
    var fireButtonEducationShownOrExpired: Bool

    @UserDefaultsWrapper(key: .daxFireMessageExperimentShown, defaultValue: false)
    var fireMessageExperimentShown: Bool

    @UserDefaultsWrapper(key: .fireButtonPulseDateShown, defaultValue: nil)
    var fireButtonPulseDateShown: Date?

    @UserDefaultsWrapper(key: .privacyButtonPulseShown, defaultValue: false)
    var privacyButtonPulseShown: Bool

    @UserDefaultsWrapper(key: .daxBrowsingFinalDialogShown, defaultValue: false)
    var browsingFinalDialogShown: Bool

    @UserDefaultsWrapper(key: .daxSubscriptionPromotionDialogShown, defaultValue: false)
    var subscriptionPromotionDialogShown: Bool

    // Stored via KeyValueStoring (not @UserDefaultsWrapper) to comply with deprecation policy.
    // Keys preserved from the original UserDefaultsKey enum values.
    private enum ChatPathKey {
        static let visitSiteSeen = "com.duckduckgo.ios.daxOnboardingChatPathVisitSiteSeen"
        static let isChatFirstPath = "com.duckduckgo.ios.daxOnboardingIsChatFirstPath"
    }

    private let chatPathStore: KeyValueStoring = UserDefaults.standard

    var chatPathVisitSiteSeen: Bool {
        get { (try? chatPathStore.object(forKey: ChatPathKey.visitSiteSeen) as? Bool) ?? false }
        set { try? chatPathStore.set(newValue, forKey: ChatPathKey.visitSiteSeen) }
    }

    var isChatFirstPath: Bool {
        get { (try? chatPathStore.object(forKey: ChatPathKey.isChatFirstPath) as? Bool) ?? false }
        set { try? chatPathStore.set(newValue, forKey: ChatPathKey.isChatFirstPath) }
    }

    var chatPathPhase: DaxDialogs.ChatPathPhase {
        guard isChatFirstPath && fireMessageExperimentShown else { return .none }
        if !chatPathVisitSiteSeen { return .visitSite }
        // Require the user to have actually browsed a non-DDG site and seen a tracker dialog before
        // advancing to .trackerToEOJ; without this guard, the phase would jump to .trackerToEOJ the
        // moment the "try visiting a site" NTP dialog appears (via onFirstAppear), triggering the
        // "You've got this" EOJ before the user has visited any site.
        let seenBrowsingDialog = browsingWithTrackersShown || browsingWithoutTrackersShown || browsingMajorTrackingSiteShown
        guard seenBrowsingDialog else { return .visitSite }
        if !browsingFinalDialogShown { return .trackerToEOJ }
        return .none
    }
}
