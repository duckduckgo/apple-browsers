//
//  RebrandedContextualOnboardingDialogs+EndOfJourney.swift
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

import Lottie
import SwiftUI
import Onboarding
import MetricBuilder

// MARK: - End Of Journey Dialog

extension OnboardingRebranding {

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12206-51627&m=dev
    struct OnboardingEndOfJourneyDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme

        var title = UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenTitle
        let message: String
        let cta: String
        let dismissAction: () -> Void
        let onManualDismiss: () -> Void

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-EndOfJourney-TryWebsite",
            size: CGSize(width: 153, height: 169.67),
            position: .left(bottomPadding: -60, xOffset: -40)
        )

        var body: some View {
            OnboardingBubbleView.withDismissButton(
                tailPosition: OnboardingBubbleAnimationMetrics.isCompactDevice ? nil : .bottom(offset: 0.2, direction: .leading),
                onDismiss: onManualDismiss
            ) {
                OnboardingRebranding.ContextualDaxDialogContent(
                    orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                    title: title,
                    message: message
                ) {
                    Button(action: dismissAction) {
                        Text(cta)
                    }
                    .frame(maxWidth: Metrics.buttonMaxWidth.build(v: vSizeClass, h: hSizeClass))
                    .buttonStyle(theme.primaryButtonStyle.style)
                }
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            .overlay {
                if !OnboardingBubbleAnimationMetrics.isCompactDevice {
                    ScreenBottomDaxOverlay(animation: Self.daxAnimation)
                }
            }
        }
    }

}

// MARK: - Screen-Bottom Dax Overlay

/// Positions the Dax animation at the bottom of the screen using global coordinate calculation.
/// The animation renders beyond the hosting controller's bounds (clipsToBounds = false).
private struct ScreenBottomDaxOverlay: View {
    let animation: DaxAnimation

    /// Distance from the screen bottom to the bottom of the animation (above toolbar).
    private static let screenBottomPadding: CGFloat = 60

    /// Extracts the xOffset from the animation's position (only `.left` is supported here).
    private var xOffset: CGFloat {
        switch animation.position {
        case .left(_, let xOffset): return xOffset
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let globalFrame = proxy.frame(in: .global)

            // Get the window height from the key window to support iPad Stage Manager.
            let windowHeight: CGFloat = {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?
                    .keyWindow?.bounds.height ?? globalFrame.maxY
            }()
            let distanceToScreenBottom = windowHeight - globalFrame.maxY

            let xCenter = animation.size.width / 2 + xOffset
            let yCenter = proxy.size.height + distanceToScreenBottom - Self.screenBottomPadding - animation.size.height / 2

            Lottie.LottieView {
                try await DotLottieFile.asset(named: animation.animationName)
            }
            .playbackMode(.playing(.toProgress(1, loopMode: .playOnce)))
            .resizable()
            .frame(width: animation.size.width, height: animation.size.height)
            .position(x: xCenter, y: yCenter)
        }
        .allowsHitTesting(false)
    }
}

private extension OnboardingRebranding.OnboardingEndOfJourneyDialog {

    enum Metrics {
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).iPhone(landscape: 170.0).iPad(170.0)
    }

}
