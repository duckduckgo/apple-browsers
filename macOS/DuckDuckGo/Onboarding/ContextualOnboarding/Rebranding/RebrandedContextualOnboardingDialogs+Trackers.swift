//
//  RebrandedContextualOnboardingDialogs+Trackers.swift
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
import Lottie

// MARK: - Trackers Blocked

extension OnboardingRebranding {

    struct OnboardingTrackersBlockedDialog: View {
        /// Layout values unique to the trackers dialog. Shared metrics live on
        /// `OnboardingRebranding.Layout`.
        private enum Layout {
            /// Bubble tail near the bottom-leading edge, pointing down-right toward the wing.
            static let tailOffset: CGFloat = 0.1
            static let wingWidth: CGFloat = 55
            static let wingHeight: CGFloat = 62
            /// Negative spacing so the wing's top overlaps the bubble's tail area.
            static let wingOverlapSpacing: CGFloat = -20
            /// The wing animation is the bottom of the panel; no extra padding below it.
            static let panelBottomPadding: CGFloat = 0
        }

        @Environment(\.onboardingTheme) private var theme

        let cta = UserText.ContextualOnboarding.onboardingGotItButton

        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let message: NSAttributedString
        let blockedTrackersCTAAction: () -> Void
        let viewModel: OnboardingFireButtonDialogViewModel
        let onManualDismiss: () -> Void
        /// Fires when the bubble transitions in-place to the follow-up content,
        /// so the host can swap the background illustration to match.
        let onContentTransition: (() -> Void)?

        var body: some View {
            // The fire dialog is a plain tail-less bubble — an inline content swap inside the
            // trackers bubble would leave its tail and wing in place, so render OnboardingFireDialog
            // directly instead.
            if showNextScreen {
                OnboardingRebranding.OnboardingFireDialog(
                    viewModel: viewModel,
                    onManualDismiss: onManualDismiss,
                    onContentTransition: nil
                )
                .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: Layout.wingOverlapSpacing) {
                        OnboardingBubbleView(
                            tailPosition: .bottom(offset: Layout.tailOffset, direction: .trailing),
                            arrowLength: OnboardingRebranding.Layout.bubbleArrowLength,
                            arrowWidth: OnboardingRebranding.Layout.bubbleArrowWidth,
                            content: {
                                OnboardingRebranding.ContextualDaxDialogContent(
                                    orientation: .horizontalStack(alignment: .center),
                                    message: message
                                ) {
                                    Button(cta) {
                                        blockedTrackersCTAAction()
                                        if shouldFollowUp {
                                            onContentTransition?()
                                            withAnimation(.easeInOut(duration: OnboardingRebranding.Layout.inlineTransitionDuration)) {
                                                showNextScreen = true
                                            }
                                        }
                                    }
                                    .buttonStyle(theme.primaryButtonStyle.style)
                                }
                            }
                        )
                        .onboardingDismissable(onManualDismiss)

                        WingPointingAnimation()
                            .frame(width: Layout.wingWidth, height: Layout.wingHeight)
                            .clipped()
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: OnboardingRebranding.Layout.bubbleMaxWidth)
                    Spacer(minLength: 0)
                }
                .padding(.top, OnboardingRebranding.Layout.panelTopPadding)
                .padding(.bottom, Layout.panelBottomPadding)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
    }

}

// MARK: - Wing Pointing Lottie

/// Pointer-wing Lottie shown directly below the trackers bubble. Plays once on appear
/// and holds on the final frame.
struct WingPointingAnimation: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        attachAnimation(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func attachAnimation(to container: NSView) {
        guard let animation = LottieAnimation.asset("wing-pointing", bundle: .main) else {
            return
        }
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.animationSpeed = 1.0
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        view.play()
    }
}
