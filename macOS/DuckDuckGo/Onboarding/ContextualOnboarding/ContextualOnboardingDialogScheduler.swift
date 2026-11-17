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

import FeatureFlags_macOS
import Foundation
import PrivacyConfig

/// What a tab view should do with the contextual onboarding dialog it shows.
enum ContextualOnboardingDialogUpdate: Equatable {
    /// Show this dialog, replacing any dialog on screen.
    case show(ContextualDialogType)
    /// Remove the dialog on screen, if any.
    case hide
    /// Leave the screen as it is.
    case keep
}

/// Decides when a tab view asks for a contextual onboarding dialog. One per `BrowserTabViewController`.
/// The tab view keeps drawing the dialog and handling its buttons, and applies the updates returned here.
@MainActor
final class ContextualOnboardingDialogScheduler {

    private let dialogProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater
    private let featureFlagger: FeatureFlagger
    private let isInPopUpWindow: () -> Bool

    /// The tab and URL of the last finished navigation, to tell a reload from a new page.
    private weak var lastTab: Tab?
    private(set) var lastURL: URL?

    /// Set when the user dismissed the dialog or switched tabs, so it isn't shown again when the window becomes key.
    private var wasDismissed = false

    init(dialogProvider: ContextualOnboardingDialogTypeProviding & ContextualOnboardingStateUpdater,
         featureFlagger: FeatureFlagger,
         isInPopUpWindow: @escaping () -> Bool) {
        self.dialogProvider = dialogProvider
        self.featureFlagger = featureFlagger
        self.isInPopUpWindow = isInPopUpWindow
    }

    /// A navigation finished in the tab on screen: moves onboarding forward, unless it's a reload.
    func navigationDidFinish(in tab: Tab?) -> ContextualOnboardingDialogUpdate {
        // A reload removes the dialog without asking for a new one.
        if tab == lastTab && tab?.url == lastURL && lastURL != nil {
            return .hide
        }
        lastURL = tab?.url
        lastTab = tab
        guard canShowDialog(), let tab else { return .hide }
        return update(showing: dialogProvider.dialogTypeForTab(tab, privacyInfo: tab.privacyInfo))
    }

    /// The window became key; `displayed` is the dialog on screen, if any.
    func windowDidBecomeKey(tab: Tab?, displayed: ContextualDialogType?) -> ContextualOnboardingDialogUpdate {
        guard !isInPopUpWindow(), !wasDismissed, dialogProvider.state != .onboardingCompleted else { return .keep }
        // Re-showing the same dialog would restart its typewriter animation.
        let expected = tab.flatMap { dialogProvider.lastDialogForTab($0) }
        if displayed != nil && displayed == expected { return .keep }
        return showLastDialog(in: tab)
    }

    /// Shows again the last dialog of this tab, without moving onboarding forward.
    /// Only the tab it was shown on gets it back, so a new window doesn't repeat it.
    func showLastDialog(in tab: Tab?) -> ContextualOnboardingDialogUpdate {
        guard canShowDialog(), let tab else { return .hide }
        return update(showing: dialogProvider.lastDialogForTab(tab))
    }

    /// The selected tab changed. Counts as dismissing the dialog.
    func selectedTabDidChange() {
        wasDismissed = true
    }

    /// The user dismissed the dialog on screen.
    func dialogDismissed() {
        wasDismissed = true
    }

    private func canShowDialog() -> Bool {
        guard featureFlagger.isFeatureOn(.contextualOnboarding) else {
            dialogProvider.turnOffFeature()
            return false
        }
        return !isInPopUpWindow()
    }

    private func update(showing dialog: ContextualDialogType?) -> ContextualOnboardingDialogUpdate {
        guard let dialog else { return .hide }
        wasDismissed = false
        return .show(dialog)
    }
}
