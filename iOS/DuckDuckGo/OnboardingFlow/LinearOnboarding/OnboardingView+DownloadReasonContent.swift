//
//  OnboardingView+DownloadReasonContent.swift
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

extension OnboardingView {

    /// Figma: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=89-87784
    struct DownloadReasonContent: View {
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @State private var selectedDownloadReason: OnboardingDownloadReasonContent.Option?
        @Binding var isVisible: Bool
        private let content: OnboardingDownloadReasonContent
        private let action: (OnboardingDownloadReasonContent.Option) -> Void

        init(
            content: OnboardingDownloadReasonContent,
            isVisible: Binding<Bool> = .constant(false),
            action: @escaping (OnboardingDownloadReasonContent.Option) -> Void
        ) {
            self.content = content
            self._isVisible = isVisible
            self.action = action
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(content.message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                content: AnyView(
                    DownloadReasonGrid(
                        items: content.options,
                        selectedItem: selectedDownloadReason,
                        onSelect: { downloadReason in
                            selectedDownloadReason = downloadReason
                        }
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
                        }
                    )
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)
                },
                actions: {
                    Button(action: handleNextButtonAction) {
                        Text(content.primaryCTA)
                    }
                    .disabled(selectedDownloadReason == nil)
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
        }

        func handleNextButtonAction() {
            guard let selectedDownloadReason else { return }
            action(selectedDownloadReason)
        }
    }

}

private struct DownloadReasonGrid: View {

    private enum Metrics {
        static let itemSpacing: CGFloat = 8
    }

    private let items: [OnboardingDownloadReasonContent.Option]
    private let selectedItem: OnboardingDownloadReasonContent.Option?
    private let rowAndColumns: [[OnboardingDownloadReasonContent.Option]]
    private let onSelect: (OnboardingDownloadReasonContent.Option) -> Void

    init(items: [OnboardingDownloadReasonContent.Option], selectedItem: OnboardingDownloadReasonContent.Option?, columns: Int = 2, onSelect: @escaping (OnboardingDownloadReasonContent.Option) -> Void) {
        self.items = items
        self.selectedItem = selectedItem
        rowAndColumns = items.chunked(into: columns)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .center, spacing: Metrics.itemSpacing) {
            ForEach(rowAndColumns, id: \.self) { row in
                HStack(spacing: Metrics.itemSpacing) {
                    ForEach(row, id: \.self) { reason in
                        DownloadReasonButton(icon: reason.icon, title: reason.title, isSelected: reason == selectedItem) {
                            onSelect(reason)
                        }
                    }
                }
            }
        }
        .compositingGroup() // Flatten the whole grid so the container's fade can't bleed shadows through fills
    }

}

private extension DownloadReasonGrid {

    struct DownloadReasonButton: View {

        private enum Metrics {
            static let contentVerticalSpacing: CGFloat = 8
            static let contentHorizontalPadding: CGFloat = 16
            static let contentVerticalPadding: CGFloat = 20
            static let cornerRadius: CGFloat = 24
            static let imageSize = CGSize(width: 44, height: 44)
            // Shadow
            static let innerShadowColor: Color = .black.opacity(0.06)
            static let innerShadowRadius: CGFloat = 2
            static let innerShadowOffset = CGPoint(x: 0, y: 1)
            static let outerShadowColor: Color = .black.opacity(0.16)
            static let outerShadowRadius: CGFloat = 0.5
            static let outerShadowOffset = CGPoint(x: 0, y: 0.25)
            // Stroke
            static let strokeInset: CGFloat = 0.5
            static let strokeWidth: CGFloat = 1
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.colorScheme) private var colorScheme

        let icon: OnboardingImageResource
        let title: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            VStack(alignment: .center, spacing: Metrics.contentVerticalSpacing) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.imageSize.width, height: Metrics.imageSize.height)

                Text(title)
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.contextual.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.contentHorizontalPadding)
            .padding(.vertical, Metrics.contentVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(isSelected ? OnboardingRebrandColor.accentAltPrimary : onboardingTheme.colorPalette.bubbleBackground)
            .cornerRadius(Metrics.cornerRadius)
            .shadow(color: Metrics.innerShadowColor, radius: Metrics.innerShadowRadius, x: Metrics.innerShadowOffset.x, y: Metrics.innerShadowOffset.y)
            .shadow(color: Metrics.outerShadowColor, radius: Metrics.outerShadowRadius, x: Metrics.outerShadowOffset.x, y: Metrics.outerShadowOffset.y)
            .overlay(overlay)
            .onTapGesture {
                action()
            }
        }

        @ViewBuilder
        private var overlay: some View {
            // A selected button is always outlined with the theme's border color. An unselected
            // button is outlined only in dark mode, with a subtle white edge; in light mode it
            // has no border.
            let borderColor: Color? = if isSelected {
                onboardingTheme.colorPalette.optionsListBorderColor
            } else if colorScheme == .dark {
                .white.opacity(0.12)
            } else {
                nil
            }

            if let borderColor {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                    .inset(by: Metrics.strokeInset)
                    .stroke(borderColor, lineWidth: Metrics.strokeWidth)
            }
        }
    }

}
