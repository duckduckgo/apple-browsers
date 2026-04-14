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
        let viewModel: OnboardingSiteSuggestionsViewModel
        let gotItAction: () -> Void
        let onManualDismiss: () -> Void

        var body: some View {
            OnboardingBubbleView.withDismissButton(
                tailPosition: .leading(offset: 0.3, direction: .top),
                onDismiss: onManualDismiss
            ) {
                if showNextScreen {
                    OnboardingTrySiteDialogContent(viewModel: viewModel)
                } else {
                    OnboardingRebranding.ContextualDaxDialogContent(
                        orientation: .horizontalStack(alignment: .center),
                        title: title,
                        message: message
                    ) {
                        Button(cta) {
                            gotItAction()
                            withAnimation {
                                if shouldFollowUp {
                                    showNextScreen = true
                                }
                            }
                        }
                        .buttonStyle(theme.primaryButtonStyle.style)
                    }
                }
            }
        }
    }

}
