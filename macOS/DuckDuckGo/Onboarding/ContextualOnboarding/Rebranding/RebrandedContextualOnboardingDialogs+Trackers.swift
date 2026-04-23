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
        @Environment(\.onboardingTheme) private var theme

        let cta = UserText.ContextualOnboarding.onboardingGotItButton

        @State private var showNextScreen: Bool = false

        let shouldFollowUp: Bool
        let initialPanelHeight: CGFloat
        let followUpPanelHeight: CGFloat
        let message: NSAttributedString
        let blockedTrackersCTAAction: () -> Void
        let viewModel: OnboardingFireButtonDialogViewModel
        let onManualDismiss: () -> Void
        /// Fires when the bubble transitions in-place to the follow-up content,
        /// so the host can swap the background illustration to match.
        let onContentTransition: (() -> Void)?

        private var panelHeight: CGFloat {
            showNextScreen ? followUpPanelHeight : initialPanelHeight
        }

        var body: some View {
            // Trackers dialog: tail at bottom-leading (points down-right); Wing Lottie sits
            // DIRECTLY below the bubble (VStack with small negative spacing so wing's top
            // overlaps bubble's tail area). The wing's bottom is flush with the panel's
            // bottom padding — no extra space below.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                // Negative spacing pulls the wing up so its top overlaps the bubble's tail
                // area — the "padding between bubble and wing" the reference shows.
                VStack(spacing: -20) {
                    OnboardingBubbleView(
                        tailPosition: .bottom(offset: 0.1, direction: .trailing),
                        arrowLength: 14,
                        arrowWidth: 22,
                        content: {
                            if showNextScreen {
                                OnboardingFireDialogContent(viewModel: viewModel)
                                    .transition(.identity)
                            } else {
                                OnboardingRebranding.ContextualDaxDialogContent(
                                    orientation: .horizontalStack(alignment: .center),
                                    message: message
                                ) {
                                    Button(cta) {
                                        blockedTrackersCTAAction()
                                        if shouldFollowUp {
                                            onContentTransition?()
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                showNextScreen = true
                                            }
                                        }
                                    }
                                    .buttonStyle(theme.primaryButtonStyle.style)
                                }
                                .transition(.identity)
                            }
                        }
                    )
                    .onboardingDismissable(onManualDismiss)

                    WingPointingAnimation()
                        .frame(width: 55, height: 62)
                        .clipped()
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: 640)
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            // No bottom padding — the wing animation IS the bottom of the panel (anchored
            // directly to the panel edge, no background showing through below it).
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity)
        }
    }

}

// MARK: - Wing Pointing Lottie

/// Hand/wing pointer Lottie loaded from the OnboardingContextual asset catalog. Plays once on
/// appear and holds on the final frame.
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
