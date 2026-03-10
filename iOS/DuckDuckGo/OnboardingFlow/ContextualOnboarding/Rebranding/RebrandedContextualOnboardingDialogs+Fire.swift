//
//  RebrandedContextualOnboardingDialogs+Fire.swift
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

// MARK: - Fire Dialog

extension OnboardingRebranding {

    struct OnboardingFireDialog: View {
        @Environment(\.onboardingTheme) private var theme

        let onManualDismiss: () -> Void

        var body: some View {
            OnboardingBubbleView.withDismissButton(tailPosition: nil, onDismiss: onManualDismiss) {
                OnboardingRebranding.OnboardingFireDialogContent()
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
        }
    }

    struct OnboardingFireDialogContent: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass

        var message = UserText.Onboarding.ContextualOnboarding.onboardingTryFireButtonMessage

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent<EmptyView>(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation().build(v: vSizeClass, h: hSizeClass),
                message: attributedMessage
            )
        }

        private let attributedMessage: AttributedString = {
            var attributedString = AttributedString(UserText.Onboarding.ContextualOnboarding.onboardingTryFireButtonMessage)
            // Find the range of "Fire Button"
            if let range = attributedString.range(of: "Fire Button") {
                attributedString[range].inlinePresentationIntent = .stronglyEmphasized // Bold
            }
            return attributedString
        }()
    }

}
