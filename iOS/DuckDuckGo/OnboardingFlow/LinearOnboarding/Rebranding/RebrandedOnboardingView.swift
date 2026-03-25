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

/// Animation timing constants for the rebranded onboarding bubble dialogs.
///
/// The onboarding flow uses a two-level animation approach to create polished transitions:
///
/// 1. **Parent-level animations** (this view): Handles step-to-step transitions where the
///    bubble resizes and content changes (e.g., intro → browsers comparison).
///    - Bubble resizes with explicit duration
///    - Content hides, waits for resize, then fades in
///
/// 2. **Child-level animations** (individual content views): Some views have internal state
///    transitions that don't change `state.type` (e.g., showing skip dialog, tutorial overlay).
///    - Child views receive a `showContent` binding to control their visibility
///    - They manage their own hide/show sequencing using the parent's animation timing constants
enum OnboardingBubbleAnimationMetrics {
    /// How long the bubble takes to resize between steps
    static let bubbleResizeAnimationDuration: TimeInterval = 0.25
    /// How long to wait before triggering state change after content is hidden
    static let contentFadeOutDelay: TimeInterval = 0.15
    /// How long to wait before fading in new content (includes bubble resize duration plus buffer)
    static let contentFadeInDelay: TimeInterval = 0.3
}

extension OnboardingRebranding.OnboardingView {

    /// A theme-driven layout container for rebranded onboarding dialog steps.
    ///
    /// `LinearDialogContentContainer` arranges dialog content into a standardised vertical
    /// stack without applying any visual chrome (backgrounds, shadows, or mascot elements).
    /// The outer visual container — typically an ``OnboardingBubbleView`` — is responsible
    /// for the surrounding decoration; this view handles **inner layout only**.
    ///
    /// The layout is split into two top-level groups separated by ``Metrics/outerSpacing``:
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
    /// All spacing values are supplied through ``Metrics`` and should be sourced from the
    /// current ``OnboardingTheme`` to stay consistent with the 2026 design system.
    struct LinearDialogContentContainer<Title: View, Actions: View>: View {

        /// Spacing values that control the vertical gaps between each region of the container.
        struct Metrics {
            /// Spacing between the text group (title + message) and the content group (content + actions).
            let outerSpacing: CGFloat
            /// Spacing between the title and the optional message within the text group.
            let textSpacing: CGFloat
            /// Spacing between the optional content and the actions within the content group.
            let contentSpacing: CGFloat
            /// Additional top padding applied above the actions view.
            let actionsSpacing: CGFloat
        }

        private let metrics: Metrics
        private let message: AnyView?
        private let content: AnyView?
        private let title: Title
        private let actions: Actions

        /// Creates a new dialog content container.
        ///
        /// - Parameters:
        ///   - metrics: Spacing configuration sourced from the current onboarding theme.
        ///   - message: An optional subtitle or description displayed below the title.
        ///   - content: An optional main content area (e.g. an illustration, picker, or comparison table)
        ///              displayed above the action buttons.
        ///   - title: A view builder producing the primary heading.
        ///   - actions: A view builder producing the call-to-action buttons.
        init(
            metrics: Metrics,
            message: AnyView? = nil,
            content: AnyView? = nil,
            @ViewBuilder title: () -> Title,
            @ViewBuilder actions: () -> Actions
        ) {
            self.metrics = metrics
            self.message = message
            self.content = content
            self.title = title()
            self.actions = actions()
        }

        var body: some View {
            VStack(spacing: metrics.outerSpacing) {
                VStack(spacing: metrics.textSpacing) {
                    title

                    if let message {
                        message
                    }
                }

                VStack(spacing: metrics.contentSpacing) {
                    if let content {
                        content
                    }

                    actions
                        .padding(.top, metrics.actionsSpacing)
                }
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
        @Namespace var animationNamespace
        @ObservedObject private var model: OnboardingIntroViewModel
        @State private var dialogContentHeight: CGFloat = 0
        @State private var showBubbleContent: Bool = false

        init(model: OnboardingIntroViewModel) {
            self.model = model
        }

        /// Direction the bubble's tail arrow points toward.
        private enum BubbleTailDirection {
            case leading
            case trailing
        }

        /// Layout configuration for a bubble-backed onboarding dialog step.
        ///
        /// Each onboarding step that renders inside an ``OnboardingBubbleView`` uses this
        /// configuration to control the bubble's tail position, vertical placement, visibility,
        /// and whether a step progress indicator is shown.
        ///
        /// Steps that return `nil` from ``bubbleBackedDialogConfiguration(for:)`` fall through
        /// to the legacy Dax dialog path instead.
        private struct BubbleBackedDialogConfiguration {
            /// Horizontal offset of the bubble tail arrow from the leading/trailing edge.
            let tailOffset: CGFloat
            /// Which side the tail arrow points toward.
            let tailDirection: BubbleTailDirection
            /// Extra top padding added on top of the base minimum top margin.
            let additionalTopMargin: CGFloat
            /// Whether the dialog content is visible (used for entrance sequencing).
            let isVisible: Bool
            /// Whether to display the step progress indicator (e.g. "3 of 5").
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
            .overlay(alignment: .topLeading) {
                RebrandingBadge()
                    .padding(.leading, onboardingTheme.linearOnboardingMetrics.rebrandingBadgeLeadingPadding)
                    .padding(.top, onboardingTheme.linearOnboardingMetrics.rebrandingBadgeTopPadding)
            }
            .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
        }

        private func onboardingDialogView(state: ViewState.Intro) -> some View {
            let configuration = bubbleBackedDialogConfiguration(for: state.type)

            return GeometryReader { geometry in
                let defaultTopPadding = onboardingTheme.linearOnboardingMetrics.minTopMargin + configuration.additionalTopMargin
                // On iPad we reduce the gap between dialog and background illustration by adding extra padding to the dialog by a percentage of screen height based on orientation.
                let platformSpecificTopPadding = geometry.size.height * BubbleBackedDialogMetrics.dialogVerticalOffsetPercentage.build(v: verticalSizeClass, h: horizontalSizeClass)
                let topPadding = defaultTopPadding + platformSpecificTopPadding

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center) {
                        bubbleBackedDialogView(state: state, configuration: configuration)
                            .animation(.linear(duration: OnboardingBubbleAnimationMetrics.bubbleResizeAnimationDuration), value: state.type)
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
                    showContent: $showBubbleContent,
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
                    showContent: $showBubbleContent,
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
                showContent: $showBubbleContent,
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
            .onAppear {
                // Show content after initial bubble animation on first appearance
                animateContentTransition()
            }
        }

        @ViewBuilder
        private func makeBubbleView<Content: View>(
            configuration: BubbleBackedDialogConfiguration,
            stepInfo: ViewState.Intro.StepInfo,
            @ViewBuilder content: @escaping () -> Content
        ) -> some View {
            // Always use withStepProgressIndicator to maintain consistent view identity
            // Use isVisible to control whether the counter is shown
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
            switch type {
            case .startOnboardingDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.introAdditionalTopMargin,
                    isVisible: model.introState.showIntroViewContent,
                    showsStepCounter: false
                )
            case .browsersComparisonDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.browsersComparisonAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .addToDockPromoDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.addToDockAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .chooseAppIconDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .trailing,
                    additionalTopMargin: BubbleBackedDialogMetrics.appIconPickerAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .chooseAddressBarPositionDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.addressBarPositionAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: true
                )
            case .chooseSearchExperienceDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: onboardingTheme.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.searchExperienceAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: true
                )
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoContent(
                showContent: $showBubbleContent,
                showTutorialAction: {
                    // Don't use animateContentTransition here - the child handles it
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
                showContent: $model.appIconPickerContentState.showContent,
                action: {
                    animateContentTransition {
                        model.appIconPickerContinueAction()
                    }
                }
            )
        }

        private var addressBarPositionView: some View {
            AddressBarPositionContent(
                action: {
                    animateContentTransition {
                        model.selectAddressBarPositionAction()
                    }
                }
            )
        }

        private var searchExperienceSelectionView: some View {
            SearchExperienceContent(
                action: {
                    animateContentTransition {
                        model.selectSearchExperienceAction()
                    }
                }
            )
        }

        /// Animates bubble content with a hide → optional action → show sequence.
        ///
        /// This three-phase sequence prevents cross-fading between old and new content:
        /// 1. Hide current content immediately (no fade-out animation)
        /// 2. Optionally execute action after brief delay (triggers state change and bubble resize)
        /// 3. Show new content after bubble finishes resizing
        ///
        /// - Parameter action: Optional closure to execute between hiding and showing content.
        ///                     If nil, content is shown immediately after fade-in delay (for initial appearance).
        private func animateContentTransition(action: (() -> Void)? = nil) {
            // Phase 1: Hide current content immediately
            showBubbleContent = false

            if let action {
                // Phase 2: After content is hidden, trigger the action
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeOutDelay) {
                    // Call action without animation wrapper
                    // The bubble resize animation is handled by .animation(..., value: state.type) modifier on the bubble view
                    action()
                }

                // Phase 3: After bubble resize completes, show new content
                let totalDelay = OnboardingBubbleAnimationMetrics.contentFadeOutDelay + OnboardingBubbleAnimationMetrics.contentFadeInDelay
                DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
                    withAnimation {
                        showBubbleContent = true
                    }
                }
            } else {
                // First appearance of bubble. Show content after fade-in delay
                DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingBubbleAnimationMetrics.contentFadeInDelay) {
                    withAnimation {
                        showBubbleContent = true
                    }
                }
            }
        }

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
    /// Slides content to the left while fading out, matching the scrollable background exit animation.
    ///
    /// This transition mimics the behavior of `ExitingBackgroundView` in `ScrollableOnboardingBackground`,
    /// sliding the view until its trailing edge aligns with the screen's leading edge while fading out
    /// at twice the rate of the slide animation.
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
                // Slide left: at progress=1.0, trailing edge reaches screen's leading edge
                // Image is centered in frame, so: offset = -(screenWidth/2 + imageWidth/2)
                .offset(x: -(geometry.size.width / 2 + geometry.size.width / 2) * progress)
                // Fade out twice as fast as the slide, clamped to avoid negative opacity
                .opacity(max(0, 1.0 - progress * 2))
        }
    }
}
