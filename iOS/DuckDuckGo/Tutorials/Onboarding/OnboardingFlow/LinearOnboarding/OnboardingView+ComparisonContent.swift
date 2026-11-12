//
//  OnboardingView+ComparisonContent.swift
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

import DesignResourcesKitIcons
import DuckUI
import Onboarding
import SwiftUI

extension OnboardingView {

    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=7412-24499
    /// Figma: https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=7419-54020
    struct ComparisonContent: View {

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @Binding var isVisible: Bool
        @State private var shouldStartTyping = false
        @State private var showContent = false
        private let content: OnboardingComparisonContent
        private let primaryAction: () -> Void
        private let cancelAction: (() -> Void)?

        init(
            content: OnboardingComparisonContent,
            isVisible: Binding<Bool>,
            primaryAction: @escaping () -> Void,
            cancelAction: (() -> Void)? = nil
        ) {
            self.content = content
            self._isVisible = isVisible
            self.primaryAction = primaryAction
            self.cancelAction = cancelAction
        }

        // Uses a custom layout instead of LinearDialogContentContainer because
        // the comparison table has its own animated row reveal that needs `showContent`.
        var body: some View {
            VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                TypingText(
                    content.title,
                    startAnimating: $shouldStartTyping,
                    onTypingFinished: { [reduceMotion] in
                        if reduceMotion {
                            showContent = true
                        } else {
                            withAnimation { showContent = true }
                        }
                    }
                )
                .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                .font(onboardingTheme.typography.title)
                .multilineTextAlignment(.center)

                VStack(spacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing) {
                    RebrandedOnboardingComparisonTableView(
                        header: tableHeader,
                        features: content.features,
                        availableFeatureAnimation: .animated(startAnimation: showContent)
                    )

                    if let footer = content.footer {
                        SubscriptionNote(text: footer)
                    }

                    VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
                        Button(action: primaryAction) {
                            Text(content.primaryCTA)
                        }
                        .buttonStyle(onboardingTheme.primaryButtonStyle.style)

                        if let secondaryCTA = content.secondaryCTA, let cancelAction {
                            Button(action: cancelAction) {
                                Text(secondaryCTA)
                            }
                            .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                        }
                    }
                }
                .opacity(showContent ? 1 : 0)
                .animation(reduceMotion ? nil : .easeIn(duration: 0.25), value: showContent)
            }
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        private var tableHeader: RebrandedOnboardingComparisonTableView.Header {
            let leftIcon = switch content.competitor {
            case .safari:
                OnboardingRebrandingImages.Comparison.safariIcon
            case .google:
                OnboardingRebrandingImages.Comparison.googleIcon
            case .ai:
                OnboardingRebrandingImages.Comparison.popularAIsIcon
            }

            if let subHeader = content.subHeader {
                return .textAndIcons(
                    title: subHeader,
                    leftIcon: leftIcon,
                    rightIcon: OnboardingRebrandingImages.Comparison.ddgIcon
                )
            }
            return .icons(
                leftIcon: leftIcon,
                rightIcon: OnboardingRebrandingImages.Comparison.ddgIcon
            )
        }

    }

}

private enum SubscriptionNoteMetrics {
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    static let iconSize: CGFloat = 24
}

/// A highlighted note pointing out that some features need a paid subscription.
private struct SubscriptionNote: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let text: String

    var body: some View {
        HStack(spacing: SubscriptionNoteMetrics.spacing) {
            Image(uiImage: DesignSystemImages.Color.Size24.subscription)
                .resizable()
                .frame(width: SubscriptionNoteMetrics.iconSize, height: SubscriptionNoteMetrics.iconSize)

            Text(text)
                .font(onboardingTheme.typography.rowDetails)
                .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SubscriptionNoteMetrics.padding)
        .background(OnboardingRebrandColor.subscriptionNoteBackground, in: RoundedRectangle(cornerRadius: SubscriptionNoteMetrics.cornerRadius))
    }
}
