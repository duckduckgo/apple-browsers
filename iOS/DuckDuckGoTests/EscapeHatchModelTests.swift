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
import Core
import PrivacyConfig
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

    private func makeSUT(targetTab: Tab,
                         router: EscapeHatchActionRouter,
                         featureFlagger: FeatureFlagger = MockFeatureFlagger(),
                         lastTabShortcutAdapter: LastTabShortcutAdapter = LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore()),
                         onShortcutHidden: @escaping () -> Void = {}) -> EscapeHatchModel {
        EscapeHatchModel(
            title: "title",
            subtitle: "subtitle",
            tabType: .regular,
            domain: nil,
            targetTab: targetTab,
            tabsSource: StaticEscapeHatchTabsSource(tabs: [targetTab]),
            router: router,
            featureFlagger: featureFlagger,
            afterInactivityOptionAdapter: AfterInactivityOptionAdapter(
                initialOption: .lastUsedTab,
                keyValueStore: MockKeyValueFileStore()
            ),
            lastTabShortcutAdapter: lastTabShortcutAdapter,
            onShortcutHidden: onShortcutHidden
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

    @available(iOS 16, *)
    @Test("isFireButtonEnabled is false when the escapeHatchFireButton flag is off", .timeLimit(.minutes(1)))
    func fireButtonDisabledWhenFlagOff() {
        let sut = makeSUT(targetTab: Tab(uid: "tab"),
                          router: SpyRouter(),
                          featureFlagger: MockFeatureFlagger())

        #expect(sut.isFireButtonEnabled == false)
    }

    @available(iOS 16, *)
    @Test("isFireButtonEnabled is true when the escapeHatchFireButton flag is on", .timeLimit(.minutes(1)))
    func fireButtonEnabledWhenFlagOn() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.escapeHatchFireButton])
        let sut = makeSUT(targetTab: Tab(uid: "tab"),
                          router: SpyRouter(),
                          featureFlagger: flagger)

        #expect(sut.isFireButtonEnabled == true)
    }

    @available(iOS 16, *)
    @Test("isHideShortcutEnabled tracks the escapeHatchHideShortcut flag", .timeLimit(.minutes(1)))
    func hideShortcutEnabledTracksFlag() {
        let off = makeSUT(targetTab: Tab(uid: "tab"), router: SpyRouter(), featureFlagger: MockFeatureFlagger())
        #expect(off.isHideShortcutEnabled == false)

        let on = makeSUT(targetTab: Tab(uid: "tab"),
                         router: SpyRouter(),
                         featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.escapeHatchHideShortcut]))
        #expect(on.isHideShortcutEnabled == true)
    }

    @available(iOS 16, *)
    @Test("hideShortcut disables the setting and reports telemetry", .timeLimit(.minutes(1)))
    func hideShortcutDisablesAndReports() {
        let adapter = LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore())
        var hiddenReports = 0
        let sut = makeSUT(targetTab: Tab(uid: "tab"),
                          router: SpyRouter(),
                          featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.escapeHatchHideShortcut]),
                          lastTabShortcutAdapter: adapter,
                          onShortcutHidden: { hiddenReports += 1 })

        sut.hideShortcut()

        #expect(adapter.isEnabled == false)
        #expect(hiddenReports == 1)
    }

    @available(iOS 16, *)
    @Test("Card is hidden when the shortcut is disabled and the hide feature is available", .timeLimit(.minutes(1)))
    func cardHiddenWhenShortcutDisabled() {
        let adapter = LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore())
        let sut = makeSUT(targetTab: Tab(uid: "tab"),
                          router: SpyRouter(),
                          featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.escapeHatchHideShortcut]),
                          lastTabShortcutAdapter: adapter)

        // Target tab is present, so the card is visible while the shortcut is enabled.
        #expect(sut.isReturnToTabCardVisible == true)

        adapter.setEnabled(false)
        #expect(sut.isReturnToTabCardVisible == false)
    }

    @available(iOS 16, *)
    @Test("Shortcut is always considered enabled when the hide feature is unavailable", .timeLimit(.minutes(1)))
    func shortcutAlwaysEnabledWhenFeatureUnavailable() {
        let adapter = LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore())
        adapter.setEnabled(false)
        let sut = makeSUT(targetTab: Tab(uid: "tab"),
                          router: SpyRouter(),
                          featureFlagger: MockFeatureFlagger(),
                          lastTabShortcutAdapter: adapter)

        #expect(sut.isLastTabShortcutEnabled == true)
        #expect(sut.isReturnToTabCardVisible == true)
    }
}
