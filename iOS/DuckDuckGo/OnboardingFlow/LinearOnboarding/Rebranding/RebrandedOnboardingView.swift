//
//  RebrandedOnboardingView.swift
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
import MetricBuilder

private enum BubbleBackedDialogMetrics {
    /// Extra top margin for the intro step; all other steps use 0.
    static let introAdditionalTopMargin: CGFloat = 40
    static let browsersComparisonAdditionalTopMargin: CGFloat = 0
    static let addressBarPositionAdditionalTopMargin: CGFloat = 0
    static let searchExperienceAdditionalTopMargin: CGFloat = 0
    static let addToDockAdditionalTopMargin: CGFloat = 0
    static let appIconPickerAdditionalTopMargin: CGFloat = 0

    /// Percentage-based vertical offset for the dialog bubble to center it appropriately based on device orientation and screen size.
    /// iPhone uses 0.0 (relies on padding), iPad uses percentage of screen height
    static let dialogVerticalOffsetPercentage = MetricBuilder<CGFloat>(default: 0.0)
        .iPad(portrait: 0.15, landscape: 0.05)
}

/// Timing constants shared by step transitions and in-place sub-view swaps
/// (e.g. add-to-dock promo → tutorial).
enum OnboardingBubbleAnimationMetrics {
    static let bubbleResizeAnimationDuration: TimeInterval = 0.25
    static let contentFadeOutDelay: TimeInterval = 0.15
    static let contentFadeInDelay: TimeInterval = 0.3
    static let contentFadeInAnimationDuration: TimeInterval = 0.35
    static let daxEntranceDuration: TimeInterval = 0.5
    static let daxExitDuration: TimeInterval = 0.5

    /// iPhone 16 baseline. Containers smaller than this hide Dax and bubble tails.
    static let referenceScreenSize = CGSize(width: 390, height: 844)

    static var isCompactDevice: Bool {
        let size = windowSize
        return size.width < referenceScreenSize.width || size.height < referenceScreenSize.height
    }

    /// Bubble tails hide on compact containers and accessibility text sizes — at those text
    /// sizes the inflated bubble loses its anchor to Dax, so the tail becomes a stray decoration.
    static func shouldHideBubbleTail(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        isCompactDevice || dynamicTypeSize.isAccessibilitySize
    }

    /// iPad Pro 13″ portrait baseline. Some Dax animations use an alternate position above this.
    static let largeScreenThreshold = CGSize(width: 1000, height: 1300)

    static var isLargeScreen: Bool {
        let maxDimension = max(windowSize.width, windowSize.height)
        return maxDimension >= largeScreenThreshold.height
    }

    private static var windowSize: CGSize {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow?.bounds.size ?? .zero
    }
}

extension OnboardingRebranding.OnboardingView {

    /// Theme-driven inner layout for onboarding dialog steps (no visual chrome).
    ///
    /// ```
    /// ┌──────────────────────────┐
    /// │  Title                   │  ← required
    /// │  Message                 │  ← optional
    /// ├──────────────────────────┤  ← outerSpacing
    /// │  Content                 │  ← optional (e.g. image, picker)
    /// │  Actions                 │  ← required (buttons)
    /// └──────────────────────────┘
    /// ```
    ///
    /// `showContent` controls the opacity of everything below the title, enabling the
    /// content to fade in after the typing animation finishes.
    struct LinearDialogContentContainer<Title: View, Actions: View>: View {

        struct Metrics {
            let outerSpacing: CGFloat   // Between text group and content group
            let textSpacing: CGFloat    // Between title and message
            let contentSpacing: CGFloat // Between content and actions
            let actionsSpacing: CGFloat // Extra top padding above actions
        }

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private let metrics: Metrics
        private let message: AnyView?
        private let content: AnyView?
        private let showContent: Binding<Bool>
        private let title: Title
        private let actions: Actions

        init(
            metrics: Metrics,
            message: AnyView? = nil,
            content: AnyView? = nil,
            showContent: Binding<Bool> = .constant(true),
            @ViewBuilder title: () -> Title,
            @ViewBuilder actions: () -> Actions
        ) {
            self.metrics = metrics
            self.message = message
            self.content = content
            self.showContent = showContent
            self.title = title()
            self.actions = actions()
        }

        var body: some View {
            VStack(spacing: metrics.outerSpacing) {
                title

                VStack(spacing: metrics.textSpacing) {
                    if let message {
                        message
                    }

                    VStack(spacing: metrics.contentSpacing) {
                        if let content {
                            content
                        }

                        actions
                            .padding(.top, metrics.actionsSpacing)
                    }
                }
                .opacity(showContent.wrappedValue ? 1 : 0)
                .animation(reduceMotion ? nil : .easeIn(duration: 0.25), value: showContent.wrappedValue)
            }
        }

    }

}

// MARK: - Main View

extension OnboardingRebranding {

    struct OnboardingView: View {

        typealias ViewState = LegacyOnboardingViewState

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        /// When on, skip native transitions/fades and jump to final state. Typing is gated
        /// inside `TypingText` / `AnimatableTypingText`. Lottie freezes at the design layer.
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// Drives intro Dax sizing so AX text sizes don't make the bubble overlap Dax.
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Namespace var animationNamespace
        @ObservedObject private var model: OnboardingIntroViewModel
        @State private var dialogContentHeight: CGFloat = 0
        /// Live measured intro bubble height; Dax sizing reads `lockedIntroBubbleHeight` instead.
        @State private var introBubbleHeight: CGFloat = 0
        /// First non-zero intro bubble height captured per step entry / dynamic-type change.
        /// The intro bubble swaps between two content configurations; ignoring later
        /// measurements keeps Dax stable across the swap. Reset to `0` on font-size change.
        @State private var lockedIntroBubbleHeight: CGFloat = 0
        @State private var showBubbleContent: Bool = false
        @State private var skipTypingAnimation: Bool = false
        /// `true` → forward entrance; `false` → reverse exit.
        @State private var daxPlayForward = true
        /// Incrementing forces `DaxAnimationOverlay` to recreate and restart from the right frame.
        @State private var daxAnimationID = 0
        @State private var daxExiting = false
        /// Currently-displayed animation. Updated explicitly so the old overlay stays alive
        /// (and can finish its exit) after the model has moved on.
        @State private var currentDaxAnimation: DaxAnimation?
        @State private var isDuckAIQueryExitTransitionActive = false

        init(model: OnboardingIntroViewModel) {
            self.model = model
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                switch model.state {
                case let .landing(content):
                    onboardingTheme.colorPalette.background
                        .ignoresSafeArea()
                    landingView(content: content)
                        .transition(reduceMotion ? .identity : AnyTransition.slideLeftAndFade.animation(.easeOut(duration: 1.0)))
                case let .onboarding(viewState):
                    onboardingTheme.colorPalette.background
                        .ignoresSafeArea()

                    ScrollableOnboardingBackground(viewState: viewState)

                    // Authoritative AX-size guard at render time, in case the `dynamicTypeSize`
                    // onChange handler below hasn't run yet (e.g. waking from background).
                    if let dax = currentDaxAnimation, !dynamicTypeSize.isAccessibilitySize {
                        DaxAnimationOverlay(animation: dax, playForward: daxPlayForward, isExiting: daxExiting)
                            // Recreate on direction changes and step transitions.
                            .id("\(daxAnimationID)-\(dax.animationName)")
                    }

                    onboardingDialogView(state: viewState)
                        .transition(
                            reduceMotion ? .identity : .scale.combined(with: .opacity)
                        )
#if DEBUG || ALPHA
                        .overlay(alignment: .bottom) {
                            Button {
                                model.overrideOnboardingCompleted()
                            } label: {
                                Text(UserText.Onboarding.Intro.Debug.skip)
                            }
                            .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
                            .padding(.bottom, 8)
                        }
#endif
                }
            }
            .contentShape(Rectangle())
            // Tap anywhere to skip the current typing animation via the environment key.
            .simultaneousGesture(TapGesture().onEnded { skipTypingAnimation = true })
#if DEBUG || ALPHA
            .overlay(alignment: .topLeading) {
                RebrandingBadge()
                    .padding(.leading, onboardingTheme.linearOnboardingMetrics.rebrandingBadgeLeadingPadding)
                    .padding(.top, onboardingTheme.linearOnboardingMetrics.rebrandingBadgeTopPadding)
            }
#endif
            .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
            // Resync Dax when text size changes while backgrounded — body re-evaluates on
            // return but `currentDaxAnimation` is `@State` and would otherwise stay stale.
            .onChange(of: dynamicTypeSize) { newDynamicTypeSize in
                // `newDynamicTypeSize` (not `self.dynamicTypeSize`, which may still be stale).
                // Reset `lockedIntroBubbleHeight` so the next preference firing re-captures
                // at the new font size.
                lockedIntroBubbleHeight = 0
                currentDaxAnimation = activeDaxAnimation(for: newDynamicTypeSize)
                daxAnimationID += 1
                daxExiting = false
            }
            .onPreferenceChange(IntroBubbleHeightPreferenceKey.self) { introBubbleHeight = $0 }
            .onChange(of: introBubbleHeight) { newHeight in
                // Capture the first non-zero measurement; ignore later swaps inside the intro
                // bubble (otherwise Dax would resize when content swaps). Step-type guard:
                // preference also fires with 0 when intro unmounts.
                guard case let .onboarding(viewState) = model.state,
                      case .startOnboardingDialog = viewState.type else { return }
                guard lockedIntroBubbleHeight == 0, newHeight > 0 else { return }
                lockedIntroBubbleHeight = newHeight
                currentDaxAnimation = activeDaxAnimation
                daxExiting = false
            }
        }

        private func onboardingDialogView(state: ViewState.Intro) -> some View {
            let configuration = bubbleBackedDialogConfiguration(for: state.type)
            let isDuckAIQueryStep = if case .duckAIQueryDialog = state.type { true } else { false }

            return GeometryReader { geometry in
                let defaultTopPadding = onboardingTheme.linearOnboardingMetrics.minTopMargin + configuration.additionalTopMargin
                // On iPad we reduce the gap between dialog and background illustration by adding extra padding to the dialog by a percentage of screen height based on orientation.
                let platformSpecificTopPadding = geometry.size.height * BubbleBackedDialogMetrics.dialogVerticalOffsetPercentage.build(v: verticalSizeClass, h: horizontalSizeClass)
                let topPadding = defaultTopPadding + platformSpecificTopPadding

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center) {
                        bubbleBackedDialogView(state: state, configuration: configuration)
                            .animation(reduceMotion ? nil : .easeInOut(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration), value: state.type)
                            .frame(maxWidth: onboardingTheme.linearOnboardingMetrics.bubbleMaxWidth, alignment: .center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(width: geometry.size.width, alignment: .center)
                            .padding(.top, topPadding)
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: OnboardingDialogHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
                }
                .withoutScroll(dialogContentHeight <= geometry.size.height)
                .onPreferenceChange(OnboardingDialogHeightPreferenceKey.self) { height in
                    dialogContentHeight = height
                }
            }
            .padding()
            .opacity(isDuckAIQueryExitTransitionActive && isDuckAIQueryStep ? 0 : 1)
        }

        private func landingView(content: OnboardingLandingContent) -> some View {
            LandingView(
                content: content,
                animationNamespace: animationNamespace
            ) { [reduceMotion] in
                if reduceMotion {
                    model.onAppear()
                } else {
                    withAnimation { model.onAppear() }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        @ViewBuilder
        private func introView(content: OnboardingIntroStepContent, dialogType: ViewState.Intro.IntroDialogType) -> some View {
            let skipOnboardingView: AnyView? = if dialogType == .default {
                nil
            } else {
                AnyView(
                    SkipOnboardingContent(
                        content: content.skipFlowStepContent,
                        isVisible: $showBubbleContent,
                        startBrowsingAction: model.confirmSkipOnboardingAction,
                        resumeOnboardingAction: {
                            animateContentTransition {
                                model.startOnboardingAction(isResumingOnboarding: true)
                            }
                        }
                    )
                )
            }

            switch dialogType {
            case .restoreData:
                RestorePromptDialogContent(
                    content: content.restorePromptStepContent,
                    skipOnboardingView: skipOnboardingView,
                    isVisible: $showBubbleContent,
                    skipTypingAnimation: $skipTypingAnimation,
                    restoreAction: {
                        model.restoreSyncAccountAction()
                        animateContentTransition {
                            model.startOnboardingAction(isResumingOnboarding: false)
                        }
                    },
                    skipAction: {
                        model.restorePromptSkipAction()
                        model.skipOnboardingAction()
                    },
                    onSkipOnboardingPresented: {
                        model.skipOnboardingPresented()
                    }
                )
            case .skipTutorial, .default:
                IntroDialogContent(
                    content: content,
                    skipOnboardingView: skipOnboardingView,
                    isVisible: $showBubbleContent,
                    skipTypingAnimation: $skipTypingAnimation,
                    continueAction: {
                        animateContentTransition {
                            model.startOnboardingAction(isResumingOnboarding: false)
                        }
                    },
                    skipAction: model.skipOnboardingAction,
                    onSkipOnboardingPresented: {
                        model.skipOnboardingPresented()
                    }
                )
            }
        }

        private func browsersComparisonView(content: OnboardingBrowserComparisonContent) -> some View {
            BrowsersComparisonContent(
                content: content,
                isVisible: $showBubbleContent,
                setAsDefaultBrowserAction: model.setDefaultBrowserAction,
                cancelAction: {
                    animateContentTransition {
                        model.cancelSetDefaultBrowserAction()
                    }
                }
            )
        }

        private func aiComparisonView(content: OnboardingAIComparisonContent) -> some View {
            AIComparisonContent(
                content: content,
                isVisible: $showBubbleContent,
                continueAction: {
                    animateContentTransition {
                        model.aiComparisonAction()
                    }
                }
            )
        }

        private func bubbleBackedDialogView(
            state: ViewState.Intro,
            configuration: BubbleBackedDialogConfiguration
        ) -> some View {
            let isIntroStep: Bool = if case .startOnboardingDialog = state.type { true } else { false }
            return makeBubbleView(configuration: configuration, stepInfo: state.step) {
                VStack {
                    bubbleBackedDialogContent(for: state.type)
                        .opacity(showBubbleContent ? 1 : 0)
                }
            }
            // Propagates tap-to-skip to descendants' TypingText views.
            .environment(\.typingAnimationSkip, skipTypingAnimation)
            // Publishes the intro bubble's rendered height for inverse Dax scaling.
            .background {
                if isIntroStep {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: IntroBubbleHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
            .onAppear {
                animateContentTransition()
            }
        }

        /// Wraps content in a bubble with optional step counter. Always uses
        /// `withStepProgressIndicator` for stable view identity across steps.
        @ViewBuilder
        private func makeBubbleView<Content: View>(
            configuration: BubbleBackedDialogConfiguration,
            stepInfo: ViewState.Intro.StepInfo,
            @ViewBuilder content: @escaping () -> Content
        ) -> some View {
            // Leading tails are mirrored (theme 0.8 → 0.2 from left); trailing tails use the
            // offset directly. Hidden on compact viewports / AX text sizes.
            let tail: OnboardingBubbleView<Content>.TailPosition? = configuration.tail.flatMap { tail in
                guard !OnboardingBubbleAnimationMetrics.shouldHideBubbleTail(for: dynamicTypeSize) else { return nil }
                switch tail.direction {
                case .leading: return .bottom(offset: 1 - tail.offset, direction: .leading)
                case .trailing: return .bottom(offset: tail.offset, direction: .trailing)
                }
            }
            OnboardingBubbleView.withStepProgressIndicator(
                tailPosition: tail,
                currentStep: stepInfo.currentStep,
                totalSteps: stepInfo.totalSteps,
                isVisible: stepInfo != .hidden
            ) {
                content()
            }
        }

        @ViewBuilder
        private func bubbleBackedDialogContent(for type: ViewState.Intro.IntroType) -> some View {
            switch type {
            case let .startOnboardingDialog(content, dialogType):
                introView(content: content, dialogType: dialogType)
            case let .browsersComparisonDialog(content):
                browsersComparisonView(content: content)
            case let .aiComparisonDialog(content):
                aiComparisonView(content: content)
            case let .addToDockPromoDialog(content):
                addToDockPromoView(content: content)
            case let .chooseAppIconDialog(content):
                appIconPickerView(content: content)
            case let .chooseAddressBarPositionDialog(content):
                addressBarPositionView(content: content)
            case let .chooseSearchExperienceDialog(content):
                searchExperienceSelectionView(content: content)
            case let .duckAIQueryDialog(content, defaultMode):
                duckAIQuerySelectionView(content: content, defaultMode: defaultMode)
            }
        }

        private func addToDockPromoView(content: OnboardingAddToDockContent) -> some View {
            AddToDockPromoContent(
                content: content,
                isVisible: $showBubbleContent,
                showTutorialAction: {
                    // The child view manages its own hide/show sequence for the promo -> tutorial switch.
                    model.addToDockShowTutorialAction()
                    // The background doesn't change here, so animateContentTransition is not called.
                    // Trigger the Dax exit manually: starts simultaneously with the tutorial transition,
                    // then removes the overlay once the exit animation completes.
                    let exitDuration = content.daxAnimation.effectiveExitDuration
                    daxExiting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) {
                        daxExiting = false
                        currentDaxAnimation = nil
                        daxAnimationID += 1
                    }
                },
                dismissAction: { fromAddToDockTutorial in
                    animateContentTransition {
                        model.addToDockContinueAction(isShowingAddToDockTutorial: fromAddToDockTutorial)
                    }
                }
            )
        }

        private func appIconPickerView(content: OnboardingAppIconColorContent) -> some View {
            AppIconPickerContent(
                content: content,
                isVisible: $showBubbleContent,
                action: {
                    animateContentTransition {
                        model.appIconPickerContinueAction()
                    }
                }
            )
        }

        private func addressBarPositionView(content: OnboardingAddressBarPositionContent) -> some View {
            AddressBarPositionContent(
                content: content,
                isVisible: $showBubbleContent,
                action: {
                    animateContentTransition {
                        model.selectAddressBarPositionAction()
                    }
                }
            )
        }

        private func searchExperienceSelectionView(content: OnboardingSearchExperienceContent) -> some View {
            SearchExperienceContent(
                content: content,
                isVisible: $showBubbleContent,
                action: {
                    animateContentTransition {
                        model.selectSearchExperienceAction()
                    }
                }
            )
        }

        /// Dax animation for the current model state.
        private var activeDaxAnimation: DaxAnimation? {
            activeDaxAnimation(for: dynamicTypeSize)
        }

        /// Variant taking an explicit `DynamicTypeSize` so `.onChange` callers can pass the
        /// new value instead of the stale captured `self.dynamicTypeSize`.
        private func activeDaxAnimation(for dynamicTypeSize: DynamicTypeSize) -> DaxAnimation? {
            guard case let .onboarding(viewState) = model.state else { return nil }
            return daxAnimation(for: viewState.type, dynamicTypeSize: dynamicTypeSize)
        }

        /// `nil` when no animation is configured, the device is compact, or AX text sizes
        /// would make the inflated bubble overlap Dax.
        private func daxAnimation(
            for type: OnboardingView.ViewState.Intro.IntroType,
            dynamicTypeSize: DynamicTypeSize? = nil
        ) -> DaxAnimation? {
            let dynamicTypeSize = dynamicTypeSize ?? self.dynamicTypeSize
            guard !OnboardingBubbleAnimationMetrics.isCompactDevice else { return nil }
            guard !dynamicTypeSize.isAccessibilitySize else { return nil }
            switch type {
            // `lockedIntroBubbleHeight` (not the live value) keeps Dax stable across intro
            // bubble content swaps. Dax is scaled inversely to the bubble so they never overlap.
            case .startOnboardingDialog(let content, _):
                return scaledThumbUpAnimation(forBubbleHeight: lockedIntroBubbleHeight, base: content.daxAnimation)
            case .browsersComparisonDialog(let content):
                return content.daxAnimation
            case .aiComparisonDialog(let content):
                return content.daxAnimation
            case .addToDockPromoDialog(let content):
                return content.daxAnimation
            case .chooseAppIconDialog(let content):
                return content.daxAnimation
            case .chooseAddressBarPositionDialog(let content):
                return content.daxAnimation
            case .chooseSearchExperienceDialog(let content):
                return content.daxAnimation
            case .duckAIQueryDialog(let content, _):
                return content.daxAnimation
            }
        }

        /// Scales `base` inversely to the bubble height so Dax and the bubble never overlap.
        /// Returns `nil` when Dax would shrink below the minimum visible height.
        /// Only `size`, `position` bottom padding, and `exitOffset` are adjusted; all other
        /// params (animation name, entrance, timing) are taken from `base` unchanged.
        private func scaledThumbUpAnimation(forBubbleHeight bubbleHeight: CGFloat, base: DaxAnimation) -> DaxAnimation? {
            let referenceBubbleHeight: CGFloat = 280.0
            let minDaxHeight: CGFloat = 170.0

            let extraBubbleHeight = max(0, bubbleHeight - referenceBubbleHeight)
            let targetHeight = base.size.height - extraBubbleHeight
            guard targetHeight >= minDaxHeight else { return nil }

            let scale = targetHeight / base.size.height
            let size = CGSize(width: base.size.width * scale, height: targetHeight)

            guard case .left(let baseBottomPadding, let xOffset) = base.position else { return nil }
            let bottomPadding = baseBottomPadding * scale

            return DaxAnimation(
                animationName: base.animationName,
                size: size,
                position: .left(bottomPadding: bottomPadding, xOffset: xOffset),
                largeScreenPosition: .left(bottomPadding: bottomPadding, xOffset: 200.0),
                entranceOffset: base.entranceOffset,
                exitOffset: base.exitOffset.map { CGPoint(x: -size.width, y: $0.y) },
                exitDuration: base.exitDuration,
                fadeOut: base.fadeOut,
                startDelay: base.startDelay
            )
        }

        /// Hide → action → show sequence prevents cross-fading between steps.
        private func duckAIQuerySelectionView(content: OnboardingDuckAIQueryContent, defaultMode: DuckAIQueryMode) -> some View {
            LegacyOnboardingView.DuckAIQuerySearchContent(
                content: content,
                defaultMode: defaultMode,
                visualStyle: .rebranded,
                onModeConfirmed: model.selectDuckAIQueryAction(selection:),
                openAIChatAction: model.openAIChatFromOnboarding,
                openSearchAction: model.searchFromOnboarding,
                measureQuerySubmissionAction: model.measureDuckAIQuerySubmission,
                startExitTransitionAction: {
                    beginDuckAIQueryExitTransition()
                }
            )
        }

        /// Hide → optional action → show sequence for bubble content. If the current step's
        /// Dax has an exit (slide, fade, or two-stage), it plays in sync with the page
        /// transition and the overlay advances after `daxExitDuration`.
        ///
        /// - Parameter action: Closure run between hide and show (triggers the state change
        ///   and bubble resize). `nil` for the initial fade-in.
        private func animateContentTransition(action: (() -> Void)? = nil) {
            showBubbleContent = false

            // Read the currently-displayed animation (not the model-derived one) so e.g. the
            // add-to-dock promo→tutorial in-place swap, where the overlay is already cleared,
            // doesn't add an exit delay.
            let currentDax: DaxAnimation? = action != nil ? currentDaxAnimation : nil
            let daxExitDuration = currentDax?.effectiveExitDuration ?? OnboardingBubbleAnimationMetrics.daxExitDuration
            let hasAnyDaxExit = !reduceMotion && (
                currentDax?.hasSlideExit == true
                || currentDax?.hasFadeExit == true
                || currentDax?.hasTwoStagesExit == true
            )

            if action == nil {
                // Initial appearance: pin the overlay.
                skipTypingAnimation = false
                currentDaxAnimation = activeDaxAnimation
                daxPlayForward = true
                daxAnimationID += 1
            }

            // Reduced motion collapses every delay to zero.
            let actionDelay: TimeInterval = (action != nil && !reduceMotion) ? OnboardingBubbleAnimationMetrics.contentFadeOutDelay : 0

            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + actionDelay) {
                    skipTypingAnimation = false
                    if hasAnyDaxExit {
                        // Don't update `currentDaxAnimation` yet — the old animation must stay
                        // rendered while its exit plays, even after `model.state` moves on.
                        daxExiting = true
                        action()
                        DispatchQueue.main.asyncAfter(deadline: .now() + daxExitDuration) {
                            daxExiting = false
                            currentDaxAnimation = activeDaxAnimation
                            daxPlayForward = true
                            daxAnimationID += 1
                        }
                    } else {
                        action()
                        currentDaxAnimation = activeDaxAnimation
                        daxPlayForward = true
                        daxAnimationID += 1
                    }
                    // Bubble resize comes from `.animation(_, value: state.type)`, not here.
                }
            }

            // Reveal content once the bubble has finished resizing.
            let showDelay = reduceMotion ? 0 : (actionDelay + OnboardingBubbleAnimationMetrics.contentFadeInDelay)
            DispatchQueue.main.asyncAfter(deadline: .now() + showDelay) {
                if reduceMotion {
                    showBubbleContent = true
                } else {
                    withAnimation { showBubbleContent = true }
                }
            }
        }

        private func beginDuckAIQueryExitTransition() {
            if reduceMotion {
                isDuckAIQueryExitTransitionActive = true
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isDuckAIQueryExitTransitionActive = true
                }
            }
        }

    }

}

// MARK: - OnboardingView + Configuration

private extension OnboardingRebranding.OnboardingView {

    struct BubbleTail {
        /// Direction the bubble's tail arrow points toward.
        enum Direction {
            case leading
            case trailing
        }

        let offset: CGFloat
        let direction: BubbleTail.Direction
    }

    /// Per-step layout configuration for the bubble dialog (tail position, spacing, visibility).
    struct BubbleBackedDialogConfiguration {
        let tail: BubbleTail?
        var additionalTopMargin: CGFloat = 0
        let isVisible: Bool
    }

    func bubbleBackedDialogConfiguration(for type: ViewState.Intro.IntroType) -> BubbleBackedDialogConfiguration {
        let tailLeadingOffset = 0.7
        let tailTrailingOffset = 0.2
        switch type {
        case .startOnboardingDialog:
            return BubbleBackedDialogConfiguration(
                tailOffset: tailLeadingOffset,
                tailDirection: .leading,
                additionalTopMargin: BubbleBackedDialogMetrics.introAdditionalTopMargin,
                isVisible: model.introState.showIntroViewContent
            )
        case .browsersComparisonDialog, .aiComparisonDialog:
            return BubbleBackedDialogConfiguration(
                tailOffset: tailTrailingOffset,
                tailDirection: .leading,
                isVisible: true
            )
        case .addToDockPromoDialog:
            return BubbleBackedDialogConfiguration(
                tailOffset: tailLeadingOffset,
                tailDirection: .leading,
                isVisible: true
            )
        case .chooseAppIconDialog:
            return BubbleBackedDialogConfiguration(
                tailOffset: tailLeadingOffset,
                tailDirection: .trailing,
                isVisible: true
            )
        case .chooseAddressBarPositionDialog:
            return BubbleBackedDialogConfiguration(
                tailOffset: tailTrailingOffset,
                tailDirection: .leading,
                isVisible: true
            )
        case .chooseSearchExperienceDialog:
            return BubbleBackedDialogConfiguration(
                tailOffset: tailLeadingOffset,
                tailDirection: .leading,
                isVisible: true
            )
        case .duckAIQueryDialog:
            return BubbleBackedDialogConfiguration(
                tail: nil,
                additionalTopMargin: BubbleBackedDialogMetrics.searchExperienceAdditionalTopMargin,
                isVisible: true
            )
        }
    }
    
}

private extension OnboardingRebranding.OnboardingView.BubbleBackedDialogConfiguration {

    init(tailOffset: CGFloat, tailDirection: OnboardingRebranding.OnboardingView.BubbleTail.Direction, additionalTopMargin: CGFloat = 0, isVisible: Bool) {
        self.init(tail: .init(offset: tailOffset, direction: tailDirection), additionalTopMargin: additionalTopMargin, isVisible: isVisible)
    }

}

// MARK: - Bubble Visibility Typing Modifier

/// Visibility → typing pipeline used by every linear onboarding content view.
/// `isVisible` true → after `typingStartDelay`, sets `shouldStartTyping`.
/// `isVisible` false → resets both flags so the next appearance starts fresh.
struct OnboardingBubbleVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @Binding var shouldStartTyping: Bool
    @Binding var showContent: Bool
    /// Delay before typing starts. Callers whose bubble takes longer to settle (e.g. the
    /// scale-fading Intro dialog) can pass a larger value.
    var typingStartDelay: TimeInterval = OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration

    func body(content: Content) -> some View {
        content.onChange(of: isVisible) { showing in
            if showing {
                DispatchQueue.main.asyncAfter(deadline: .now() + typingStartDelay) {
                    shouldStartTyping = true
                }
            } else {
                shouldStartTyping = false
                showContent = false
            }
        }
    }
}

extension View {
    func onBubbleVisibilityChanged(
        isVisible: Binding<Bool>,
        shouldStartTyping: Binding<Bool>,
        showContent: Binding<Bool>,
        typingStartDelay: TimeInterval = OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration
    ) -> some View {
        modifier(
            OnboardingBubbleVisibilityModifier(
                isVisible: isVisible,
                shouldStartTyping: shouldStartTyping,
                showContent: showContent,
                typingStartDelay: typingStartDelay
            )
        )
    }
}

private struct RebrandingBadge: View {
    var body: some View {
        Text(verbatim: "REBRANDED")
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .foregroundColor(.white)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .accessibilityIdentifier("RebrandedBadge")
    }
}

private struct OnboardingDialogHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Carries the intro bubble's rendered height up so Dax can scale inversely (bigger bubble
/// → smaller Dax, hidden below the minimum).
private struct IntroBubbleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Custom Transitions

extension AnyTransition {
    /// Slides left and fades out, matching the `ScrollableOnboardingBackground` exit animation.
    static var slideLeftAndFade: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .modifier(
                active: SlideLeftAndFadeModifier(progress: 1.0),
                identity: SlideLeftAndFadeModifier(progress: 0.0)
            )
        )
    }
}

private struct SlideLeftAndFadeModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(x: -geometry.size.width * progress)
                // Fade at 2× the slide rate so the view is invisible by the halfway point.
                .opacity(max(0, 1.0 - progress * 2))
        }
    }
}
