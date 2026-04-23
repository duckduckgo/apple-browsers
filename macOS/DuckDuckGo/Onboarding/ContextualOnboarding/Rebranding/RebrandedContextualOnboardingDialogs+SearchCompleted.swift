//
//  RebrandedContextualOnboardingDialogs+SearchCompleted.swift
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

// MARK: - Anonymous Search Completed

extension OnboardingRebranding {

    struct OnboardingSearchDoneDialog: View {
        @Environment(\.onboardingTheme) private var theme

        let title = NSAttributedString(string: UserText.ContextualOnboarding.onboardingFirstSearchDoneTitle)
        let message = NSAttributedString(string: UserText.ContextualOnboarding.onboardingFirstSearchDoneMessage)
        let cta = UserText.ContextualOnboarding.onboardingGotItButton

        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let initialPanelHeight: CGFloat
        let followUpPanelHeight: CGFloat
        let viewModel: OnboardingSiteSuggestionsViewModel
        let gotItAction: () -> Void
        let onManualDismiss: () -> Void
        /// Fires when the bubble transitions in-place to the follow-up content,
        /// so the host can swap the background illustration to match.
        let onContentTransition: (() -> Void)?

        private var panelHeight: CGFloat {
            showNextScreen ? followUpPanelHeight : initialPanelHeight
        }

        var body: some View {
            // When transitioning to the follow-up ("try a site!") we render the full
            // tryASite dialog so the waving-Dax overlay and bubble tail come with it —
            // the Figma calls for Dax + tail on that screen, which a content-only swap
            // inside the plain searchDone bubble can't produce.
            if showNextScreen {
                OnboardingRebranding.OnboardingTrySiteDialog(
                    viewModel: viewModel,
                    onManualDismiss: onManualDismiss
                )
                .transition(.identity)
            } else {
                // searchDone has no Dax and no bubble tail per the Figma — just a plain bubble.
                OnboardingBubbleView.withDismissButton(
                    tailPosition: nil,
                    onDismiss: onManualDismiss
                ) {
                    OnboardingRebranding.ContextualDaxDialogContent(
                        orientation: .horizontalStack(alignment: .center),
                        title: title,
                        message: message
                    ) {
                        Button(cta) {
                            gotItAction()
                            if shouldFollowUp {
                                onContentTransition?()
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showNextScreen = true
                                }
                            }
                        }
                        .buttonStyle(theme.primaryButtonStyle.style)
                    }
                }
                .contextualOnboardingPanelLayout(height: panelHeight)
                .transition(.identity)
            }
        }
    }

}
