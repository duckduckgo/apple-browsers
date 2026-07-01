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
import DesignResourcesKitIcons

// MARK: - End Of Journey Dialog

extension OnboardingRebranding {

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12206-51627&m=dev
    struct OnboardingEndOfJourneyDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        let title: String
        let message: String
        let cta: String
        let dismissAction: () -> Void
        let onManualDismiss: (() -> Void)?
        /// Suppress the screen-bottom Dax — used by the Duck.ai variant where the
        /// keyboard is up and there's no room for Dax.
        let showsDaxAnimation: Bool

        init(title: String = UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenTitle,
             message: String,
             cta: String,
             showsDaxAnimation: Bool = true,
             dismissAction: @escaping () -> Void, onManualDismiss: (() -> Void)? = nil) {
            self.title = title
            self.message = message
            self.cta = cta
            self.showsDaxAnimation = showsDaxAnimation
            self.dismissAction = dismissAction
            self.onManualDismiss = onManualDismiss
        }

        static let daxAnimation = DaxAnimation(
            animationName: "Dax-EndOfJourney-TryWebsite",
            size: CGSize(width: 153, height: 169.67),
            position: .left(bottomPadding: -70.0, xOffset: 0.0),
            largeScreenPosition: .left(bottomPadding: 0.0, xOffset: 0.0)
        )

        var body: some View {
            OnboardingBubbleView(tailPosition: showsDaxAnimation && !OnboardingBubbleAnimationMetrics.shouldHideBubbleTail(for: dynamicTypeSize) ? .bottom(offset: 0.2, direction: .leading) : nil) {
                OnboardingRebranding.ContextualDaxDialogContent(
                    orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                    title: AttributedString(title),
                    message: AttributedString(OnboardingRichTextMessageRenderer.render(message))
                ) {
                    Button(action: dismissAction) {
                        Text(cta)
                    }
                    .frame(maxWidth: Metrics.buttonMaxWidth.build(v: vSizeClass, h: hSizeClass))
                    .buttonStyle(theme.primaryButtonStyle.style)
                }
            }
            .ifLet(onManualDismiss) { view, onDismiss in
                view.onboardingDismissable(onDismiss)
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            .overlay {
                // Keyboard-aware placement on every non-compact device. Replaces the prior
                // iPhone-only path that left iPad's keyboard covering Dax.
                if showsDaxAnimation && !OnboardingBubbleAnimationMetrics.isCompactDevice {
                    ScreenBottomDaxOverlay(animation: Self.daxAnimation)
                }
            }
        }
    }

}

// MARK: - Screen-Bottom Dax Overlay

/// Positions Dax at the screen bottom via global coordinates; re-anchors to the keyboard's
/// top edge when the keyboard is visible so it doesn't get covered. Renders beyond the
/// hosting controller's bounds (which doesn't clip).
private struct ScreenBottomDaxOverlay: View {
    let animation: DaxAnimation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var keyboard = KeyboardResponder()

    private static let screenBottomPadding: CGFloat = 60
    /// `0` so Dax's bounding box rests directly on the keyboard's top edge.
    private static let keyboardTopPadding: CGFloat = 0
    /// Matches the standard iOS keyboard show/hide curve.
    private static let keyboardFollowAnimation: Animation = .easeInOut(duration: 0.25)

    private var xOffset: CGFloat {
        switch animation.position {
        case .left(_, let xOffset): return xOffset
        default: return 0
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let globalFrame = proxy.frame(in: .global)
            let windowHeight: CGFloat = {
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?
                    .keyWindow?.bounds.height ?? globalFrame.maxY
            }()

            let xCenter = animation.size.width / 2 + xOffset

            // Anchor above the screen bottom, or above the keyboard top when visible.
            // `keyboardFrame` is in window coords; convert to local via `globalFrame.minY`.
            let distanceToScreenBottom = windowHeight - globalFrame.maxY
            let screenBottomYCenter = proxy.size.height + distanceToScreenBottom - Self.screenBottomPadding - animation.size.height / 2

            let yCenter: CGFloat = {
                let keyboardFrame = keyboard.keyboardFrame
                guard keyboardFrame.height > 0 else { return screenBottomYCenter }
                let localKeyboardTop = keyboardFrame.minY - globalFrame.minY
                return localKeyboardTop - Self.keyboardTopPadding - animation.size.height / 2
            }()

            // Reduce Motion: freeze at the intended final frame.
            let mode: LottiePlaybackMode = {
                if reduceMotion {
                    let finalProgress = animation.twoStagesAnimation.map { AnimationProgressTime($0) } ?? 1.0
                    return .paused(at: .progress(finalProgress))
                }
                return .playing(.toProgress(1, loopMode: .playOnce))
            }()

            Lottie.LottieView {
                try await DotLottieFile.asset(named: animation.animationName)
            }
            .playbackMode(mode)
            .resizable()
            .frame(width: animation.size.width, height: animation.size.height)
            .position(x: xCenter, y: yCenter)
            .animation(reduceMotion ? nil : Self.keyboardFollowAnimation, value: keyboard.keyboardFrame)
        }
        .allowsHitTesting(false)
    }
}

private extension OnboardingRebranding.OnboardingEndOfJourneyDialog {

    enum Metrics {
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).iPhone(landscape: 170.0).iPad(170.0)
    }

}
