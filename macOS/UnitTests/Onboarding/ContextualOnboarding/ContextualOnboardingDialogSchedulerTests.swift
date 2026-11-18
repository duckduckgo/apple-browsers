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

    private let provider = StubDialogProvider()
    private let sent = SentUpdates()
    private let timer = FakeTimer()
    let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.contextualOnboarding.rawValue: true])

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

    // MARK: - Showing the last dialog

    @available(iOS 16, macOS 13, *)
    @Test("Showing the last dialog doesn't move onboarding forward", .timeLimit(.minutes(1)))
    func showLastDialogDoesNotAdvance() async {
        provider.lastDialogForTabStub = .subscriptionUpsell
        let tab = await Tab(content: .newtab)

        makeScheduler().showLastDialog(in: tab)

        #expect(sent.updates == [.show(.subscriptionUpsell)])
        #expect(provider.dialogTypeForTabCallCount == 0)
    }

    // MARK: - Window became key

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key, the last dialog of the tab comes back", .timeLimit(.minutes(1)))
    func windowKeyShowsLastDialog() async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates == [.show(.tryASite)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key with the same dialog on screen, it is kept", .timeLimit(.minutes(1)))
    func windowKeyKeepsSameDialog() async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: .tryASite)

        #expect(sent.updates.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key with an outdated dialog on screen, it is replaced", .timeLimit(.minutes(1)))
    func windowKeyReplacesOutdatedDialog() async {
        provider.lastDialogForTabStub = .tryFireButton
        let tab = await Tab(content: .newtab)

        makeScheduler().windowDidBecomeKey(tab: tab, displayed: .tryASite)

        #expect(sent.updates == [.show(.tryFireButton)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A dismissed dialog or a tab switch keeps the dialog away when the window becomes key", .timeLimit(.minutes(1)),
          arguments: [true, false])
    func dismissKeepsDialogAway(byTabSwitch: Bool) async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)
        let scheduler = makeScheduler()

        if byTabSwitch {
            scheduler.selectedTabDidChange()
        } else {
            scheduler.dialogDismissed()
        }

        scheduler.windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Showing a dialog again lets the window bring it back after a dismiss", .timeLimit(.minutes(1)))
    func showingResetsDismissed() async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)
        let scheduler = makeScheduler()
        scheduler.dialogDismissed()

        scheduler.showLastDialog(in: tab)
        scheduler.windowDidBecomeKey(tab: tab, displayed: nil)

        #expect(sent.updates == [.show(.tryASite), .show(.tryASite)])
    }

    @available(iOS 16, macOS 13, *)
    @Test("When onboarding is completed, the window becoming key changes nothing", .timeLimit(.minutes(1)))
    func windowKeyAfterCompletion() async {
        provider.state = .onboardingCompleted
        provider.lastDialogForTabStub = .tryASite
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

        makeScheduler().navigationDidFinish(in: try await duckAITab())

        #expect(sent.updates == [.hide])
        #expect(provider.dialogTypeForTabCallCount == 0)
        #expect(timer.pendingDelays == [2])
    }

    @available(iOS 16, macOS 13, *)
    @Test("The first answer asks once and stops the failsafe", .timeLimit(.minutes(1)))
    func firstAnswerAsksOnce() async throws {
        provider.nextDialog = .thatsDuckAI
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: try await duckAITab())

        scheduler.firstAnswerReceived()
        timer.fireAll()

        #expect(sent.updates == [.hide, .show(.thatsDuckAI)])
        #expect(provider.dialogTypeForTabCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without an answer, the failsafe asks once", .timeLimit(.minutes(1)))
    func failsafeAsksOnce() async throws {
        provider.nextDialog = .thatsDuckAI
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: try await duckAITab())

        timer.fireAll()
        scheduler.firstAnswerReceived()

        #expect(sent.updates == [.hide, .show(.thatsDuckAI)])
        #expect(provider.dialogTypeForTabCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Leaving the Duck.ai page or switching tabs stops waiting", .timeLimit(.minutes(1)), arguments: [true, false])
    func leavingStopsWaiting(bySwitchingTabs: Bool) async throws {
        provider.nextDialog = nil
        let scheduler = makeScheduler()
        scheduler.navigationDidFinish(in: try await duckAITab())

        if bySwitchingTabs {
            scheduler.selectedTabDidChange()
        } else {
            scheduler.navigationDidFinish(in: await Tab(content: .newtab))
        }
        timer.fireAll()
        scheduler.firstAnswerReceived()

        #expect(provider.dialogTypeForTabCallCount == (bySwitchingTabs ? 0 : 1))
        #expect(timer.pendingDelays.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once onboarding is completed, a Duck.ai page doesn't wait", .timeLimit(.minutes(1)))
    func completedOnboardingDoesNotWait() async throws {
        provider.state = .onboardingCompleted

        makeScheduler().navigationDidFinish(in: try await duckAITab())

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

/// Keeps "next dialog" and "last dialog for this tab" apart, so tests can tell which one was asked.
private final class StubDialogProvider: ContextualOnboardingDialogTypeProviding, ContextualOnboardingStateUpdater {
    var nextDialog: ContextualDialogType?
    var lastDialogForTabStub: ContextualDialogType?
    private(set) var dialogTypeForTabCallCount = 0
    private(set) var turnOffFeatureCallCount = 0

    var lastDialog: ContextualDialogType?
    var state: ContextualOnboardingState = .ongoing
    @Published var isContextualOnboardingCompleted = false
    var isContextualOnboardingCompletedPublisher: Published<Bool>.Publisher { $isContextualOnboardingCompleted }

    func dialogTypeForTab(_ tab: Tab) -> ContextualDialogType? {
        dialogTypeForTabCallCount += 1
        return nextDialog
    }

    func lastDialogForTab(_ tab: Tab) -> ContextualDialogType? {
        lastDialogForTabStub
    }

    func gotItPressed() {}
    func fireButtonUsed() {}

    func turnOffFeature() {
        turnOffFeatureCallCount += 1
    }
}
