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
import DesignResourcesKitIcons

extension OnboardingView {

    /// Figma: https://www.figma.com/design/icdZo7pS4cAWaoVf4byU9t/Add-VPN-to-list-of-download-reasons?node-id=5170-28324
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
                    DownloadReasonList(
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

private enum DownloadReasonListMetrics {
    static let rowSpacing: CGFloat = 12
    static let listHorizontalPadding: CGFloat = 4
    static let contentSpacing: CGFloat = 16
    static let iconSpacing: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 16
    static let borderWidth: CGFloat = 1
    static let borderLightColor = Color.black.opacity(0.12)
    static let borderDarkColor = Color.white.opacity(0.12)
    static let accentColor = Color(singleUseColor: .rebranding(.accentPrimary))
}

private struct DownloadReasonList: View {

    let items: [OnboardingDownloadReasonContent.Option]
    let selectedItem: OnboardingDownloadReasonContent.Option?
    let onSelect: (OnboardingDownloadReasonContent.Option) -> Void

    var body: some View {
        VStack(spacing: DownloadReasonListMetrics.rowSpacing) {
            ForEach(items, id: \.self) { item in
                DownloadReasonRow(icon: item.icon, title: item.title, isSelected: item == selectedItem) {
                    onSelect(item)
                }
            }
        }
        .padding(.horizontal, DownloadReasonListMetrics.listHorizontalPadding)
    }

}

private struct DownloadReasonRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.onboardingTheme) private var onboardingTheme

    let icon: OnboardingDownloadReasonContent.Icon
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DownloadReasonListMetrics.contentSpacing) {
                HStack(spacing: DownloadReasonListMetrics.iconSpacing) {
                    iconImage
                        .frame(width: DownloadReasonListMetrics.iconSize, height: DownloadReasonListMetrics.iconSize)

                    Text(title)
                        .font(onboardingTheme.typography.contextual.body)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                OnboardingRebranding.RadioIndicator(isSelected: isSelected, accentColor: DownloadReasonListMetrics.accentColor)
            }
            .padding(.horizontal, DownloadReasonListMetrics.horizontalPadding)
            .padding(.vertical, DownloadReasonListMetrics.verticalPadding)
            .frame(maxWidth: .infinity)
            .background(isSelected ? OnboardingRebrandColor.accentAltGlowPrimary : .clear)
            .clipShape(RoundedRectangle(cornerRadius: DownloadReasonListMetrics.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DownloadReasonListMetrics.cornerRadius)
                    .strokeBorder(borderColor, lineWidth: DownloadReasonListMetrics.borderWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var iconImage: some View {
        switch icon {
        case .search:
            Image(uiImage: DesignSystemImages.Color.Size24.findSearch)
        case .aiChat:
            Image(uiImage: DesignSystemImages.Color.Size24.aiChat)
        case .adsBlocked:
            Image(uiImage: DesignSystemImages.Color.Size24.adsBlocked)
        case .block:
            Image(uiImage: DesignSystemImages.Color.Size24.block)
        case .vpn:
            Image(uiImage: DesignSystemImages.Color.Size24.vpn)
        }
    }

    private var borderColor: Color {
        if isSelected {
            DownloadReasonListMetrics.accentColor
        } else {
            colorScheme == .light ? DownloadReasonListMetrics.borderLightColor : DownloadReasonListMetrics.borderDarkColor
        }
    }

}
