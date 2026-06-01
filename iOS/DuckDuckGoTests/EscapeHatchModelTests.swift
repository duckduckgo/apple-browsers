//
//  EscapeHatchModelTests.swift
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
import CoreGraphics
import Testing
import PersistenceTestingUtils
@testable import DuckDuckGo

@Suite("Escape Hatch Model")
@MainActor
struct EscapeHatchModelTests {

    private final class SpyRouter: EscapeHatchActionRouter {
        private(set) var burnImmediatelyCalls: [Tab] = []
        private(set) var closeCalls: [Tab] = []
        private(set) var openingScreenOptionChanges: [AfterInactivityOption] = []

        func escapeHatchDidRequestSwitch(to tab: Tab) {}
        func escapeHatchDidRequestClose(_ tab: Tab) { closeCalls.append(tab) }
        func escapeHatchDidRequestBurnWithConfirmation(_ tab: Tab, sourceRect: CGRect) {}
        func escapeHatchDidRequestTabSwitcher() {}

        func escapeHatchDidRequestBurnImmediately(_ tab: Tab) {
            burnImmediatelyCalls.append(tab)
        }

        func escapeHatchDidChangeOpeningScreenOption(to option: AfterInactivityOption) {
            openingScreenOptionChanges.append(option)
        }
    }

    private func makeSUT(targetTab: Tab, router: EscapeHatchActionRouter) -> EscapeHatchModel {
        EscapeHatchModel(
            title: "title",
            subtitle: "subtitle",
            tabType: .regular,
            domain: nil,
            targetTab: targetTab,
            tabsSource: StaticEscapeHatchTabsSource(tabs: [targetTab]),
            router: router,
            featureFlagger: MockFeatureFlagger(),
            afterInactivityOptionAdapter: AfterInactivityOptionAdapter(
                initialOption: .lastUsedTab,
                keyValueStore: MockKeyValueFileStore()
            )
        )
    }

    @available(iOS 16, *)
    @Test("Convenience init wires onBurnTabImmediately to the router's no-confirmation method", .timeLimit(.minutes(1)))
    func convenienceInitWiresBurnImmediatelyClosure() {
        let targetTab = Tab(uid: "target-tab")
        let router = SpyRouter()
        let sut = makeSUT(targetTab: targetTab, router: router)

        sut.onBurnTabImmediately()

        #expect(router.burnImmediatelyCalls.count == 1)
        #expect(router.burnImmediatelyCalls.first === targetTab)
    }

    @available(iOS 16, *)
    @Test("primarySwipeAction for a fire tab burns immediately with the burn label", .timeLimit(.minutes(1)))
    func primarySwipeActionForFireTabBurnsImmediately() {
        let targetTab = Tab(fireTab: true)
        let router = SpyRouter()
        let sut = makeSUT(targetTab: targetTab, router: router)

        sut.primarySwipeAction.perform()

        #expect(sut.primarySwipeAction.label == UserText.escapeHatchMenuDeleteTab)
        #expect(router.burnImmediatelyCalls.count == 1)
        #expect(router.burnImmediatelyCalls.first === targetTab)
        #expect(router.closeCalls.isEmpty)
    }

    @available(iOS 16, *)
    @Test("primarySwipeAction for a regular tab closes with the close label", .timeLimit(.minutes(1)))
    func primarySwipeActionForRegularTabCloses() {
        let targetTab = Tab(uid: "regular-tab")
        let router = SpyRouter()
        let sut = makeSUT(targetTab: targetTab, router: router)

        sut.primarySwipeAction.perform()

        #expect(sut.primarySwipeAction.label == UserText.escapeHatchMenuCloseTab)
        #expect(router.closeCalls.count == 1)
        #expect(router.closeCalls.first === targetTab)
        #expect(router.burnImmediatelyCalls.isEmpty)
    }
}
