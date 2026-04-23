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
        let viewModel: OnboardingSiteSuggestionsViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            // Mirrors tryASearch layout: Dax waving on the left overlapping the bubble's
            // top-left; bubble keeps its normal 640pt max width.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingBubbleView(
                    tailPosition: .leading(offset: 0.85, direction: .top),
                    arrowLength: 14,
                    arrowWidth: 22,
                    content: {
                        OnboardingTrySiteDialogContent(viewModel: viewModel)
                    }
                )
                .onboardingDismissable(onManualDismiss)
                .frame(maxWidth: 640)
                .overlay(
                    DaxWavingAnimation()
                        .frame(width: 130, height: 154)
                        .clipped()
                        .offset(x: -130, y: -21)
                        .allowsHitTesting(false),
                    alignment: .topLeading
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)
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
