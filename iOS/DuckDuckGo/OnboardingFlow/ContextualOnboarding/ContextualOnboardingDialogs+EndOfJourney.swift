//
//  ContextualOnboardingDialogs+EndOfJourney.swift
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

    static let contextualThumbsUpDaxAnimation = DaxAnimation(
        animationName: "Dax-EndOfJourney-TryWebsite",
        size: CGSize(width: 153, height: 169.67),
        position: .left(bottomPadding: -70.0, xOffset: 0.0),
        largeScreenPosition: .left(bottomPadding: 0.0, xOffset: 0.0)
    )

    /// https://www.figma.com/design/YPE94Xkcrk2uqiF2l4VmSv/Onboarding--2026-?node-id=12206-51627&m=dev
    /// https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=938-134498&m=dev
    struct OnboardingEndOfJourneyDialog: View {
        @Environment(\.verticalSizeClass) private var vSizeClass
        @Environment(\.horizontalSizeClass) private var hSizeClass
        @Environment(\.onboardingTheme) private var theme
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        let content: OnboardingEndOfJourneyContent
        let onAction: (OnboardingEndOfJourneyAction) -> Void

        init(content: OnboardingEndOfJourneyContent, onAction: @escaping (OnboardingEndOfJourneyAction) -> Void) {
            self.content = content
            self.onAction = onAction
        }

        /// Legacy convenience initializer for single-button callers (fire-onboarding completion, standard
        /// final) that still pass discrete closures. Bridges them to the content-driven view.
        init(title: String = UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenTitle,
             message: String,
             cta: String,
             showsDaxAnimation: Bool = true,
             dismissAction: @escaping () -> Void,
             onManualDismiss: (() -> Void)? = nil) {
            self.content = OnboardingEndOfJourneyContent(
                icon: nil,
                title: title,
                message: message,
                primaryCTA: cta,
                primaryAction: .completeAndActivateSearch,
                secondaryCTA: nil,
                secondaryAction: nil,
                daxAnimation: showsDaxAnimation ? OnboardingRebranding.contextualThumbsUpDaxAnimation : nil,
                isManuallyDismissable: onManualDismiss != nil
            )
            self.onAction = { action in
                switch action {
                case .manualDismiss: onManualDismiss?()
                default: dismissAction()
                }
            }
        }

        var body: some View {
            OnboardingBubbleView(tailPosition: content.daxAnimation != nil && !OnboardingBubbleAnimationMetrics.shouldHideBubbleTail(for: dynamicTypeSize) ? .bottom(offset: 0.2, direction: .leading) : nil) {
                dialogContent
            }
            .if(content.isManuallyDismissable) { view in
                view.onboardingDismissable {
                    onAction(.manualDismiss)
                }
            }
            .padding(theme.contextualOnboardingMetrics.containerPadding)
            .applyMaxDialogWidth(iPhoneLandscape: theme.contextualOnboardingMetrics.maxContainerWidth, iPad: theme.contextualOnboardingMetrics.maxContainerWidth)
            .overlay {
                // Bottom, keyboard-aware Dax on every non-compact device. Hidden on compact (no room)
                // and when the content opts out (e.g. the chat-path completion).
                if let daxAnimation = content.daxAnimation, !OnboardingBubbleAnimationMetrics.isCompactDevice {
                    ScreenBottomDaxOverlay(animation: daxAnimation)
                }
            }
        }

        @ViewBuilder
        private var dialogContent: some View {
            if let icon = content.icon {
                iconDialogContent(icon: icon)
            } else {
                standardDialogContent
            }
        }

        /// Icon variant (Try-AI): promo-style layout — top icon with centered title/message.
        private func iconDialogContent(icon: OnboardingEndOfJourneyIcon) -> some View {
            VStack {
                icon.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.iconSize.width, height: Metrics.iconSize.height)
                OnboardingRebranding.ContextualDaxDialogContent(
                    title: content.title,
                    titleTextAlignment: .center,
                    message: content.message,
                    messageTextAlignment: .center
                ) {
                    buttons
                }
            }
        }

        /// Standard "You've got this!" / privateAIChat: bottom bubble tail, orientation-adaptive rich text.
        private var standardDialogContent: some View {
            OnboardingRebranding.ContextualDaxDialogContent(
                orientation: OnboardingRebranding.ContextualDynamicMetrics.dialogOrientation(horizontalAlignment: .center).build(v: vSizeClass, h: hSizeClass),
                title: AttributedString(content.title),
                message: AttributedString(OnboardingRichTextMessageRenderer.render(content.message))
            ) {
                buttons
            }
        }

        @ViewBuilder
        private var buttons: some View {
            VStack(spacing: Metrics.buttonSpacing) {
                Button(action: { onAction(content.primaryAction) }) {
                    Text(content.primaryCTA)
                }
                // Single-button dialogs keep the current width on iPad / iPhone-landscape; two-button dialogs stay full-width.
                .frame(maxWidth: content.secondaryCTA == nil ? Metrics.buttonMaxWidth.build(v: vSizeClass, h: hSizeClass) : nil)
                .buttonStyle(theme.primaryButtonStyle.style)

                if let secondaryCTA = content.secondaryCTA, let secondaryAction = content.secondaryAction {
                    Button(action: { onAction(secondaryAction) }) {
                        Text(secondaryCTA)
                    }
                    .buttonStyle(theme.secondaryButtonStyle.style)
                }
            }
        }
    }

}

// MARK: - Icon

extension OnboardingEndOfJourneyIcon {
    /// The view owns the mapping from the semantic icon case to its image.
    var image: Image {
        switch self {
        case .duckAI:
            return Image(uiImage: DesignSystemImages.Color.Size96.duckAI)
        }
    }
}

// MARK: - Screen-Bottom Dax Overlay

/// Positions Dax at the screen bottom via global coordinates; re-anchors to the keyboard's
/// top edge when the keyboard is visible so it doesn't get covered. Renders beyond the
/// hosting controller's bounds (which doesn't clip).
struct ScreenBottomDaxOverlay: View {
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
        static let iconSize = CGSize(width: 96, height: 96)
        static let buttonSpacing: CGFloat = 8
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).iPhone(landscape: 170.0).iPad(170.0)
    }

}
