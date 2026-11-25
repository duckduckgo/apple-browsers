//
//  ContextualOnboardingDialogScheduler.swift
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
import Combine
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

/// What a tab view should do with the contextual onboarding dialog it shows.
enum ContextualOnboardingDialogUpdate: Equatable {
    /// Show this dialog, replacing any dialog on screen.
    case show(ContextualDialogType)
    /// Remove the dialog on screen, if any.
    case hide
}

/// Decides when a tab view asks for a contextual onboarding dialog. One per `BrowserTabViewController`.
/// The tab view tells it what happened, keeps drawing the dialog and handling its buttons,
/// and applies the updates sent through `onUpdate`.
@MainActor
final class ContextualOnboardingDialogScheduler {

    /// Set by the tab view; receives every update the scheduler decides.
    var onUpdate: (ContextualOnboardingDialogUpdate) -> Void = { _ in }

    private let dialogProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater
    private let featureFlagger: FeatureFlagger
    private let isInPopUpWindow: () -> Bool

    /// The tab and URL of the last finished navigation, to tell a reload from a new page.
    private weak var lastTab: Tab?
    private(set) var lastURL: URL?

    /// Set when the user dismissed the dialog or switched tabs, so it isn't shown again when the window becomes key.
    private var wasDismissed = false

    static let firstDuckAIAnswerFailsafeDelay: TimeInterval = 2
    /// Runs an action after a delay; cancelling the result skips it. Injected so tests control time.
    private let runAfter: (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable
    private weak var tabWaitingForFirstDuckAIAnswer: Tab?
    private var firstDuckAIAnswerFailsafe: AnyCancellable?

    init(dialogProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater,
         featureFlagger: FeatureFlagger,
         isInPopUpWindow: @escaping () -> Bool,
         runAfter: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable = ContextualOnboardingDialogScheduler.runAfterDelay) {
        self.dialogProvider = dialogProvider
        self.featureFlagger = featureFlagger
        self.isInPopUpWindow = isInPopUpWindow
        self.runAfter = runAfter
    }

    /// A navigation finished in the tab on screen: moves onboarding forward, unless it's a reload.
    func navigationDidFinish(in tab: Tab?) {
        // A reload removes the dialog without asking for a new one.
        if tab == lastTab && tab?.url == lastURL && lastURL != nil {
            onUpdate(.hide)
            return
        }
        lastURL = tab?.url
        lastTab = tab
        stopWaitingForFirstDuckAIAnswer()
        guard canShowDialog(), let tab else {
            onUpdate(.hide)
            return
        }
        if tab.url?.isDuckAIURL == true, dialogProvider.state != .onboardingCompleted {
            onUpdate(.hide)
            waitForFirstDuckAIAnswer(in: tab)
            return
        }
        send(dialogProvider.dialogTypeForTab(tab))
    }

    /// Duck.ai's first answer arrived in the tab on screen.
    func firstDuckAIAnswerReceived() {
        // To do: pixel (dialog triggered by the first answer)
        askAfterFirstDuckAIAnswer()
    }

    /// The window became key; `displayed` is the dialog on screen, if any.
    func windowDidBecomeKey(tab: Tab?, displayed: ContextualDialogType?) {
        guard !isInPopUpWindow(), !wasDismissed, dialogProvider.state != .onboardingCompleted else { return }
        // Re-showing the same dialog would restart its typewriter animation.
        let expected = tab.flatMap { dialogProvider.lastDialogForTab($0) }
        if displayed != nil && displayed == expected { return }
        showLastDialog(in: tab)
    }

    /// The user pressed Got it. `displayed` is the dialog still on screen, if any.
    func gotItPressed(displayed: ContextualDialogType?, in tab: Tab?) {
        dialogProvider.gotItPressed()
        // Legacy dialogs are already removed here; rebranded ones hand over to the upsell when they're dismissed.
        if dialogProvider.lastDialog == .subscriptionUpsell, displayed == nil {
            showLastDialog(in: tab)
        }
    }

    /// Shows again the last dialog of this tab, without moving onboarding forward.
    /// Only the tab it was shown on gets it back, so a new window doesn't repeat it.
    private func showLastDialog(in tab: Tab?) {
        guard canShowDialog(), let tab else {
            onUpdate(.hide)
            return
        }
        send(dialogProvider.lastDialogForTab(tab))
    }

    /// The selected tab changed. Counts as dismissing the dialog.
    func selectedTabDidChange() {
        wasDismissed = true
        stopWaitingForFirstDuckAIAnswer()
    }

    /// The user dismissed `dialog`, and it's no longer on screen.
    func dialogDismissed(_ dialog: ContextualDialogType, in tab: Tab?) {
        wasDismissed = true
        // High Five hands over to the upsell in a new dialog. Both facts matter, or dismissing the upsell would show it again.
        if dialog == .highFive, dialogProvider.lastDialog == .subscriptionUpsell {
            showLastDialog(in: tab)
        }
    }

    private func waitForFirstDuckAIAnswer(in tab: Tab) {
        tabWaitingForFirstDuckAIAnswer = tab
        firstDuckAIAnswerFailsafe = runAfter(Self.firstDuckAIAnswerFailsafeDelay) { [weak self] in
            // To do: pixel (dialog triggered by the failsafe)
            self?.askAfterFirstDuckAIAnswer()
        }
    }

    private func askAfterFirstDuckAIAnswer() {
        guard let tab = tabWaitingForFirstDuckAIAnswer else { return }
        stopWaitingForFirstDuckAIAnswer()
        guard canShowDialog() else {
            onUpdate(.hide)
            return
        }
        send(dialogProvider.dialogTypeForTab(tab))
    }

    private func stopWaitingForFirstDuckAIAnswer() {
        tabWaitingForFirstDuckAIAnswer = nil
        firstDuckAIAnswerFailsafe = nil
    }

    /// Runs `action` on the main actor after `delay`; cancelling the result skips it.
    static func runAfterDelay(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        return AnyCancellable { task.cancel() }
    }

    private func canShowDialog() -> Bool {
        guard featureFlagger.isFeatureOn(.contextualOnboarding) else {
            dialogProvider.turnOffFeature()
            return false
        }
        return !isInPopUpWindow()
    }

    private func send(_ dialog: ContextualDialogType?) {
        guard let dialog else {
            onUpdate(.hide)
            return
        }
        wasDismissed = false
        onUpdate(.show(dialog))
    }
}
