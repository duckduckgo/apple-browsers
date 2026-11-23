//
//  DuckAIOnboardingPathTests.swift
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

@MainActor
struct DuckAIOnboardingPathTests {

    let subscriptionManager = SubscriptionManagerMock.notUpsellEligible()
    let progress = ContextualOnboardingProgress(storage: MockContextualDialogStateStoring(),
                                                settings: InMemoryThrowingKeyValueStore().throwingKeyedStoring())
    let sut: DuckAIOnboardingPath

    init() {
        sut = DuckAIOnboardingPath(progress: progress, subscriptionManager: subscriptionManager)
    }

    private func duckAITab() async throws -> Tab {
        await Tab(content: .aiChat(try #require(URL(string: "https://duck.ai/chat"))))
    }

    @available(iOS 16, macOS 13, *)
    @Test("The Duck.ai tab gets That's Duck.ai!", .timeLimit(.minutes(1)))
    func duckAITabShowsThatsDuckAI() async throws {
        #expect(sut.dialog(for: try await duckAITab()) == .next(.thatsDuckAI))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Before That's Duck.ai!, other tabs get nothing", .timeLimit(.minutes(1)))
    func otherTabsBeforeThatsDuckAIGetNothing() async throws {
        let site = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))
        let newTab = await Tab(content: .newtab)

        #expect(sut.dialog(for: site) == ContextualOnboardingDecision.none)
        #expect(sut.dialog(for: newTab) == ContextualOnboardingDecision.none)
    }

    @available(iOS 16, macOS 13, *)
    @Test("After That's Duck.ai!, the next page starts the ending, whatever it is", .timeLimit(.minutes(1)),
          arguments: ["newtab", "site", "duckai"])
    func nextPageAfterThatsDuckAIStartsEnding(page: String) async throws {
        progress.markSeen(.thatsDuckAI)
        let site = try #require(URL(string: "https://example.com"))
        let tab: Tab
        switch page {
        case "newtab": tab = await Tab(content: .newtab)
        case "site": tab = await Tab(content: .url(site, credential: nil, source: .ui))
        default: tab = try await duckAITab()
        }

        #expect(sut.dialog(for: tab) == .next(.highFive))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once High Five was seen, the ending decides", .timeLimit(.minutes(1)))
    func endingDecidesAfterHighFive() async {
        subscriptionManager.hasAppStoreProductsAvailable = true
        progress.markSeen(.thatsDuckAI)
        progress.markSeen(.highFive)
        let newTab = await Tab(content: .newtab)

        #expect(sut.dialog(for: newTab) == .next(.subscriptionUpsell))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Only Fire is usable until Fire is used", .timeLimit(.minutes(1)))
    func uiLockedExceptFireUntilFire() {
        #expect(sut.uiLock == .locked(except: [.fire]))

        progress.fireButtonUsedOnce = true

        #expect(sut.uiLock == .unlocked)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it is handled by the ending; That's Duck.ai! has nothing after it", .timeLimit(.minutes(1)))
    func gotIt() {
        subscriptionManager.hasAppStoreProductsAvailable = true

        #expect(sut.gotItPressed(lastDialog: .thatsDuckAI) == ContextualOnboardingDecision.none)
        #expect(sut.gotItPressed(lastDialog: .highFive) == .next(.subscriptionUpsell))
        #expect(sut.gotItPressed(lastDialog: .subscriptionUpsell) == .completed)
    }
}
