//
//  RebrandedContextualOnboardingDialogs+TrySite.swift
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
import Onboarding
import MetricBuilder

// MARK: - Try Visiting Site

extension OnboardingRebranding {

    struct OnboardingTrySiteDialog: View {
        @Environment(\.onboardingTheme) private var theme

        var message = UserText.Onboarding.ContextualOnboarding.onboardingTryASiteMessage
        let viewModel: OnboardingSiteSuggestionsViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            ScrollView(.vertical, showsIndicators: false) {
                OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: onManualDismiss) {
                    OnboardingTrySiteDialogContent(message: message, viewModel: viewModel)
                }
                .padding(theme.contextualOnboardingMetrics.containerPadding)
            }
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
        }
    }

    struct OnboardingTrySiteDialogContent: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass

        var message = UserText.Onboarding.ContextualOnboarding.onboardingTryASiteMessage
        let viewModel: OnboardingSiteSuggestionsViewModel

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation().build(v: vSizeClass, h: hSizeClass),
                title: viewModel.title,
                message: message.attributed
            ) {
                OnboardingRebranding.ContextualOnboardingListView(list: viewModel.itemsList, action: viewModel.listItemPressed)
            }
        }
    }

}

// MARK: - Previews

#Preview("Onboarding TryVisitSiteDialog - Light") {
    ZStack {
        Color.white.ignoresSafeArea()

        OnboardingRebranding.OnboardingTrySiteDialog(
            viewModel: OnboardingSiteSuggestionsViewModel(
                title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteMessage,
                suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle)
            ),
            onManualDismiss: {}
        )
        .padding()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.light)
}

#Preview("Onboarding TryVisitSiteDialog - Dark") {
    ZStack {
        Color(red: 43/255, green: 85/255, blue: 202/255).ignoresSafeArea()

        OnboardingRebranding.OnboardingTrySiteDialog(
            viewModel: OnboardingSiteSuggestionsViewModel(
                title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteMessage,
                suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle)
            ),
            onManualDismiss: {}
        )
        .padding()
        .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
    }
    .preferredColorScheme(.dark)
}
