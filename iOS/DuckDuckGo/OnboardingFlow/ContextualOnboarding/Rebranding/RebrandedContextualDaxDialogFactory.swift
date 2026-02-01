//
//  RebrandedContextualDaxDialogFactory.swift
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

import SwiftUI
import Core
import Onboarding

final class RebrandedContextualDaxDialogFactory: ContextualDaxDialogsFactory {
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    private let contextualOnboardingSettings: ContextualOnboardingSettings
    private let contextualOnboardingPixelReporter: OnboardingPixelReporting
    private let contextualOnboardingSiteSuggestionsProvider: OnboardingSuggestionsItemsProviding
    private let onboardingManager: OnboardingManaging

    init(
        contextualOnboardingLogic: ContextualOnboardingLogic,
        contextualOnboardingSettings: ContextualOnboardingSettings = DefaultDaxDialogsSettings(),
        contextualOnboardingPixelReporter: OnboardingPixelReporting,
        contextualOnboardingSiteSuggestionsProvider: OnboardingSuggestionsItemsProviding = OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle),
        onboardingManager: OnboardingManaging = OnboardingManager()
    ) {
        self.contextualOnboardingSettings = contextualOnboardingSettings
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.contextualOnboardingPixelReporter = contextualOnboardingPixelReporter
        self.contextualOnboardingSiteSuggestionsProvider = contextualOnboardingSiteSuggestionsProvider
        self.onboardingManager = onboardingManager
    }

    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView> {
        let rootView: AnyView
        switch spec.type {
        case .afterSearch:
            rootView = AnyView(
                Button(action: delegate.didAcknowledgeContextualOnboardingSearch) {
                    Text(verbatim: "Ok")
                }
            )
        case .visitWebsite:
            rootView = AnyView(
                Button(action: { delegate.navigateFromOnboarding(to: URL(string: "https://apple.com")!) }) {
                    Text(verbatim: "Try apple.com")
                }
            )
        case .siteIsMajorTracker, .siteOwnedByMajorTracker, .withMultipleTrackers, .withOneTracker, .withoutTrackers:
            rootView = AnyView(
                Button(action: delegate.didAcknowledgeContextualOnboardingTrackersDialog) {
                    Text(verbatim: "Ok")
                }
            )
        case .fire:
            rootView = AnyView(
                Button(action: delegate.didTapDismissContextualOnboardingAction) {
                    Text(verbatim: "Dismiss Dialog")
                }
            )
        case .final:
            rootView = AnyView(
                Button(action: delegate.didTapDismissContextualOnboardingAction) {
                    Text(verbatim: "Dismiss Dialog")
                }
            )
        }

        let hostingController = UIHostingController(rootView: AnyView(rootView))
        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = [.intrinsicContentSize]
        }

        return hostingController
    }

}
