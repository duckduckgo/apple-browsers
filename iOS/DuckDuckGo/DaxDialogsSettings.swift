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

import Core
import Persistence

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
    /// Set when the user completes the fire-education step in the Duck.ai experiment flow.
    var isChatFirstPath: Bool { get set }

    /// The current phase of the Duck.ai chat-first onboarding path, derived from persisted state flags.
    var chatPathPhase: DaxDialogs.ChatPathPhase { get }
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
