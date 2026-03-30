//
//  RebrandedContextualOnboardingDialogs+SearchCompleted.swift
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

// MARK: - Anonymous Search Completed

extension OnboardingRebranding {

    struct OnboardingSearchDoneDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme

        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let viewModel: OnboardingSiteSuggestionsViewModel
        let gotItAction: () -> Void
        let onManualDismiss: (_ isShowingNextScreen: Bool) -> Void

        var body: some View {
            OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: { onManualDismiss(showNextScreen) }) {
                if showNextScreen {
                    searchDoneFollowUpContent
                } else {
                    searchDoneContent
                }
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
        }


        private var searchDoneContent: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                title: UserText.Onboarding.ContextualOnboarding.Rebranding.onboardingFirstSearchDoneTitle,
                message: UserText.Onboarding.ContextualOnboarding.Rebranding.onboardingFirstSearchDoneMessage
            ) {
                Button {
                    gotItAction()
                    withAnimation {
                        if shouldFollowUp {
                            showNextScreen = true
                        }
                    }
                } label: {
                    Text(UserText.Onboarding.ContextualOnboarding.onboardingGotItButton)
                }
                .frame(maxWidth: Metrics.buttonMaxWidth.build(v: vSizeClass, h: hSizeClass))
                .buttonStyle(theme.primaryButtonStyle.style)
            }
        }

        private var searchDoneFollowUpContent: some View {
            OnboardingRebranding.OnboardingTrySiteDialogContent(viewModel: viewModel)
        }

    }

}

private extension OnboardingRebranding.OnboardingSearchDoneDialog {

    enum Metrics {
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).iPhone(landscape: 174.0).iPad(174.0)
    }

}
