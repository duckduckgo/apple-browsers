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
import PrivacyDashboard
import Testing
@testable import DuckDuckGo_Privacy_Browser

@MainActor
struct ContextualOnboardingDialogSchedulerTests {

    private let provider = StubDialogProvider()
    let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.contextualOnboarding.rawValue: true])

    func makeScheduler(isInPopUpWindow: Bool = false) -> ContextualOnboardingDialogScheduler {
        ContextualOnboardingDialogScheduler(dialogProvider: provider,
                                            featureFlagger: featureFlagger,
                                            isInPopUpWindow: { isInPopUpWindow })
    }

    // MARK: - Navigation finished

    @available(iOS 16, macOS 13, *)
    @Test("A finished navigation shows the dialog the provider picks", .timeLimit(.minutes(1)))
    func navigationShowsNextDialog() async throws {
        provider.nextDialog = .tryASite
        let tab = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))

        #expect(makeScheduler().navigationDidFinish(in: tab) == .show(.tryASite))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished navigation with no dialog to show hides the one on screen", .timeLimit(.minutes(1)))
    func navigationWithoutDialogHides() async {
        provider.nextDialog = nil
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().navigationDidFinish(in: tab) == .hide)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Finishing the same page again in the same tab hides the dialog and asks for no new one", .timeLimit(.minutes(1)))
    func sameNavigationAgainHides() async throws {
        provider.nextDialog = .tryASite
        let tab = await Tab(content: .url(try #require(URL(string: "https://example.com")), credential: nil, source: .ui))
        let scheduler = makeScheduler()
        _ = scheduler.navigationDidFinish(in: tab)
        #expect(provider.dialogTypeForTabCallCount == 1)

        #expect(scheduler.navigationDidFinish(in: tab) == .hide)
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
        _ = scheduler.navigationDidFinish(in: tab)

        #expect(scheduler.navigationDidFinish(in: otherTab) == .show(.tryASite))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished navigation in a pop-up window hides the dialog", .timeLimit(.minutes(1)))
    func popUpHides() async {
        provider.nextDialog = .tryASearch
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler(isInPopUpWindow: true).navigationDidFinish(in: tab) == .hide)
        #expect(provider.dialogTypeForTabCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With the feature flag off, the dialog is hidden and onboarding is turned off", .timeLimit(.minutes(1)))
    func flagOffTurnsOffOnboarding() async {
        featureFlagger.featuresStub[FeatureFlag.contextualOnboarding.rawValue] = false
        provider.nextDialog = .tryASearch
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().navigationDidFinish(in: tab) == .hide)
        #expect(provider.turnOffFeatureCallCount == 1)
    }

    // MARK: - Showing the last dialog

    @available(iOS 16, macOS 13, *)
    @Test("Showing the last dialog doesn't move onboarding forward", .timeLimit(.minutes(1)))
    func showLastDialogDoesNotAdvance() async {
        provider.lastDialogForTabStub = .subscriptionUpsell
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().showLastDialog(in: tab) == .show(.subscriptionUpsell))
        #expect(provider.dialogTypeForTabCallCount == 0)
    }

    // MARK: - Window became key

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key, the last dialog of the tab comes back", .timeLimit(.minutes(1)))
    func windowKeyShowsLastDialog() async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().windowDidBecomeKey(tab: tab, displayed: nil) == .show(.tryASite))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key with the same dialog on screen, it is kept", .timeLimit(.minutes(1)))
    func windowKeyKeepsSameDialog() async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().windowDidBecomeKey(tab: tab, displayed: .tryASite) == .keep)
    }

    @available(iOS 16, macOS 13, *)
    @Test("When the window becomes key with an outdated dialog on screen, it is replaced", .timeLimit(.minutes(1)))
    func windowKeyReplacesOutdatedDialog() async {
        provider.lastDialogForTabStub = .tryFireButton
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().windowDidBecomeKey(tab: tab, displayed: .tryASite) == .show(.tryFireButton))
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

        #expect(scheduler.windowDidBecomeKey(tab: tab, displayed: nil) == .keep)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Showing a dialog again lets the window bring it back after a dismiss", .timeLimit(.minutes(1)))
    func showingResetsDismissed() async {
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)
        let scheduler = makeScheduler()
        scheduler.dialogDismissed()

        _ = scheduler.showLastDialog(in: tab)

        #expect(scheduler.windowDidBecomeKey(tab: tab, displayed: nil) == .show(.tryASite))
    }

    @available(iOS 16, macOS 13, *)
    @Test("When onboarding is completed, the window becoming key changes nothing", .timeLimit(.minutes(1)))
    func windowKeyAfterCompletion() async {
        provider.state = .onboardingCompleted
        provider.lastDialogForTabStub = .tryASite
        let tab = await Tab(content: .newtab)

        #expect(makeScheduler().windowDidBecomeKey(tab: tab, displayed: nil) == .keep)
    }
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

    func dialogTypeForTab(_ tab: Tab, privacyInfo: PrivacyInfo?) -> ContextualDialogType? {
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
