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

import Onboarding
import SwiftUI

// MARK: - Fire Dialog

extension OnboardingRebranding {

    struct OnboardingFireDialog: View {
        @Environment(\.onboardingTheme) private var theme
        @Environment(\.onboardingTheme.contextualOnboardingMetrics) private var contextualMetrics

        let title: String?
        let message: String
        let isDuckAIExperiment: Bool
        let onManualDismiss: (() -> Void)?

        init(title: String? = nil, message: String, isDuckAIExperiment: Bool = false, onManualDismiss: (() -> Void)? = nil) {
            self.title = title
            self.message = message
            self.isDuckAIExperiment = isDuckAIExperiment
            self.onManualDismiss = onManualDismiss
        }

        var body: some View {
            OnboardingBubbleView(tailPosition: nil) {
                OnboardingRebranding.OnboardingFireDialogContent(
                    title: title,
                    message: message,
                    titleBodyVerticalSpacingOverride: isDuckAIExperiment ? contextualMetrics.titleBodyVerticalSpacingVerticalLayout * 0.4 : nil
                )
            }
            .ifLet(onManualDismiss) { view, onManualDismiss in
                view.onboardingDismissable(onManualDismiss)
            }
            .padding(dialogContainerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
        }

        private var dialogContainerPadding: EdgeInsets {
            let base = theme.contextualOnboardingMetrics.containerPadding
            guard isDuckAIExperiment else { return base }
            return EdgeInsets(
                top: base.top * 0.75,
                leading: base.leading,
                bottom: base.bottom * 0.75,
                trailing: base.trailing
            )
        }
    }

    struct OnboardingFireDialogContent: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass

        let title: String?
        let message: String
        let titleBodyVerticalSpacingOverride: CGFloat?

        init(title: String? = nil, message: String, titleBodyVerticalSpacingOverride: CGFloat? = nil) {
            self.title = title
            self.message = message
            self.titleBodyVerticalSpacingOverride = titleBodyVerticalSpacingOverride
        }

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent<EmptyView>(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation().build(v: vSizeClass, h: hSizeClass),
                title: title,
                titleBodyVerticalSpacingOverride: titleBodyVerticalSpacingOverride,
                message: message
            )
        }
    }

}
