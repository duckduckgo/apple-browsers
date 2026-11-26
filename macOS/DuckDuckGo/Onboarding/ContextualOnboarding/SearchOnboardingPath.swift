//
//  SearchOnboardingPath.swift
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
import Persistence
import PrivacyDashboard
import Subscription

/// The one value only the search path reads and writes.
protocol BlockedTrackerStoring: AnyObject {
    var blockedTrackerSeen: Bool { get set }
}

struct SearchOnboardingPathSettings: StoringKeys {
    let blockedTrackerSeen = StorageKey<Bool>(.contextualOnboardingBlockedTrackers,
                                              migrateLegacyKey: "contextual.onboarding.blocked.trackers")
}

final class SearchOnboardingPathStorage: BlockedTrackerStoring {
    private let settings: any KeyedStoring<SearchOnboardingPathSettings>

    init(settings: any KeyedStoring<SearchOnboardingPathSettings> = UserDefaults.standard.keyedStoring()) {
        self.settings = settings
    }

    var blockedTrackerSeen: Bool {
        get { settings.blockedTrackerSeen ?? false }
        set { settings.blockedTrackerSeen = newValue }
    }
}

/// Today's contextual onboarding: Try a search → search done / Try a site → trackers → Fire → the shared ending.
final class SearchOnboardingPath: ContextualOnboardingPath {

    private let progress: ContextualOnboardingProgressReading
    private let storage: BlockedTrackerStoring
    private let ending: OnboardingEndingSteps
    private let trackerMessageProvider: TrackerMessageProviding
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatPreferences: AIChatPreferencesStorage

    init(progress: ContextualOnboardingProgressReading,
         storage: BlockedTrackerStoring = SearchOnboardingPathStorage(),
         subscriptionManager: any SubscriptionManager,
         trackerMessageProvider: TrackerMessageProviding,
         aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
         aiChatPreferences: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage()) {
        self.progress = progress
        self.storage = storage
        self.ending = OnboardingEndingSteps(progress: progress, subscriptionManager: subscriptionManager)
        self.trackerMessageProvider = trackerMessageProvider
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatPreferences = aiChatPreferences
    }

    /// People who kept Duck.ai in the address bar end with Try Duck.ai instead of High Five.
    private var offersDuckAIEnding: Bool {
        guard #available(macOS 13, *) else { return false }
        return aiChatMenuConfig.shouldDisplayAnyAIChatFeature && aiChatPreferences.showSearchAndDuckAIToggle
    }

    let uiLock = UserInteractionLock.unlocked

    func reset() {
        storage.blockedTrackerSeen = false
    }

    func dialog(for tab: Tab) -> ContextualOnboardingDecision {
        // 1. After Try Duck.ai opened Duck.ai, the upsell waits for a page that isn't Duck.ai.
        if progress.hasSeen(.tryDuckAI), !progress.hasSeen(.subscriptionUpsell), tab.url?.isDuckAIURL == true { return .none }
        // 2. Once the final dialog was seen, the ending decides (upsell or completed).
        if case .decided(let decision) = ending.decisionForNextDialog() { return decision }
        // 3. Otherwise pick today's dialog for this tab, without writing anything.
        let dialog: ContextualDialogType?
        switch tab.content {
        case .newtab:
            dialog = dialogForNewTab()
        case .url(let url, _, _):
            // Check if the URL is a DuckDuckGo search.
            if url.isDuckDuckGoSearch {
                dialog = dialogForDuckDuckGoSearch()
            } else if url.isDuckDuckGo, url.path == "/l" || url.path == "/l/" {
                // The redirect a bang search goes through isn't a site visit.
                dialog = nil
            } else {
                // For website visit, decide dialog also based on the tracker type.
                let trackerType = trackerMessageProvider.trackersType(privacyInfo: tab.privacyInfo)
                dialog = dialogForRegularUrl(trackerType: trackerType, privacyInfo: tab.privacyInfo)
            }
        default:
            dialog = nil
        }
        switch dialog {
        case .highFive?: return ending.start(offeringDuckAI: offersDuckAIEnding)
        case let dialog?: return .next(dialog)
        case nil: return .none
        }
    }

    func gotItPressed(lastDialog: ContextualDialogType) -> ContextualOnboardingDecision {
        switch lastDialog {
        case .searchDone(shouldFollowUp: true):
            // The search done dialog continues in place with Try a site.
            return .next(.tryASite)
        case .trackers:
            // The trackers dialog continues in place with the Fire button, whatever its follow-up flag.
            return .next(.tryFireButton)
        case .tryFireButton:
            // Skipping Fire reaches the ending.
            return ending.start(offeringDuckAI: offersDuckAIEnding)
        default:
            return ending.gotItPressed(after: lastDialog)
        }
    }
}

// MARK: - Helpers
extension SearchOnboardingPath {
    // Determines the dialog for a new tab.
    private func dialogForNewTab() -> ContextualDialogType? {
        // If "tryASearch" has not been shown, show it.
        if !progress.hasSeen(.tryASearch) {
            return .tryASearch
        }
        // If "tryASearch" was seen and "tryASite" hasn't been shown and the "tracker" dialog hasn't been seen, show "tryASite".
        if !progress.hasSeen(.tryASite) && !progress.hasSeen(.defaultTrackers) {
            return .tryASite
        }
        // If either "tryFireButton" has been shown or the fire button was used, and "highFive" hasn't been shown,
        // and the trackers dialog has been shown, return "highFive" if not previously shown.
        if (progress.hasSeen(.tryFireButton) || progress.fireButtonUsedOnce) &&
            !progress.hasSeen(.highFive) &&
            progress.hasSeen(.defaultTrackers) {
            return .highFive
        }
        return nil
    }

    // Determines the dialog for a DuckDuckGo search URL.
    private func dialogForDuckDuckGoSearch() -> ContextualDialogType? {
        // Ensure "tryASearch" has been seen.
        guard progress.hasSeen(.tryASearch) else { return nil }
        // If the "SearchDone" hasn't been seen, choose between follow-up or non-follow-up (showing TrySiteVisit or not o gotItPressed)
        // based on whether either "tryASite" or the "trackers" has been seen.
        if !progress.hasSeen(.defaultSearchDone) {
            return (progress.hasSeen(.tryASite) || progress.hasSeen(.defaultTrackers))
            ? .searchDone(shouldFollowUp: false)
            : .searchDone(shouldFollowUp: true)
        }
        // If the fire button was used or "tryFireButton" seen, and default trackers has been seen,
        // show "highFive" if not previously shown.
        if (progress.hasSeen(.tryFireButton) || progress.fireButtonUsedOnce) &&
            progress.hasSeen(.defaultTrackers) &&
            !progress.hasSeen(.highFive) {
            return .highFive
        }
        return nil
    }

    // Determines the dialog for a website visit based on tracker type and privacy info.
    private func dialogForRegularUrl(trackerType: OnboardingTrackersType?, privacyInfo: PrivacyInfo?) -> ContextualDialogType? {
        // If "tryASearch" hasn't been seen, show it.
        if !progress.hasSeen(.tryASearch) { return .tryASearch }
        // If a blocked tracker dialog (specific tracker dialog where trackers were blocked) was not shown
        if !storage.blockedTrackerSeen {
            // If the tracker type is blocked, mark it and show a tracker dialog.
            // Decide if when the user presses got it we should show the fireButton dialog
            // (based on whether the fire button was used or related dialog shown)
            if case .blockedTrackers = trackerType {
                storage.blockedTrackerSeen = true
                let shouldFollowUp = !progress.hasSeen(.tryFireButton) && !progress.fireButtonUsedOnce
                return trackerDialog(for: privacyInfo, shouldFollowUp: shouldFollowUp)
            }
            // if the tracker dialog (for not blocked trackers e.i. major tracker no no trackers) hasn't been seen, show it.
            if !progress.hasSeen(.defaultTrackers) {
                let shouldFollowUp = !progress.hasSeen(.tryFireButton) && !progress.fireButtonUsedOnce
                return trackerDialog(for: privacyInfo, shouldFollowUp: shouldFollowUp)
            }
        }
        // If "trackers" has been seen, show "tryFireButton" if not seen before.
        if !progress.hasSeen(.tryFireButton) && progress.hasSeen(.defaultTrackers) {
            return .tryFireButton
        }
        // If "tryFireButton" and "trackers" dialogs have been seen show "highFive" if not seen before.
        if progress.hasSeen(.tryFireButton) && progress.hasSeen(.defaultTrackers) && !progress.hasSeen(.highFive) {
            return .highFive
        }
        return nil
    }

    private func trackerDialog(for privacyInfo: PrivacyInfo?, shouldFollowUp: Bool) -> ContextualDialogType? {
        guard let message = trackerMessageProvider.trackerMessage(privacyInfo: privacyInfo) else { return nil }
        return .trackers(message: message, shouldFollowUp: shouldFollowUp)
    }
}
