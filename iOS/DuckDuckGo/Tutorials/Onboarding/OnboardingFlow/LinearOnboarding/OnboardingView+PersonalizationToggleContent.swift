//
//  OnboardingView+PersonalizationToggleContent.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

// MARK: - Helpers

/// One toggle row in a `PersonalizationTemplate`: static copy + icon, plus the live `Bool` binding
/// (built from a personalization slice at the call site). `subtitle` is optional — some rows have none.
struct OnboardingPersonalizationToggleItem: Identifiable {
    let item: OnboardingPersonalizationContent.Item
    let isOn: Binding<Bool>
    /// Rows shown only while this item's toggle is on
    let dependentItems: [OnboardingPersonalizationToggleItem]

    var id: OnboardingPersonalizationContent.Item.ItemType {
        item.type
    }
}

extension OnboardingPersonalizationToggleItem {

    init(_ item: OnboardingPersonalizationContent.Item, isOn: Binding<Bool>, dependentItems: [OnboardingPersonalizationToggleItem] = []) {
        self.item = item
        self.isOn = isOn
        self.dependentItems = dependentItems
    }

}

extension OnboardingPersonalizationContent.Item.ItemType {

    func uiBindingTo(manager: OnboardingPersonalizationManaging) -> Binding<Bool> {
        switch self {
        case .recentlyVisitedSites:
            Binding(
                get: {
                    manager.isRecentlyVisitedSitesEnabled
                },
                set: {
                    manager.setRecentlyVisitedSites($0)
                }
            )
        case .safeSearch:
            Binding(
                get: {
                    manager.isSafeSearchEnabled
                },
                set: {
                    manager.setSafeSearch($0)
                }
            )
        case .searchAssist:
            Binding(
                get: {
                    manager.isSearchAssistEnabled
                },
                set: {
                    manager.setSearchAssist($0)
                }
            )
        case .aiGeneratedImages:
            Binding(
                get: {
                    manager.areAIGeneratedImagesHidden
                },
                set: {
                    manager.setAIGeneratedImagesHidden($0)
                }
            )
        case .youTubeAdBlocking:
            Binding(
                get: {
                    manager.isYouTubeAdBlockingEnabled
                },
                set: {
                    manager.setYouTubeAdBlocking($0)
                }
            )
        case .rejectOptionalCookies:
            Binding(
                get: {
                    manager.isCookiePopUpProtectionEnabled
                },
                set: {
                    manager.setCookiePopUpProtection($0)
                }
            )
        case .acceptOtherCookies:
            Binding(
                get: {
                    manager.isPopUpsWithoutOptOutsEnabled
                },
                set: {
                    manager.setPopUpsWithoutOptOuts($0)
                }
            )
        }
    }

}

// MARK: - Template View

extension OnboardingView {

    /// A reusable shell for the toggle-list personalization steps (Search, No-AI, YouTube, …):
    /// a typing title, a list of toggle rows, and a primary CTA.
    ///
    /// Screens whose *shape* differs — e.g. the single-select model picker — get their own view
    /// rather than bending this one with mode flags. Same shape → reuse; different shape → new view.
    struct PersonalizationToggleTemplate: View {
        private enum Metrics {
            static let contentTopPadding: CGFloat = 24
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool

        private let content: OnboardingPersonalizationContent
        private let items: [OnboardingPersonalizationToggleItem]
        private let action: () -> Void

        init(
            content: OnboardingPersonalizationContent,
            items: [OnboardingPersonalizationToggleItem],
            isVisible: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.content = content
            self.items = items
            self._isVisible = isVisible
            self.action = action
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: Metrics.contentTopPadding,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: message,
                content: AnyView(
                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingPersonalizationToggleItemsList(items: items)

                        if let footer = content.footer {
                            Text(footer)
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                                .font(onboardingTheme.typography.progressIndicator)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
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
                    Button(action: action) {
                        Text(content.primaryCTA)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        private var message: AnyView? {
            if let message = content.message {
                return AnyView(
                    Text(message)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.body)
                    .multilineTextAlignment(.center)
                    )
            } else {
                return nil
            }
        }

    }

}
