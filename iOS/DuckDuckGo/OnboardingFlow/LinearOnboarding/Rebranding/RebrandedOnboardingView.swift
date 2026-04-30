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
    /// Reference screen size (iPhone 16 base: 390 × 844 pt).
    /// Dax animations and bubble tails are hidden on screens smaller than this.
    static let referenceScreenSize = CGSize(width: 390, height: 844)
    /// `true` when the device screen is smaller than `referenceScreenSize` in either dimension.
    /// On compact devices, Dax animations and bubble tails are hidden entirely.
    static var isCompactDevice: Bool {
        let size = windowSize
        return size.width < referenceScreenSize.width || size.height < referenceScreenSize.height
    }

    /// `true` when bubble tails should be suppressed: either the screen is compact (smaller
    /// than `referenceScreenSize`) or the user has selected an accessibility text size in iOS
    /// Settings → Accessibility → Display & Text Size → Larger Text. At those text sizes the
    /// inflated bubble loses anchoring relative to where Dax used to sit, so the tail loses
    /// its referent and becomes a stray decoration.
    static func shouldHideBubbleTail(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        isCompactDevice || dynamicTypeSize.isAccessibilitySize
    }

    /// Large-screen threshold (iPad Pro 13″ portrait: 1032 × 1376 pt).
    /// On large screens, Dax animation positions may be adjusted to avoid looking off-center.
    static let largeScreenThreshold = CGSize(width: 1000, height: 1300)

    /// `true` on large devices (e.g. iPad Pro 13″) where Dax positioning needs adjustment.
    static var isLargeScreen: Bool {
        let maxDimension = max(windowSize.width, windowSize.height)
        return maxDimension >= largeScreenThreshold.height
    }

    /// Current key window bounds, falling back to the first connected scene's window.
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
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        /// Drives Dax-animation sizing for the intro dialog so accessibility text sizes don't
        /// cause the inflated bubble to overlap Dax's head.
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Namespace var animationNamespace
        @ObservedObject private var model: OnboardingIntroViewModel
        @State private var dialogContentHeight: CGFloat = 0
        @State private var showBubbleContent: Bool = false
        @State private var skipTypingAnimation: Bool = false
        /// `true` → Dax plays forward (entrance); `false` → plays in reverse (exit).
        @State private var daxPlayForward = true
        /// Incrementing this ID forces `DaxAnimationOverlay` to recreate and restart from the correct frame.
        @State private var daxAnimationID = 0
        /// `true` while the current Dax overlay is animating its exit; reset alongside `daxAnimationID`.
        @State private var daxExiting = false
        /// The animation currently displayed by the overlay. Updated explicitly so the old overlay
        /// stays alive (and can play its exit) even after the model state has moved to the next step.
        @State private var currentDaxAnimation: DaxAnimation?
        @State private var isExperimentExitTransitionActive = false

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
            var additionalTopMargin: CGFloat = 0
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

                    // Render-path guard against stale `@State`. `currentDaxAnimation` is captured
                    // at step transitions (see `animateContentTransition`); when the user changes
                    // the system text size while backgrounded the `.onChange(of: dynamicTypeSize)`
                    // below resyncs it, but reading the environment directly here makes the
                    // accessibility-size suppression authoritative on the render itself — even
                    // if the closure runs after this body re-evaluates.
                    if let dax = currentDaxAnimation, !dynamicTypeSize.isAccessibilitySize {
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
            // When the user changes the system text size (Settings → Accessibility → Display &
            // Text Size → Larger Text) while the app is backgrounded, returning to the app only
            // re-evaluates the body — but `currentDaxAnimation` is `@State` and stays whatever
            // value was captured at the last step transition. Without this, switching to/from an
            // accessibility size won't add/remove Dax (or update its scale at xxLarge/xxxLarge).
            // Recompute against the new environment and bump the overlay ID so the Lottie view
            // is recreated rather than reusing the previous frame's geometry.
            .onChange(of: dynamicTypeSize) { newDynamicTypeSize in
                // Use the new value passed by SwiftUI rather than `self.dynamicTypeSize`: when
                // the closure runs, the captured `self` can still expose the previous env value,
                // which would otherwise make `activeDaxAnimation` return the wrong answer (and
                // either leave Dax stranded or fail to bring it back when leaving an AX size).
                currentDaxAnimation = activeDaxAnimation(for: newDynamicTypeSize)
                daxAnimationID += 1
                daxExiting = false
            }
        }

        private func onboardingDialogView(state: ViewState.Intro) -> some View {
            let configuration = bubbleBackedDialogConfiguration(for: state.type)
            let isExperimentSearchStep = if case .duckAIQueryExperimentDialog = state.type { true } else { false }

            return GeometryReader { geometry in
                let defaultTopPadding = onboardingTheme.linearOnboardingMetrics.minTopMargin + configuration.additionalTopMargin
                // On iPad we reduce the gap between dialog and background illustration by adding extra padding to the dialog by a percentage of screen height based on orientation.
                let platformSpecificTopPadding = geometry.size.height * BubbleBackedDialogMetrics.dialogVerticalOffsetPercentage.build(v: verticalSizeClass, h: horizontalSizeClass)
                let topPadding = defaultTopPadding + platformSpecificTopPadding

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center) {
                        bubbleBackedDialogView(state: state, configuration: configuration)
                            .animation(.easeInOut(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration), value: state.type)
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
            .opacity(isExperimentExitTransitionActive && isExperimentSearchStep ? 0 : 1)
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
            // Tail is hidden on compact devices (screens smaller than iPhone 16) and on
            // accessibility text sizes (where the inflated bubble has no fixed anchor for the
            // tail to point at). On standard devices it sits on the bottom edge; the offset is
            // mirrored for leading tails (theme 0.8 → 0.2 from left) and used directly for trailing.
            let tail: OnboardingBubbleView<Content>.TailPosition? = OnboardingBubbleAnimationMetrics.shouldHideBubbleTail(for: dynamicTypeSize) ? nil : {
                switch configuration.tailDirection {
                case .leading: return .bottom(offset: 1 - configuration.tailOffset, direction: .leading)
                case .trailing: return .bottom(offset: configuration.tailOffset, direction: .trailing)
                }
            }()
            OnboardingBubbleView.withStepProgressIndicator(
                tailPosition: tail,
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
            case .duckAIQueryExperimentDialog(let defaultMode):
                experimentSearchExperienceSelectionView(defaultMode: defaultMode)
            }
        }

        private func bubbleBackedDialogConfiguration(for type: ViewState.Intro.IntroType) -> BubbleBackedDialogConfiguration {
            let tailLeadingOffset = 0.7
            let tailTrailingOffset = 0.2
            switch type {
            case .startOnboardingDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailLeadingOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.introAdditionalTopMargin,
                    isVisible: model.introState.showIntroViewContent,
                    showsStepCounter: false
                )
            case .chooseAppIconDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailLeadingOffset,
                    tailDirection: .trailing,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .browsersComparisonDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailTrailingOffset,
                    tailDirection: .leading,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .addToDockPromoDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailLeadingOffset,
                    tailDirection: .leading,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .chooseAddressBarPositionDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailTrailingOffset,
                    tailDirection: .leading,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .chooseSearchExperienceDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: tailLeadingOffset,
                    tailDirection: .leading,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .duckAIQueryExperimentDialog:
                return BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.searchExperienceAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: false
                )
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoContent(
                isVisible: $showBubbleContent,
                showTutorialAction: {
                    // The child view manages its own hide/show sequence for the promo -> tutorial switch.
                    model.addToDockShowTutorialAction()
                    // The background doesn't change here, so animateContentTransition is not called.
                    // Trigger the Dax exit manually: starts simultaneously with the tutorial transition,
                    // then removes the overlay once the exit animation completes.
                    let exitDuration = AddToDockPromoContent.daxAnimation.effectiveExitDuration
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

        /// Returns the `DaxAnimation` for the current model state, or `nil`.
        /// Called after a state change to advance `currentDaxAnimation` to the next step.
        private var activeDaxAnimation: DaxAnimation? {
            activeDaxAnimation(for: dynamicTypeSize)
        }

        /// Variant that accepts an explicit `DynamicTypeSize`. Used by the dynamic-type-change
        /// handler, which must not rely on `self.dynamicTypeSize` — when SwiftUI invokes the
        /// `.onChange(of: dynamicTypeSize)` closure, the captured `self` can still hold the
        /// previous environment value, which produces a wrong `daxAnimation(for:)` answer.
        private func activeDaxAnimation(for dynamicTypeSize: DynamicTypeSize) -> DaxAnimation? {
            guard case let .onboarding(viewState) = model.state else { return nil }
            return daxAnimation(for: viewState.type, dynamicTypeSize: dynamicTypeSize)
        }

        /// Returns the `DaxAnimation` for the given step, or `nil` if no animation is configured,
        /// the device screen is smaller than the reference size (iPhone 16), or the user has
        /// chosen an accessibility text size — at those text sizes the inflated dialog bubble
        /// would otherwise overlap the animation.
        ///
        /// `dynamicTypeSize` defaults to the view's current environment value but can be
        /// overridden so callers reacting to an environment change can pass the *new* value
        /// (avoiding stale-`self` reads from inside `.onChange` closures).
        private func daxAnimation(
            for type: OnboardingView.ViewState.Intro.IntroType,
            dynamicTypeSize: DynamicTypeSize? = nil
        ) -> DaxAnimation? {
            let dynamicTypeSize = dynamicTypeSize ?? self.dynamicTypeSize
            guard !OnboardingBubbleAnimationMetrics.isCompactDevice else { return nil }
            guard !dynamicTypeSize.isAccessibilitySize else { return nil }
            switch type {
            case .startOnboardingDialog: return IntroDialogContent.daxAnimation(for: dynamicTypeSize)
            case .browsersComparisonDialog: return BrowsersComparisonContent.daxAnimation
            case .addToDockPromoDialog: return AddToDockPromoContent.daxAnimation
            case .chooseAppIconDialog: return AppIconPickerContent.daxAnimation
            case .chooseAddressBarPositionDialog: return nil // Dax-Floating is embedded in ScrollableOnboardingBackground
            case .chooseSearchExperienceDialog: return SearchExperienceContent.daxAnimation
            case .duckAIQueryExperimentDialog: return nil
            }
        }

        /// Animates a hide -> action -> show sequence to prevent cross-fading between steps.
        private func experimentSearchExperienceSelectionView(defaultMode: DuckAIQueryExperimentMode) -> some View {
            LegacyOnboardingView.DuckAIExperimentSearchContent(
                defaultMode: defaultMode,
                visualStyle: .rebranded,
                onModeConfirmed: model.selectDuckAIQueryExperimentAction(selection:),
                openAIChatAction: model.openAIChatFromOnboarding,
                openSearchAction: model.searchFromOnboarding,
                measureQuerySubmissionAction: model.measureDuckAIQueryExperimentQuerySubmission,
                startExitTransitionAction: {
                    beginExperimentExitTransition()
                }
            )
        }

        /// Animates bubble content with a hide → optional action → show sequence.
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
            // Use `currentDaxAnimation` (what's actually displayed) instead of deriving from the model state,
            // so transitions where the overlay was already cleared (e.g. promo→tutorial within add-to-dock)
            // don't trigger an unnecessary daxExitDuration delay.
            let currentDax: DaxAnimation? = action != nil ? currentDaxAnimation : nil
            let daxExitDuration = currentDax?.effectiveExitDuration ?? OnboardingBubbleAnimationMetrics.daxExitDuration
            let hasAnyDaxExit = currentDax?.hasSlideExit == true
                || currentDax?.hasFadeExit == true
                || currentDax?.hasTwoStagesExit == true

            if action == nil {
                // Initial appearance — pin the overlay to the current step and reset Dax.
                currentDaxAnimation = activeDaxAnimation
                daxPlayForward = true
                daxAnimationID += 1
            }

            // All exit animations (slide, fade, or both) start simultaneously with the page
            // transition — no pre-transition delay is added.
            let actionDelay: TimeInterval = action != nil ? OnboardingBubbleAnimationMetrics.contentFadeOutDelay : 0

            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + actionDelay) {
                    if hasAnyDaxExit {
                        // Trigger exit animations in sync with the page transition.
                        // currentDaxAnimation is intentionally NOT updated here — keeping it
                        // pinned to the old step's animation keeps the overlay alive so it can
                        // finish its exit even after model.state has moved to the next step.
                        daxExiting = true
                        action()
                        DispatchQueue.main.asyncAfter(deadline: .now() + daxExitDuration) {
                            // Exit complete — advance the overlay to the new step.
                            daxExiting = false
                            currentDaxAnimation = activeDaxAnimation
                            daxPlayForward = true
                            daxAnimationID += 1
                        }
                    } else {
                        // No exit animation — advance the overlay atomically with the state change.
                        action()
                        currentDaxAnimation = activeDaxAnimation
                        daxPlayForward = true
                        daxAnimationID += 1
                    }
                    // No withAnimation -- the bubble resize is driven by .animation(..., value: state.type).
                }
            }

            // Show new content after the bubble has finished resizing.
            let showDelay = actionDelay + OnboardingBubbleAnimationMetrics.contentFadeInDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + showDelay) {
                withAnimation { showBubbleContent = true }
            }
        }

        private func beginExperimentExitTransition() {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExperimentExitTransitionActive = true
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
