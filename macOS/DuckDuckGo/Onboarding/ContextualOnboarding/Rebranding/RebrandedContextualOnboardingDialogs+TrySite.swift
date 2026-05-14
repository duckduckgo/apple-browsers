//
//  RebrandedContextualOnboardingDialogs+TrySite.swift
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

// MARK: - Try Visiting Site

extension OnboardingRebranding {

    struct OnboardingTrySiteDialog: View {
        /// Layout values unique to the tryASite dialog. Shared metrics live on
        /// `OnboardingRebranding.Layout`.
        private enum Layout {
            /// Bubble tail anchor — sits slightly lower than tryASearch's 0.99 so the tail
            /// aligns with the Dax's pointing beak on this dialog's shorter content.
            static let tailOffset: CGFloat = 0.85
        }

        let viewModel: OnboardingSiteSuggestionsViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingBubbleView(
                    tailPosition: .leading(offset: Layout.tailOffset, direction: .top),
                    arrowLength: OnboardingRebranding.Layout.bubbleArrowLength,
                    arrowWidth: OnboardingRebranding.Layout.bubbleArrowWidth,
                    content: {
                        OnboardingTrySiteDialogContent(viewModel: viewModel)
                    }
                )
                .onboardingDismissable(onManualDismiss)
                .frame(maxWidth: OnboardingRebranding.Layout.bubbleMaxWidth)
                .overlay(
                    DaxWavingAnimation()
                        .frame(
                            width: OnboardingRebranding.Layout.DaxWaving.width,
                            height: OnboardingRebranding.Layout.DaxWaving.height
                        )
                        .clipped()
                        .offset(
                            x: OnboardingRebranding.Layout.DaxWaving.offsetX,
                            y: OnboardingRebranding.Layout.DaxWaving.offsetY
                        )
                        .allowsHitTesting(false),
                    alignment: .topLeading
                )
                Spacer(minLength: 0)
            }
            .padding(.top, OnboardingRebranding.Layout.panelTopPadding)
            .padding(.bottom, OnboardingRebranding.Layout.panelBottomPadding)
            .frame(maxWidth: .infinity)
        }
    }

    struct OnboardingTrySiteDialogContent: View {
        let title = NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryASiteTitle)
        let message = NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryASiteMessage)
        let viewModel: OnboardingSiteSuggestionsViewModel

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: .horizontalStack(alignment: .top),
                title: title,
                message: message
            ) {
                OnboardingRebranding.ContextualOnboardingListView(
                    list: viewModel.itemsList,
                    action: viewModel.listItemPressed
                )
            }
        }
    }

}
