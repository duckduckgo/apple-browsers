//
//  ContextualOnboardingDialogs+Fire.swift
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

        let title: String?
        let message: String
        let onManualDismiss: (() -> Void)?

        init(title: String? = nil, message: String, onManualDismiss: (() -> Void)? = nil) {
            self.title = title
            self.message = message
            self.onManualDismiss = onManualDismiss
        }

        var body: some View {
            OnboardingBubbleView(tailPosition: nil) {
                OnboardingRebranding.OnboardingFireDialogContent(title: title, message: message)
            }
            .ifLet(onManualDismiss) { view, onManualDismiss in
                view.onboardingDismissable(onManualDismiss)
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
        }
    }

    struct OnboardingFireDialogContent: View {
        private static let fireButtonCopy = "Fire Button"

        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass

        let title: String?
        let message: String

        init(title: String? = nil, message: String) {
            self.title = title
            self.message = message
        }

        var body: some View {
            OnboardingRebranding.ContextualDaxDialogContent<EmptyView>(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation().build(v: vSizeClass, h: hSizeClass),
                title: title.flatMap(AttributedString.init),
                message: attributedMessage
            )
        }

        /// Builds the message with bold applied to "Fire Button" via SwiftUI's
        /// attribute system so the theme's body font applies uniformly.
        private var attributedMessage: AttributedString {
            var attributed = AttributedString(message)
            if let range = attributed.range(of: Self.fireButtonCopy) {
                attributed[range].inlinePresentationIntent = .stronglyEmphasized // Bold
            }
            return attributed
        }
    }

}
