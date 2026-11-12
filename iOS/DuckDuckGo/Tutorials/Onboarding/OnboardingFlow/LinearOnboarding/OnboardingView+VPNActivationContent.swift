//
//  OnboardingView+VPNActivationContent.swift
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
import Onboarding
import SwiftUI

extension OnboardingView {

    /// Turns on the VPN for users who subscribed from the Try VPN step.
    ///
    /// Figma: https://www.figma.com/design/icdZo7pS4cAWaoVf4byU9t/Add-VPN-to-list-of-download-reasons?node-id=5170-28430
    struct VPNActivationContent: View {

        private enum Metrics {
            static let pictogramSize = CGSize(width: 128, height: 96)
            static let headerSpacing: CGFloat = 12
            static let outerSpacing: CGFloat = 28
            static let cardSpacing: CGFloat = 12
            static let buttonSpacing: CGFloat = 8
        }

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @StateObject private var viewModel: SubscriptionOnboardingVPNActivationViewModel
        @State private var shouldStartTyping = false
        @State private var showContent = false
        @Binding private var isVisible: Bool

        private let content: OnboardingVPNActivationContent
        private let continueAction: () -> Void

        init(
            content: OnboardingVPNActivationContent,
            viewModel: @autoclosure @escaping () -> SubscriptionOnboardingVPNActivationViewModel,
            isVisible: Binding<Bool>,
            continueAction: @escaping () -> Void
        ) {
            self.content = content
            self._viewModel = StateObject(wrappedValue: viewModel())
            self._isVisible = isVisible
            self.continueAction = continueAction
        }

        private var isOn: Bool {
            viewModel.connectionState == .on
        }

        var body: some View {
            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: Metrics.outerSpacing,
                    textSpacing: Metrics.outerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(infoCards),
                showContent: $showContent,
                title: { header },
                actions: { actions }
            )
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: viewModel.connectionState)
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
            .onAppear { viewModel.onAppear() }
            .onDisappear { viewModel.onDisappear() }
        }

        private var header: some View {
            VStack(spacing: Metrics.headerSpacing) {
                Image(uiImage: isOn ? DesignSystemImages.Color.Size128.networkProtectionVPN : DesignSystemImages.Color.Size128.networkProtectionVPNDisabled)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.pictogramSize.width, height: Metrics.pictogramSize.height)

                TypingText(
                    isOn ? content.onTitle : content.offTitle,
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
            }
        }

        @ViewBuilder
        private var infoCards: some View {
            if isOn {
                VStack(spacing: Metrics.cardSpacing) {
                    SubscriptionOnboardingVPNInfoCard(state: .hiddenIP,
                                                      ipAddress: viewModel.originalIPText,
                                                      location: viewModel.originalLocationText)
                    SubscriptionOnboardingVPNInfoCard(state: .newIP,
                                                      ipAddress: viewModel.vpnIPText,
                                                      location: viewModel.vpnLocationText,
                                                      nearestIndicator: viewModel.vpnLocationNearestIndicator,
                                                      isAvailable: viewModel.isVPNInfoAvailable)
                }
                .transition(.opacity)
            } else {
                SubscriptionOnboardingVPNInfoCard(state: .visibleIP,
                                                  ipAddress: viewModel.originalIPText,
                                                  location: viewModel.originalLocationText,
                                                  isAvailable: viewModel.isOriginalInfoAvailable)
                    .transition(.opacity)
            }
        }

        @ViewBuilder
        private var actions: some View {
            if isOn {
                Button(action: continueAction) {
                    Text(content.nextCTA)
                }
                .buttonStyle(onboardingTheme.primaryButtonStyle.style)
            } else {
                VStack(spacing: Metrics.buttonSpacing) {
                    Button(action: turnOnVPN) {
                        if viewModel.isActivating {
                            SwiftUI.ProgressView()
                        } else {
                            Text(viewModel.didFailActivation ? content.tryAgainCTA : content.turnOnCTA)
                        }
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                    .disabled(viewModel.isActivating)

                    Button(action: continueAction) {
                        Text(content.skipCTA)
                    }
                    .buttonStyle(onboardingTheme.secondaryButtonStyle.style)
                }
            }
        }

        private func turnOnVPN() {
            Task {
                await viewModel.turnOnVPN()
            }
        }

    }

}
