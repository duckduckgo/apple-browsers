//
//  SearchOnboardingPathTests.swift
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
@_spi(Testing) import Persistence
import SubscriptionTestingUtilities
import Testing
@testable import DuckDuckGo_Privacy_Browser

/// The dialog rules themselves are covered through the manager in ContextualDialogsManagerTests;
/// these cover what is specific to the path: it only decides, and it hands over to the ending.
@MainActor
struct SearchOnboardingPathTests {

    let storage = MockContextualDialogStateStoring()
    let pathStorage = MockBlockedTrackerStoring()
    let subscriptionManager = SubscriptionManagerMock.notUpsellEligible()
    let trackerProvider = MockTrackerMessageProvider()
    let progress: ContextualOnboardingProgress
    let sut: SearchOnboardingPath

    init() {
        progress = ContextualOnboardingProgress(storage: storage, settings: InMemoryThrowingKeyValueStore().throwingKeyedStoring())
        sut = SearchOnboardingPath(progress: progress,
                                   storage: pathStorage,
                                   subscriptionManager: subscriptionManager,
                                   trackerMessageProvider: trackerProvider,
                                   aiChatMenuConfig: MockAIChatConfig())
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing a dialog doesn't write the seen list", .timeLimit(.minutes(1)))
    func choosingDoesNotMarkSeen() async {
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab) == .next(.tryASearch))
        #expect(storage.contextualDialogsSeen.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once High Five was seen, the ending decides before the tab's own rules", .timeLimit(.minutes(1)))
    func endingDecidesFirst() async {
        subscriptionManager.hasAppStoreProductsAvailable = true
        progress.markSeen(.highFive)
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab) == .next(.subscriptionUpsell))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reaching High Five starts the ending", .timeLimit(.minutes(1)))
    func highFiveStartsTheEnding() async {
        progress.markSeen(.tryASearch)
        progress.markSeen(.defaultTrackers)
        progress.markSeen(.tryFireButton)
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab) == .next(.highFive))
    }

    @available(iOS 16, macOS 13, *)
    @Test("After Try Duck.ai, the upsell waits for a page that isn't Duck.ai", .timeLimit(.minutes(1)))
    func upsellWaitsForAPageThatIsNotDuckAI() async throws {
        subscriptionManager.hasAppStoreProductsAvailable = true
        progress.markSeen(.tryDuckAI)
        let duckAITab = await Tab(content: .aiChat(try #require(URL(string: "https://duck.ai/chat"))))
        let newTab = await Tab(content: .newtab)

        #expect(sut.dialog(for: duckAITab) == .none)
        #expect(sut.dialog(for: newTab) == .next(.subscriptionUpsell))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only people who kept Duck.ai in the address bar end with Try Duck.ai", .timeLimit(.minutes(1)),
          arguments: [(true, true, ContextualDialogType.tryDuckAI),
                      (false, true, .highFive),
                      (true, false, .highFive)])
    func duckAIEnding(keptDuckAIToggle: Bool, isDuckAIAvailable: Bool, expected: ContextualDialogType) async {
        let aiChatMenuConfig = MockAIChatConfig()
        aiChatMenuConfig.shouldDisplayAnyAIChatFeature = isDuckAIAvailable
        let aiChatPreferences = MockAIChatPreferencesStorage()
        aiChatPreferences.showSearchAndDuckAIToggle = keptDuckAIToggle
        let sut = SearchOnboardingPath(progress: progress,
                                       storage: pathStorage,
                                       subscriptionManager: subscriptionManager,
                                       trackerMessageProvider: trackerProvider,
                                       aiChatMenuConfig: aiChatMenuConfig,
                                       aiChatPreferences: aiChatPreferences)
        progress.markSeen(.tryASearch)
        progress.markSeen(.defaultTrackers)
        progress.markSeen(.tryFireButton)
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab) == .next(expected))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A site with blocked trackers saves the blocked tracker flag", .timeLimit(.minutes(1)))
    func blockedTrackersAreSaved() async throws {
        progress.markSeen(.tryASearch)
        trackerProvider.trackerType = .blockedTrackers(entityNames: ["Tracker1"])
        let tab = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))

        guard case .next(.trackers(_, shouldFollowUp: true)) = sut.dialog(for: tab) else {
            Issue.record("Expected the trackers dialog with the Fire follow-up")
            return
        }
        #expect(pathStorage.blockedTrackerSeen)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reset clears the blocked tracker flag", .timeLimit(.minutes(1)))
    func resetClearsBlockedTrackers() {
        pathStorage.blockedTrackerSeen = true

        sut.reset()

        #expect(!pathStorage.blockedTrackerSeen)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The blocked tracker flag saved under the old key is kept and moved to the new key", .timeLimit(.minutes(1)))
    func blockedTrackersLegacyKeyIsMigrated() throws {
        let store = InMemoryKeyValueStore()
        store.set(true, forKey: "contextual.onboarding.blocked.trackers")
        let storage = SearchOnboardingPathStorage(settings: store.keyedStoring())

        #expect(storage.blockedTrackerSeen)
        #expect(store.object(forKey: "contextual-onboarding_blocked-trackers") as? Bool == true)
        #expect(store.object(forKey: "contextual.onboarding.blocked.trackers") == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it continues with the in-place follow-up or the ending", .timeLimit(.minutes(1)),
          arguments: [
            (ContextualDialogType.searchDone(shouldFollowUp: true), ContextualOnboardingDecision.next(.tryASite)),
            (.searchDone(shouldFollowUp: false), .none),
            (.trackers(message: NSAttributedString(), shouldFollowUp: true), .next(.tryFireButton)),
            (.trackers(message: NSAttributedString(), shouldFollowUp: false), .next(.tryFireButton)),
            (.tryFireButton, .next(.highFive)),
            (.tryASearch, .none)
          ])
    func gotIt(dialog: ContextualDialogType, expected: ContextualOnboardingDecision) {
        #expect(sut.gotItPressed(lastDialog: dialog) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it on High Five and the upsell is handled by the ending", .timeLimit(.minutes(1)))
    func gotItOnEndingDialogs() {
        subscriptionManager.hasAppStoreProductsAvailable = true

        #expect(sut.gotItPressed(lastDialog: .highFive) == .next(.subscriptionUpsell))
        #expect(sut.gotItPressed(lastDialog: .subscriptionUpsell) == .completed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The search path never locks the UI", .timeLimit(.minutes(1)))
    func neverLocks() {
        #expect(sut.uiLock == .unlocked)
    }
}
