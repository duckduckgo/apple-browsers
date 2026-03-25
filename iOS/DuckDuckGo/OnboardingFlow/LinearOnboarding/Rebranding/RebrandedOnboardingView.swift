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

private enum BubbleBackedDialogMetrics {
    /// Extra top margin for the intro step; all other steps use 0.
    static let introAdditionalTopMargin: CGFloat = 40
}

/// Shared timing constants for the two-level bubble animation system:
/// - **Parent level**: step-to-step transitions (bubble resize + content swap).
/// - **Child level**: in-place sub-view transitions (e.g. promo -> tutorial) that
///   reuse the same timing to stay visually consistent.
enum OnboardingBubbleAnimationMetrics {
    /// How long the bubble takes to resize between steps
    static let bubbleResizeAnimationDuration: TimeInterval = 0.25
    /// How long to wait before triggering state change after content is hidden
    static let contentFadeOutDelay: TimeInterval = 0.15
    /// How long to wait before fading in new content (includes bubble resize duration plus buffer)
    static let contentFadeInDelay: TimeInterval = 0.3
    /// Duration of the default SwiftUI fade-in animation applied when showing bubble content
    static let contentFadeInAnimationDuration: TimeInterval = 0.35
    /// Duration of the Dax slide-in entrance animation
    static let daxEntranceDuration: TimeInterval = 0.5
    /// Duration of the Dax slide-out exit animation; parent must delay overlay removal by this amount
    static let daxExitDuration: TimeInterval = 0.5
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

                VStack(spacing: metrics.outerSpacing) {
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
                .animation(.easeIn(duration: 0.25), value: showContent.wrappedValue)
            }
        }

    }

}

// MARK: - Main View

extension OnboardingRebranding {

    struct OnboardingView: View {

        typealias ViewState = LegacyOnboardingViewState

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Namespace var animationNamespace
        @ObservedObject private var model: OnboardingIntroViewModel
        @State private var dialogContentHeight: CGFloat = 0
        @State private var showBubbleContent: Bool = false
        @State private var skipTypingAnimation: Bool = false
        /// `true` → Dax plays forward (entrance); `false` → plays in reverse (exit).
        @State private var daxPlayForward = true
        /// Incrementing this ID forces `DaxAnimationOverlay` to recreate and restart from the correct frame.
        @State private var daxAnimationID = 0
        /// `true` while the current Dax overlay is sliding out; reset to `false` alongside `daxAnimationID`.
        @State private var daxExiting = false

        init(model: OnboardingIntroViewModel) {
            self.model = model
        }

        /// Direction the bubble's tail arrow points toward.
        private enum BubbleTailDirection {
            case leading
            case trailing
        }

        /// Per-step layout configuration for the bubble dialog (tail position, spacing, visibility).
        private struct BubbleBackedDialogConfiguration {
            let tailOffset: CGFloat
            let tailDirection: BubbleTailDirection
            let additionalTopMargin: CGFloat
            let isVisible: Bool
            let showsStepCounter: Bool
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                switch model.state {
                case .landing:
                    onboardingTheme.colorPalette.background
                        .ignoresSafeArea()

                    landingView
                        .transition(AnyTransition.slideLeftAndFade.animation(.easeOut(duration: 1.0)))
                case let .onboarding(viewState):
                    onboardingTheme.colorPalette.background
                        .ignoresSafeArea()

                    ScrollableOnboardingBackground(viewState: viewState)

                    if let dax = daxAnimation(for: viewState.type) {
                        DaxAnimationOverlay(animation: dax, playForward: daxPlayForward, isExiting: daxExiting)
                            // Combine animationID + name so the view is recreated on both:
                            // - direction changes (same step, forward → reverse)
                            // - step transitions where the animation asset changes
                            .id("\(daxAnimationID)-\(dax.animationName)")
                    }

                    onboardingDialogView(state: viewState)
                        .transition( // Scale content from 0.1 to 1.0 and fade in when appearing for the first time
                            .scale.combined(with: .opacity)
                        )
#if DEBUG || ALPHA
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                model.overrideOnboardingCompleted()
                            } label: {
                                Text(UserText.Onboarding.Intro.Debug.skip)
                            }
                            .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
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
        }

        private func onboardingDialogView(state: ViewState.Intro) -> some View {
            let configuration = bubbleBackedDialogConfiguration(for: state.type)

            return GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center) {
                        bubbleBackedDialogView(state: state, configuration: configuration)
                            .animation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration), value: state.type)
                            .frame(maxWidth: onboardingTheme.linearOnboardingMetrics.bubbleMaxWidth, alignment: .center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(width: geometry.size.width, alignment: .center)
                            .padding(.top, onboardingTheme.linearOnboardingMetrics.minTopMargin + configuration.additionalTopMargin)
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
        }

        private var landingView: some View {
            LandingView(animationNamespace: animationNamespace) {
                withAnimation {
                    model.onAppear()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        @ViewBuilder
        private func introView(dialogType: ViewState.Intro.IntroDialogType) -> some View {
            let skipOnboardingView: AnyView? = if dialogType == .default {
                nil
            } else {
                AnyView(
                    SkipOnboardingContent(
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
                    skipOnboardingView: skipOnboardingView,
                    isVisible: $showBubbleContent,
                    restoreAction: {
                        model.restoreSyncAccountAction()
                        animateContentTransition {
                            model.startOnboardingAction(isResumingOnboarding: false)
                        }
                    },
                    skipAction: {
                        model.restorePromptSkipAction()
                        model.skipOnboardingAction()
                    }
                )
            case .skipTutorial, .default:
                IntroDialogContent(
                    title: UserText.Onboarding.Rebranding.Intro.title,
                    message: UserText.Onboarding.Rebranding.Intro.message,
                    skipOnboardingView: skipOnboardingView,
                    isVisible: $showBubbleContent,
                    continueAction: {
                        animateContentTransition {
                            model.startOnboardingAction(isResumingOnboarding: false)
                        }
                    },
                    skipAction: model.skipOnboardingAction
                )
            }
        }

        private var browsersComparisonView: some View {
            BrowsersComparisonContent(
                isVisible: $showBubbleContent,
                title: UserText.Onboarding.BrowsersComparison.title,
                setAsDefaultBrowserAction: model.setDefaultBrowserAction,
                cancelAction: {
                    animateContentTransition {
                        model.cancelSetDefaultBrowserAction()
                    }
                }
            )
        }

        private func bubbleBackedDialogView(
            state: ViewState.Intro,
            configuration: BubbleBackedDialogConfiguration
        ) -> some View {
            let stepInfo: ViewState.Intro.StepInfo = if configuration.showsStepCounter {
                .init(currentStep: state.step.currentStep, totalSteps: state.step.totalSteps)
            } else {
                .hidden
            }
            return makeBubbleView(configuration: configuration, stepInfo: stepInfo) {
                VStack {
                    bubbleBackedDialogContent(for: state.type)
                        .opacity(showBubbleContent ? 1 : 0)
                }
            }
            // Propagates the tap-to-skip flag to all TypingText views in the subtree.
            .environment(\.typingAnimationSkip, skipTypingAnimation)
            .onAppear {
                animateContentTransition()
            }
        }

        /// Wraps content in a bubble view with an optional step counter.
        /// Always uses `withStepProgressIndicator` to keep a stable view identity across steps;
        /// `isVisible` on the configuration hides the counter when not needed.
        @ViewBuilder
        private func makeBubbleView<Content: View>(
            configuration: BubbleBackedDialogConfiguration,
            stepInfo: ViewState.Intro.StepInfo,
            @ViewBuilder content: @escaping () -> Content
        ) -> some View {
            OnboardingBubbleView.withStepProgressIndicator(
                currentStep: stepInfo.currentStep,
                totalSteps: stepInfo.totalSteps,
                isVisible: configuration.showsStepCounter
            ) {
                content()
            }
        }

        @ViewBuilder
        private func bubbleBackedDialogContent(for type: ViewState.Intro.IntroType) -> some View {
            switch type {
            case .startOnboardingDialog(let dialogType):
                introView(dialogType: dialogType)
            case .browsersComparisonDialog:
                browsersComparisonView
            case .addToDockPromoDialog:
                addToDockPromoView
            case .chooseAppIconDialog:
                appIconPickerView
            case .chooseAddressBarPositionDialog:
                addressBarPositionView
            case .chooseSearchExperienceDialog:
                searchExperienceSelectionView
            }
        }

        private func bubbleBackedDialogConfiguration(for type: ViewState.Intro.IntroType) -> BubbleBackedDialogConfiguration {
            let tailOffset = onboardingTheme.linearOnboardingMetrics.bubbleTailOffset

            switch type {
            case .startOnboardingDialog:
                // Intro is the only step with extra top margin and no step counter.
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.introAdditionalTopMargin,
                    isVisible: model.introState.showIntroViewContent,
                    showsStepCounter: false
                )
            case .chooseAppIconDialog:
                // App icon picker points the tail to the trailing side.
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailOffset,
                    tailDirection: .trailing,
                    additionalTopMargin: 0,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .browsersComparisonDialog, .addToDockPromoDialog, .chooseAddressBarPositionDialog, .chooseSearchExperienceDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: 0,
                    isVisible: true,
                    showsStepCounter: true
                )
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoContent(
                isVisible: $showBubbleContent,
                showTutorialAction: {
                    // The child view manages its own hide/show sequence for the promo -> tutorial switch.
                    model.addToDockShowTutorialAction()
                },
                dismissAction: { fromAddToDockTutorial in
                    animateContentTransition {
                        model.addToDockContinueAction(isShowingAddToDockTutorial: fromAddToDockTutorial)
                    }
                }
            )
        }

        private var appIconPickerView: some View {
            AppIconPickerContent(
                isVisible: $showBubbleContent,
                action: {
                    animateContentTransition {
                        model.appIconPickerContinueAction()
                    }
                }
            )
        }

        private var addressBarPositionView: some View {
            AddressBarPositionContent(
                isVisible: $showBubbleContent,
                action: {
                    animateContentTransition {
                        model.selectAddressBarPositionAction()
                    }
                }
            )
        }

        private var searchExperienceSelectionView: some View {
            SearchExperienceContent(
                isVisible: $showBubbleContent,
                action: {
                    animateContentTransition {
                        model.selectSearchExperienceAction()
                    }
                }
            )
        }

        /// Returns the `DaxAnimation` for the given step, or `nil` if no animation is configured.
        private func daxAnimation(for type: OnboardingView.ViewState.Intro.IntroType) -> DaxAnimation? {
            switch type {
            case .startOnboardingDialog: return IntroDialogContent.daxAnimation
            case .browsersComparisonDialog: return BrowsersComparisonContent.daxAnimation
            default: return nil
            }
        }

        /// Reverses the current step's Dax animation (plays from last frame back to first).
        ///
        /// Call this in response to a user interaction that should animate Dax out.
        /// The animation plays once in reverse and stops on the first frame.
        func reverseDaxAnimation() {
            daxPlayForward = false
            daxAnimationID += 1
        }

        /// Animates a hide -> action -> show sequence to prevent cross-fading between steps.
        ///
        /// If the current step's `DaxAnimation` has an `exitOffset`, Dax slides off-screen first;
        /// all subsequent delays are shifted by `OnboardingBubbleAnimationMetrics.daxExitDuration`.
        ///
        /// - Parameter action: Closure executed between hide and show (triggers state change and
        ///   bubble resize). Pass `nil` for the initial appearance where only a fade-in is needed.
        private func animateContentTransition(action: (() -> Void)? = nil) {
            // Reset immediately: hide content and clear the typing-skip flag for the next step.
            showBubbleContent = false
            skipTypingAnimation = false

            // Dax exit only applies during step transitions (action != nil).
            // On initial appearance (action == nil) the overlay is just being created — no exit needed.
            let currentDax: DaxAnimation? = action != nil ? {
                guard case let .onboarding(viewState) = model.state else { return nil }
                return daxAnimation(for: viewState.type)
            }() : nil
            let hasDaxExit = currentDax?.exitOffset != nil

            if hasDaxExit {
                // Trigger the slide-out; the overlay stays alive for daxExitDuration.
                daxExiting = true
                // After exit completes, swap in the overlay for the next step.
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.daxExitDuration) {
                    daxExiting = false   // new overlay starts with isExiting = false
                    daxPlayForward = true
                    daxAnimationID += 1
                }
            } else {
                // No exit animation (or initial appearance) — swap immediately.
                daxPlayForward = true
                daxAnimationID += 1
            }

            let daxExitDelay: TimeInterval = hasDaxExit ? OnboardingBubbleAnimationMetrics.daxExitDuration : 0

            // When there is an action, insert a fade-out delay before executing it so the
            // old content is invisible before the bubble starts resizing.
            let actionDelay = daxExitDelay + (action != nil ? OnboardingBubbleAnimationMetrics.contentFadeOutDelay : 0)

            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + actionDelay) {
                    // No withAnimation -- the bubble resize is driven by .animation(..., value: state.type).
                    action()
                }
            }

            // Show new content after the bubble has finished resizing.
            let showDelay = actionDelay + OnboardingBubbleAnimationMetrics.contentFadeInDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + showDelay) {
                withAnimation { showBubbleContent = true }
            }
        }

    }

}

// MARK: - Bubble Visibility Typing Modifier

/// Applies the standard visibility → typing pipeline used by all linear onboarding content views.
/// When `isVisible` becomes `true`, delays by `contentFadeInAnimationDuration` then sets `shouldStartTyping = true`.
/// When `isVisible` becomes `false`, resets both flags so the next appearance starts fresh.
struct OnboardingBubbleVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool
    @Binding var shouldStartTyping: Bool
    @Binding var showContent: Bool

    func body(content: Content) -> some View {
        content.onChange(of: isVisible) { showing in
            if showing {
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInAnimationDuration) {
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
        showContent: Binding<Bool>
    ) -> some View {
        modifier(OnboardingBubbleVisibilityModifier(isVisible: isVisible, shouldStartTyping: shouldStartTyping, showContent: showContent))
    }
}

private struct RebrandingBadge: View {
    var body: some View {
        Text("REBRANDED")
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
                // Slide the view fully off-screen to the left (its own width).
                .offset(x: -geometry.size.width * progress)
                // Fade out at 2x the slide rate so the view is invisible by the halfway point.
                .opacity(max(0, 1.0 - progress * 2))
        }
    }
}
