//
//  ContextualOnboardingDialogSchedulerTests.swift
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

import Combine
import FeatureFlags_macOS
import Foundation
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct ContextualOnboardingDialogSchedulerTests {

    private let provider = MockContextualOnboardingState()
    private let sent = SentUpdates()
    private let timer = FakeTimer()
    let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.contextualOnboarding.rawValue: true])

    init() {
        provider.state = .ongoing
    }

    func makeScheduler(isInPopUpWindow: Bool = false) -> ContextualOnboardingDialogScheduler {
        let scheduler = ContextualOnboardingDialogScheduler(dialogProvider: provider,
                                                            featureFlagger: featureFlagger,
                                                            isInPopUpWindow: { isInPopUpWindow },
                                                            runAfter: { [timer] in timer.runAfter($0, $1) })
        scheduler.onUpdate = { [sent] in sent.updates.append($0) }
        return scheduler
    }

    // MARK: - Navigation finished

    @available(iOS 16, macOS 13, *)
    @Test("A finished navigation shows the dialog the provider picks", .timeLimit(.minutes(1)))
    func navigationShowsNextDialog() async throws {
        provider.nextDialog = .tryASite
        let tab = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))

        makeScheduler().navigationDidFinish(in: tab)

        #expect(sent.updates == [.show(.tryASite)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished navigation with no dialog to show hides the one on screen", .timeLimit(.minutes(1)))
    func navigationWithoutDialogHides() async {
        provider.nextDialog = nil
        let tab = await Tab(content: .newtab)

        makeScheduler().navigationDidFinish(in: tab)

        #expect(sent.updates == [.hide])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Finishing the same page again in the same tab hides the dialog and asks for no new one", .timeLimit(.minutes(1)))
    func sameNavigationAgainHides() async throws {
        provider.nextDialog = .tryASite
        let tab = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: tab)
        #expect(provider.dialogTypeForTabCallCount == 1)

        scheduler.navigationDidFinish(in: tab)

        #expect(sent.updates == [.show(.tryASite), .hide])
        #expect(provider.dialogTypeForTabCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The same URL in another tab is not a reload", .timeLimit(.minutes(1)))
    func sameURLOtherTabIsNotReload() async throws {
        provider.nextDialog = .tryASite
        let url = try #require(URL(string: "https://example.com"))
        let tab = await Tab(content: .url(url, credential: nil, source: .ui))
        let otherTab = await Tab(content: .url(url, credential: nil, source: .ui))
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: tab)

        scheduler.navigationDidFinish(in: otherTab)

        #expect(sent.updates == [.show(.tryASite), .show(.tryASite)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished navigation in a pop-up window hides the dialog", .timeLimit(.minutes(1)))
    func popUpHides() async {
        provider.nextDialog = .tryASearch
        let tab = await Tab(content: .newtab)

        makeScheduler(isInPopUpWindow: true).navigationDidFinish(in: tab)

        #expect(sent.updates == [.hide])
        #expect(provider.dialogTypeForTabCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the feature flag off, the dialog is hidden and onboarding is turned off", .timeLimit(.minutes(1)))
    func flagOffTurnsOffOnboarding() async {
        featureFlagger.featuresStub[FeatureFlag.contextualOnboarding.rawValue] = false
        provider.nextDialog = .tryASearch
        let tab = await Tab(content: .newtab)

        makeScheduler().navigationDidFinish(in: tab)

        #expect(sent.updates == [.hide])
        #expect(provider.turnOffFeatureCallCount == 1)
    }

    // MARK: - High Five hands over to the upsell

    @available(iOS 16, macOS 13, *)
    @Test("Dismissing the ending shows the upsell next, without moving onboarding forward", .timeLimit(.minutes(1)),
          arguments: [ContextualDialogType.highFive, .tryDuckAI])
    func dismissingEndingShowsUpsell(ending: ContextualDialogType) async {
        provider.lastDialog = .subscriptionUpsell
        let tab = await Tab(content: .newtab)

        makeScheduler().dialogDismissed(ending, in: tab)

        #expect(sent.updates == [.show(.subscriptionUpsell)])
        #expect(provider.dialogTypeForTabCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dismissing any other dialog shows nothing, including the upsell itself", .timeLimit(.minutes(1)),
          arguments: [ContextualDialogType.subscriptionUpsell, .tryASite])
    func dismissingOtherDialogsShowsNothing(dialog: ContextualDialogType) async {
        provider.lastDialog = .subscriptionUpsell
        let tab = await Tab(content: .newtab)

        makeScheduler().dialogDismissed(dialog, in: tab)

        #expect(sent.updates.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it with nothing left on screen shows the upsell (legacy layout)", .timeLimit(.minutes(1)))
    func gotItWithNothingOnScreenShowsUpsell() async {
        provider.lastDialog = .subscriptionUpsell
        let tab = await Tab(content: .newtab)

        makeScheduler().gotItPressed(displayed: nil, in: tab)

        #expect(provider.gotItPressedCallCount == 1)
        #expect(sent.updates == [.show(.subscriptionUpsell)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Got it with High Five still on screen leaves the upsell to the dismiss (rebranded layout)", .timeLimit(.minutes(1)))
    func gotItWithHighFiveOnScreenWaitsForDismiss() async {
        provider.lastDialog = .subscriptionUpsell
        let tab = await Tab(content: .newtab)

        makeScheduler().gotItPressed(displayed: .highFive, in: tab)

        #expect(provider.gotItPressedCallCount == 1)
        #expect(sent.updates.isEmpty)
    }

    // MARK: - Window became key

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key, the last dialog of the tab comes back", .timeLimit(.minutes(1)))
    func windowKeyShowsLastDialog() async {
        provider.lastDialog = .tryASite
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates == [.show(.tryASite)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key with the same dialog on screen, it is kept", .timeLimit(.minutes(1)))
    func windowKeyKeepsSameDialog() async {
        provider.lastDialog = .tryASite
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: .tryASite)

        #expect(sent.updates.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key with an outdated dialog on screen, it is replaced", .timeLimit(.minutes(1)))
    func windowKeyReplacesOutdatedDialog() async {
        provider.lastDialog = .tryFireButton
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: .tryASite)

        #expect(sent.updates == [.show(.tryFireButton)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A dismissed dialog or a tab switch keeps the dialog away when the window becomes key", .timeLimit(.minutes(1)),
          arguments: [true, false])
    func dismissKeepsDialogAway(byTabSwitch: Bool) async {
        provider.lastDialog = .tryASite
        let tab = await Tab(content: .newtab)
        let scheduler = makeScheduler()

        if byTabSwitch {
            scheduler.selectedTabDidChange()
        } else {
            scheduler.dialogDismissed(.tryASite, in: tab)
        }

        scheduler.windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Showing a dialog again lets the window bring it back after a dismiss", .timeLimit(.minutes(1)))
    func showingResetsDismissed() async {
        provider.lastDialog = .subscriptionUpsell
        let tab = await Tab(content: .newtab)
        let scheduler = makeScheduler()

        // Dismissing High Five counts as a dismiss, then shows the upsell.
        scheduler.dialogDismissed(.highFive, in: tab)
        scheduler.windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates == [.show(.subscriptionUpsell), .show(.subscriptionUpsell)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("When onboarding is completed, the window becoming key changes nothing", .timeLimit(.minutes(1)))
    func windowKeyAfterCompletion() async {
        provider.state = .onboardingCompleted
        provider.lastDialog = .tryASite
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates.isEmpty)
    }
}

// MARK: - Waiting for Duck.ai's first answer

extension ContextualOnboardingDialogSchedulerTests {

    private func duckAITab() async throws -> Tab {
        await Tab(content: .aiChat(try #require(URL(string: "https://duck.ai/chat"))))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A Duck.ai page doesn't ask on load; it waits up to 2 seconds for the first answer", .timeLimit(.minutes(1)))
    func duckAIPageWaits() async throws {
        provider.nextDialog = .thatsDuckAI
        let tab = try await duckAITab()
        let scheduler = makeScheduler()

        scheduler.navigationDidFinish(in: tab)

        #expect(sent.updates == [.hide])
        #expect(provider.dialogTypeForTabCallCount == 0)
        #expect(timer.pendingDelays == [2])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The first answer asks once and stops the failsafe", .timeLimit(.minutes(1)))
    func firstAnswerAsksOnce() async throws {
        provider.nextDialog = .thatsDuckAI
        let tab = try await duckAITab()
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: tab)

        scheduler.firstDuckAIAnswerReceived()
        timer.fireAll()

        #expect(sent.updates == [.hide, .show(.thatsDuckAI)])
        #expect(provider.dialogTypeForTabCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without an answer, the failsafe asks", .timeLimit(.minutes(1)))
    func failsafeAsks() async throws {
        provider.nextDialog = .thatsDuckAI
        let tab = try await duckAITab()
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: tab)

        timer.fireAll()

        #expect(sent.updates == [.hide, .show(.thatsDuckAI)])
        #expect(provider.dialogTypeForTabCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An answer arriving after the failsafe asks nothing more", .timeLimit(.minutes(1)))
    func lateAnswerAfterFailsafeAsksNothing() async throws {
        provider.nextDialog = .thatsDuckAI
        let tab = try await duckAITab()
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: tab)
        timer.fireAll()

        scheduler.firstDuckAIAnswerReceived()

        #expect(sent.updates == [.hide, .show(.thatsDuckAI)])
        #expect(provider.dialogTypeForTabCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaving the Duck.ai page or switching tabs stops waiting", .timeLimit(.minutes(1)), arguments: [true, false])
    func leavingStopsWaiting(bySwitchingTabs: Bool) async throws {
        provider.nextDialog = nil
        let tab = try await duckAITab()
        let otherTab = await Tab(content: .newtab)
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: tab)

        if bySwitchingTabs {
            scheduler.selectedTabDidChange()
        } else {
            scheduler.navigationDidFinish(in: otherTab)
        }
        timer.fireAll()
        scheduler.firstDuckAIAnswerReceived()

        #expect(provider.dialogTypeForTabCallCount == (bySwitchingTabs ? 0 : 1))
        #expect(timer.pendingDelays.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once onboarding is completed, a Duck.ai page doesn't wait", .timeLimit(.minutes(1)))
    func completedOnboardingDoesNotWait() async throws {
        provider.state = .onboardingCompleted
        let tab = try await duckAITab()

        makeScheduler().navigationDidFinish(in: tab)

        #expect(provider.dialogTypeForTabCallCount == 1)
        #expect(timer.pendingDelays.isEmpty)
    }
}

/// Runs the scheduler's delayed actions only when a test says so.
private final class FakeTimer {
    private var actions: [(id: Int, delay: TimeInterval, action: @MainActor () -> Void)] = []
    private var nextID = 0

    var pendingDelays: [TimeInterval] { actions.map(\.delay) }

    func runAfter(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let id = nextID
        nextID += 1
        actions.append((id, delay, action))
        return AnyCancellable { [weak self] in self?.actions.removeAll { $0.id == id } }
    }

    @MainActor func fireAll() {
        let due = actions
        actions = []
        due.forEach { $0.action() }
    }
}

/// Collects what the scheduler sends through `onUpdate`.
private final class SentUpdates {
    var updates: [ContextualOnboardingDialogUpdate] = []
}
