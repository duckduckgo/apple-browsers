//
//  OnboardingView+SERPPersonalizationi.swift
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

import DuckUI
import Onboarding
import SwiftUI
import UIComponents
import DesignResourcesKitIcons

extension OnboardingView {

    struct SERPPersonalization: View {
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool
        private let content: OnboardingSERPPersonalizationContent
        private let searchPersonalization: OnboardingSearchPersonalizing
        private let primaryAction: () -> Void

        init(
            content: OnboardingSERPPersonalizationContent,
            searchPersonalization: OnboardingSearchPersonalizing,
            isVisible: Binding<Bool>,
            primaryAction: @escaping () -> Void,
        ) {
            self.content = content
            self.searchPersonalization = searchPersonalization
            self._isVisible = isVisible
            self.primaryAction = primaryAction
        }

        private var safeSearchBinding: Binding<Bool> {
            Binding(
                get: { searchPersonalization.isSafeSearchEnabled },
                set: { searchPersonalization.setSafeSearch($0) }
            )
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                content: AnyView(
                    OnboardingPersonalizationCardItem(
                        icon: Image(uiImage: DesignSystemImages.Color.Size24.autofill),
                        title: content.title,
                        subtitle: content.message,
                        toggleBinding: safeSearchBinding
                    )
                ),
                showContent: $showContent,
                title: {
                    TypingText(
                        content.title,
                        startAnimating: $shouldStartTyping,
                        onTypingFinished: { [reduceMotion] in
                            if reduceMotion {
                                showContent = true
                            } else {
                                withAnimation { showContent = true }
                            }
                        })
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)
                },
                actions: {
                    Button(action: primaryAction) {
                        Text(content.primaryCTA)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

    }

}

struct OnboardingPersonalizationCardItem: View {
    private enum Metrics {
        static let iconTextHorizontalSpacing: CGFloat = 10.0
        static let copyVerticalSpacing: CGFloat = 8.0
    }

    @Environment(\.onboardingTheme) private var onboardingTheme

    let icon: Image
    let title: String
    let subtitle: String
    let toggleBinding: Binding<Bool>

    var body: some View {
        CardItem(
            icon: CardItemIcon(
                position: .leadingColumn,
                visual: .image(icon),
                spacing: Metrics.iconTextHorizontalSpacing
            ),
            title: CardItemText(
                title,
                font: CardItemFont(onboardingTheme.typography.row)
            ),
            text: CardItemText(
                subtitle,
                font: CardItemFont(onboardingTheme.typography.rowDetails)
            ),
            titleTextSpacing: Metrics.copyVerticalSpacing,
            trailing: .toggle(toggleBinding, tint: Color(designSystemColor: .accentPrimary))
        )
    }

}

