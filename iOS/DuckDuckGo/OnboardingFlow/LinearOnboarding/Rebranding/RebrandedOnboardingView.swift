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

import SwiftUI
import Onboarding
import DuckUI

private enum OnboardingViewMetrics {
    static let landingScreenDuration = 2.0
}

private enum OnboardingViewCopy {
    static let introTitle = "Hi There!"
    static let introMessage = "Ready for a faster browser that keeps you protected?"
    static let browsersComparisonTitle = "Protections activated!"
}

private enum BubbleBackedDialogMetrics {
    static let introAdditionalTopMargin: CGFloat = 40
    static let browsersComparisonAdditionalTopMargin: CGFloat = 0
    static let addressBarPositionAdditionalTopMargin: CGFloat = 0
    static let searchExperienceAdditionalTopMargin: CGFloat = 0
    static let addToDockAdditionalTopMargin: CGFloat = 0
    static let appIconPickerAdditionalTopMargin: CGFloat = 0
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

        static let daxGeometryEffectID = "DaxIcon"

        @Environment(\.onboardingTheme) private var onboardingTheme
        @Namespace var animationNamespace
        @ObservedObject private var model: OnboardingIntroViewModel
        @State private var dialogContentHeight: CGFloat = 0

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
                onboardingTheme.colorPalette.background
                    .ignoresSafeArea()

                switch model.state {
                case .landing:
                    landingView
                case let .onboarding(viewState):
                    onboardingDialogView(state: viewState)
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
            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center) {
                        let bubbleConfiguration = bubbleBackedDialogConfiguration(for: state.type)
                        bubbleBackedDialogView(state: state, configuration: bubbleConfiguration)
                            .frame(width: geometry.size.width, alignment: .center)
                            .padding(.top, onboardingTheme.linearOnboardingMetrics.minTopMargin + bubbleConfiguration.additionalTopMargin)
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
            LandingView(animationNamespace: animationNamespace)
                .ignoresSafeArea(edges: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingViewMetrics.landingScreenDuration) {
                        model.onAppear()
                    }
                }
        }

        private func introView(shouldShowSkipOnboardingButton: Bool) -> some View {
            let skipOnboardingView: AnyView? = if shouldShowSkipOnboardingButton {
                AnyView(
                    SkipOnboardingContent(
                        startBrowsingAction: model.confirmSkipOnboardingAction,
                        resumeOnboardingAction: {
                            animateBrowserComparisonViewState(isResumingOnboarding: true)
                        }
                    )
                )
            } else {
                nil
            }

            return IntroDialogContent(
                title: OnboardingViewCopy.introTitle,
                message: OnboardingViewCopy.introMessage,
                skipOnboardingView: skipOnboardingView,
                showCTA: $model.introState.showIntroButton,
                continueAction: {
                    animateBrowserComparisonViewState(isResumingOnboarding: false)
                },
                skipAction: model.skipOnboardingAction
            )
        }

        private var browsersComparisonView: some View {
            BrowsersComparisonContent(
                title: OnboardingViewCopy.browsersComparisonTitle,
                setAsDefaultBrowserAction: model.setDefaultBrowserAction,
                cancelAction: model.cancelSetDefaultBrowserAction
            )
        }

        private func bubbleBackedDialogView(
            state: ViewState.Intro,
            configuration: BubbleBackedDialogConfiguration
        ) -> some View {
            let stepInfo: ViewState.Intro.StepInfo? = if configuration.showsStepCounter {
                .init(currentStep: state.step.currentStep, totalSteps: state.step.totalSteps)
            } else {
                nil
            }
            return makeBubbleView(configuration: configuration, stepInfo: stepInfo) {
                bubbleBackedDialogContent(for: state.type)
            }
            .frame(maxWidth: onboardingTheme.linearOnboardingMetrics.bubbleMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .visibility(configuration.isVisible ? .visible : .invisible)
        }

        @ViewBuilder
        private func makeBubbleView<Content: View>(
            configuration: BubbleBackedDialogConfiguration,
            stepInfo: ViewState.Intro.StepInfo?,
            @ViewBuilder content: @escaping () -> Content
        ) -> some View {
            let tailPosition: OnboardingBubbleView<Content>.TailPosition = switch configuration.tailDirection {
            case .leading:
                .bottom(offset: configuration.tailOffset, direction: .leading)
            case .trailing:
                .bottom(offset: configuration.tailOffset, direction: .trailing)
            }

            if let stepInfo {
                OnboardingBubbleView.withStepProgressIndicator(
                    tailPosition: tailPosition,
                    currentStep: stepInfo.currentStep,
                    totalSteps: stepInfo.totalSteps
                ) {
                    content()
                }
            } else {
                OnboardingBubbleView(
                    tailPosition: tailPosition,
                    contentInsets: onboardingTheme.linearBubbleMetrics.contentInsets,
                    arrowLength: onboardingTheme.linearBubbleMetrics.arrowLength,
                    arrowWidth: onboardingTheme.linearBubbleMetrics.arrowWidth
                ) {
                    content()
                }
            }
        }

        @ViewBuilder
        private func bubbleBackedDialogContent(for type: ViewState.Intro.IntroType) -> some View {
            switch type {
            case .startOnboardingDialog(let shouldShowSkipOnboardingButton):
                introView(shouldShowSkipOnboardingButton: shouldShowSkipOnboardingButton)
            case .browsersComparisonDialog:
                browsersComparisonView
            case .addToDockPromoDialog:
                addToDockPromoView
            case .chooseAddressBarPositionDialog:
                addressBarPositionView
            case .chooseSearchExperienceDialog:
                searchExperienceSelectionView
            case .chooseAppIconDialog:
                appIconPickerView
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
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoContent(
                isAnimating: $model.addToDockState.isAnimating,
                showTutorialAction: {
                    model.addToDockShowTutorialAction()
                },
                dismissAction: { fromAddToDockTutorial in
                    model.addToDockContinueAction(isShowingAddToDockTutorial: fromAddToDockTutorial)
                }
            )
        }

        private var appIconPickerView: some View {
            AppIconPickerContent(
                showContent: $model.appIconPickerContentState.showContent,
                action: model.appIconPickerContinueAction
            )
            .onboardingDaxDialogStyle()
        }

        private var addressBarPositionView: some View {
            AddressBarPositionContent(
                action: model.selectAddressBarPositionAction
            )
        }

        private var searchExperienceSelectionView: some View {
            SearchExperienceContent(
                action: model.selectSearchExperienceAction
            )
        }

        private func animateBrowserComparisonViewState(isResumingOnboarding: Bool) {
            model.startOnboardingAction(isResumingOnboarding: isResumingOnboarding)
            model.browserComparisonState.showComparisonButton = true
            model.browserComparisonState.animateComparisonText = true
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
