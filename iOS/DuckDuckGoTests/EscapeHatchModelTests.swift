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

    /// Records the surface-attributed events the view fires through the model wrappers; all other protocol methods are no-ops.
    private final class SpyInstrumentation: NTPAfterIdleInstrumentation {
        private(set) var firedEvents: [String] = []

        func ntpShown(afterIdle: Bool) {}
        func returnToPageTapped(afterIdle: Bool) {}
        func barUsedFromNTP(afterIdle: Bool) {}
        func toggleUsedFromNTP(afterIdle: Bool) {}
        func backButtonUsedFromNTP(afterIdle: Bool) {}
        func appBackgroundedFromNTP(afterIdle: Bool) {}
        func tabSwitcherSelectedFromNTP(afterIdle: Bool) {}
        func escapeHatchTabSwitcherTapped() {}
        func escapeHatchCloseTabTapped() {}
        func escapeHatchBurnTapped(requiredConfirmation: Bool) {}
        func escapeHatchOptionChanged(to option: AfterInactivityOption) {}
        func escapeHatchHiddenFromMenu() {}
        func escapeHatchShown() { firedEvents.append("shown") }
        func escapeHatchMenuShown() { firedEvents.append("menuShown") }
        func escapeHatchReturnToTabTappedFromMenu() { firedEvents.append("returnToTabFromMenu") }
        func escapeHatchCloseTabTappedFromMenu() { firedEvents.append("closeTabFromMenu") }
        func escapeHatchBurnTappedFromMenu(requiredConfirmation: Bool) { firedEvents.append(requiredConfirmation ? "burnWithConfirmationFromMenu" : "burnImmediatelyFromMenu") }
        func escapeHatchSwipeActionPerformed() { firedEvents.append("swipe") }
        func escapeHatchBurnTappedFromButton() { firedEvents.append("burnFromButton") }
    }

    private func makeSUT(targetTab: Tab,
                         router: EscapeHatchActionRouter,
                         lastTabShortcutAdapter: LastTabShortcutAdapter = LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore()),
                         onShortcutHidden: @escaping () -> Void = {},
                         instrumentation: NTPAfterIdleInstrumentation? = nil) -> EscapeHatchModel {
        EscapeHatchModel(
            title: "title",
            subtitle: "subtitle",
            tabType: .regular,
            domain: nil,
            targetTab: targetTab,
            tabsSource: StaticEscapeHatchTabsSource(tabs: [targetTab]),
            router: router,
            afterInactivityOptionAdapter: AfterInactivityOptionAdapter(
                initialOption: .lastUsedTab,
                keyValueStore: MockKeyValueFileStore()
            ),
            lastTabShortcutAdapter: lastTabShortcutAdapter,
            onShortcutHidden: onShortcutHidden,
            instrumentation: instrumentation
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
    @Test("hideShortcut disables the setting and reports telemetry", .timeLimit(.minutes(1)))
    func hideShortcutDisablesAndReports() {
        let adapter = LastTabShortcutAdapter(keyValueStore: MockKeyValueFileStore())
        var hiddenReports = 0
        let sut = makeSUT(targetTab: Tab(uid: "tab"),
                          router: SpyRouter(),
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
                          lastTabShortcutAdapter: adapter)

        // Target tab is present, so the card is visible while the shortcut is enabled.
        #expect(sut.isReturnToTabCardVisible == true)

        adapter.setEnabled(false)
        #expect(sut.isReturnToTabCardVisible == false)
    }

    // MARK: - Surface-attributed telemetry

    @available(iOS 16, *)
    @Test("menuDidAppear fires the menu shown pixel", .timeLimit(.minutes(1)))
    func menuDidAppearFiresMenuShown() {
        let spy = SpyInstrumentation()
        let sut = makeSUT(targetTab: Tab(uid: "tab"), router: SpyRouter(), instrumentation: spy)

        sut.menuDidAppear()

        #expect(spy.firedEvents == ["menuShown"])
    }

    @available(iOS 16, *)
    @Test("closeTabFromMenu fires the menu pixel and delegates to the close action", .timeLimit(.minutes(1)))
    func closeTabFromMenuFiresPixelAndDelegates() {
        let targetTab = Tab(uid: "tab")
        let router = SpyRouter()
        let spy = SpyInstrumentation()
        let sut = makeSUT(targetTab: targetTab, router: router, instrumentation: spy)

        sut.closeTabFromMenu()

        #expect(spy.firedEvents == ["closeTabFromMenu"])
        #expect(router.closeCalls.count == 1)
        #expect(router.closeCalls.first === targetTab)
    }

    @available(iOS 16, *)
    @Test("burnImmediatelyFromMenu fires the menu pixel and delegates to the burn action", .timeLimit(.minutes(1)))
    func burnImmediatelyFromMenuFiresPixelAndDelegates() {
        let targetTab = Tab(uid: "tab")
        let router = SpyRouter()
        let spy = SpyInstrumentation()
        let sut = makeSUT(targetTab: targetTab, router: router, instrumentation: spy)

        sut.burnImmediatelyFromMenu()

        #expect(spy.firedEvents == ["burnImmediatelyFromMenu"])
        #expect(router.burnImmediatelyCalls.count == 1)
        #expect(router.burnImmediatelyCalls.first === targetTab)
    }

    @available(iOS 16, *)
    @Test("performPrimarySwipeAction fires the swipe pixel and delegates to the primary action", .timeLimit(.minutes(1)))
    func performPrimarySwipeActionFiresPixelAndDelegates() {
        let targetTab = Tab(uid: "regular-tab")
        let router = SpyRouter()
        let spy = SpyInstrumentation()
        let sut = makeSUT(targetTab: targetTab, router: router, instrumentation: spy)

        sut.performPrimarySwipeAction()

        #expect(spy.firedEvents == ["swipe"])
        #expect(router.closeCalls.count == 1)
        #expect(router.closeCalls.first === targetTab)
    }

    @available(iOS 16, *)
    @Test("burnFromButton fires the button pixel and delegates with confirmation for a regular tab", .timeLimit(.minutes(1)))
    func burnFromButtonFiresPixelAndDelegates() {
        let targetTab = Tab(uid: "regular-tab")
        let router = SpyRouter()
        let spy = SpyInstrumentation()
        let sut = makeSUT(targetTab: targetTab, router: router, instrumentation: spy)

        sut.burnFromButton(.zero)

        #expect(spy.firedEvents == ["burnFromButton"])
        #expect(router.burnImmediatelyCalls.isEmpty) // regular tab → confirmation flow, not immediate
    }
}
