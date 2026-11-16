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
import Testing
@testable import DuckDuckGo_Privacy_Browser

/// The dialog rules themselves are covered through the manager in ContextualDialogsManagerTests;
/// these cover what is specific to the path: it only decides, and it hands over to the ending.
@MainActor
struct SearchOnboardingPathTests {

    let storage = MockContextualDialogStateStoring()
    let experiment = SpyOnboardingSubscriptionUpsellEnrolling()
    let trackerProvider = MockTrackerMessageProvider()
    let progress: ContextualOnboardingProgress
    let sut: SearchOnboardingPath

    init() {
        progress = ContextualOnboardingProgress(storage: storage, settings: InMemoryThrowingKeyValueStore().throwingKeyedStoring())
        sut = SearchOnboardingPath(progress: progress,
                                   storage: storage,
                                   subscriptionUpsellExperiment: experiment,
                                   trackerMessageProvider: trackerProvider)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Choosing a dialog doesn't write the seen list", .timeLimit(.minutes(1)))
    func choosingDoesNotMarkSeen() async {
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab, privacyInfo: nil) == .next(.tryASearch))
        #expect(storage.contextualDialogsSeen.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once High Five was seen, the ending decides before the tab's own rules", .timeLimit(.minutes(1)))
    func endingDecidesFirst() async {
        experiment.cohortStub = .treatment
        progress.markSeen(.highFive)
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab, privacyInfo: nil) == .next(.subscriptionUpsell))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reaching High Five starts the ending, which enrolls once", .timeLimit(.minutes(1)))
    func highFiveStartsTheEnding() async {
        progress.markSeen(.tryASearch)
        progress.markSeen(.defaultTrackers)
        progress.markSeen(.tryFireButton)
        let tab = await Tab(content: .newtab)

        #expect(sut.dialog(for: tab, privacyInfo: nil) == .next(.highFive))
        #expect(experiment.enrollCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A site with blocked trackers saves the blocked tracker flag", .timeLimit(.minutes(1)))
    func blockedTrackersAreSaved() async throws {
        progress.markSeen(.tryASearch)
        trackerProvider.trackerType = .blockedTrackers(entityNames: ["Tracker1"])
        let tab = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))

        guard case .next(.trackers(_, shouldFollowUp: true)) = sut.dialog(for: tab, privacyInfo: nil) else {
            Issue.record("Expected the trackers dialog with the Fire follow-up")
            return
        }
        #expect(storage.blockedTrackerSeen)
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
        #expect(experiment.enrollCallCount == (dialog == .tryFireButton ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it on High Five and the upsell is handled by the ending", .timeLimit(.minutes(1)))
    func gotItOnEndingDialogs() {
        experiment.cohortStub = .treatment

        #expect(sut.gotItPressed(lastDialog: .highFive) == .next(.subscriptionUpsell))
        #expect(sut.gotItPressed(lastDialog: .subscriptionUpsell) == .completed)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The search path never locks the UI", .timeLimit(.minutes(1)))
    func neverLocks() {
        #expect(!sut.isUILocked)
    }
}
