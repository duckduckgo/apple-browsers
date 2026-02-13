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
}

extension OnboardingRebranding.OnboardingView {

    struct LinearDialogContentContainer<Title: View, Actions: View>: View {

        struct Metrics {
            let outerSpacing: CGFloat
            let textSpacing: CGFloat
            let contentSpacing: CGFloat
            let actionsSpacing: CGFloat
        }

        private let metrics: Metrics
        private let message: AnyView?
        private let content: AnyView?
        private let title: Title
        private let actions: Actions

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

                    actions.padding(.top, metrics.actionsSpacing)
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

        @Namespace var animationNamespace
        @ObservedObject private var model: OnboardingIntroViewModel

        init(model: OnboardingIntroViewModel) {
            self.model = model
        }

        private enum BubbleTailDirection {
            case leading
            case trailing
        }

        private struct BubbleBackedDialogConfiguration {
            let tailOffset: CGFloat
            let tailDirection: BubbleTailDirection
            let additionalTopMargin: CGFloat
            let isVisible: Bool
            let showsStepCounter: Bool
        }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                OnboardingTheme.rebranding2026.colorPalette.background
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
                    .padding(.leading, OnboardingTheme.rebranding2026.linearOnboardingMetrics.rebrandingBadgeLeadingPadding)
                    .padding(.top, OnboardingTheme.rebranding2026.linearOnboardingMetrics.rebrandingBadgeTopPadding)
            }
            .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
        }

        private func onboardingDialogView(state: ViewState.Intro) -> some View {
            GeometryReader { geometry in
                VStack(alignment: .center) {
                    if let bubbleConfiguration = bubbleBackedDialogConfiguration(for: state.type) {
                        bubbleBackedDialogView(state: state, configuration: bubbleConfiguration)
                            .frame(width: geometry.size.width, alignment: .center)
                            .padding(.top, OnboardingTheme.rebranding2026.linearOnboardingMetrics.minTopMargin + bubbleConfiguration.additionalTopMargin)
                    } else {
                        DaxDialogView(
                            logoPosition: .top,
                            matchLogoAnimation: (Self.daxGeometryEffectID, animationNamespace),
                            showDialogBox: $model.introState.showDaxDialogBox,
                            onTapGesture: {
                                model.tapped()
                            },
                            content: {
                                switch state.type {
                                case .browsersComparisonDialog:
                                    EmptyView()
                                case .addToDockPromoDialog:
                                    addToDockPromoView
                                case .chooseAppIconDialog:
                                    appIconPickerView
                                case .chooseAddressBarPositionDialog:
                                    addressBarPreferenceSelectionView
                                case .chooseSearchExperienceDialog:
                                    searchExperienceSelectionView
                                default:
                                    EmptyView()
                                }
                            }
                        )
                        .frame(width: geometry.size.width, alignment: .center)
                        .padding(.top, OnboardingTheme.rebranding2026.linearOnboardingMetrics.minTopMargin)
                        .onAppear {
                            model.introState.showDaxDialogBox = true
                        }
                    }
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
            .frame(maxWidth: OnboardingTheme.rebranding2026.linearOnboardingMetrics.bubbleMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .visibility(configuration.isVisible ? .visible : .invisible)
        }

        private func makeBubbleView<Content: View>(
            configuration: BubbleBackedDialogConfiguration,
            stepInfo: ViewState.Intro.StepInfo?,
            @ViewBuilder content: @escaping () -> Content
        ) -> AnyView {
            let tailPosition: OnboardingBubbleView<Content>.TailPosition
            switch configuration.tailDirection {
            case .leading:
                tailPosition = .bottom(offset: configuration.tailOffset, direction: .leading)
            case .trailing:
                tailPosition = .bottom(offset: configuration.tailOffset, direction: .trailing)
            }

            if let stepInfo {
                return AnyView(OnboardingBubbleView.withStepProgressIndicator(
                    tailPosition: tailPosition,
                    currentStep: stepInfo.currentStep,
                    totalSteps: stepInfo.totalSteps
                ) {
                    content()
                })
            }

            return AnyView(OnboardingBubbleView(
                tailPosition: tailPosition,
                contentInsets: OnboardingTheme.rebranding2026.linearBubbleMetrics.contentInsets,
                arrowLength: OnboardingTheme.rebranding2026.linearBubbleMetrics.arrowLength,
                arrowWidth: OnboardingTheme.rebranding2026.linearBubbleMetrics.arrowWidth
            ) {
                content()
            })
        }

        @ViewBuilder
        private func bubbleBackedDialogContent(for type: ViewState.Intro.IntroType) -> some View {
            switch type {
            case .startOnboardingDialog(let shouldShowSkipOnboardingButton):
                introView(shouldShowSkipOnboardingButton: shouldShowSkipOnboardingButton)
            case .browsersComparisonDialog:
                browsersComparisonView
            default:
                EmptyView()
            }
        }

        private func bubbleBackedDialogConfiguration(for type: ViewState.Intro.IntroType) -> BubbleBackedDialogConfiguration? {
            switch type {
            case .startOnboardingDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: OnboardingTheme.rebranding2026.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.introAdditionalTopMargin,
                    isVisible: model.introState.showIntroViewContent,
                    showsStepCounter: false
                )
            case .browsersComparisonDialog:
                BubbleBackedDialogConfiguration(
                    tailOffset: OnboardingTheme.rebranding2026.linearOnboardingMetrics.bubbleTailOffset,
                    tailDirection: .leading,
                    additionalTopMargin: BubbleBackedDialogMetrics.browsersComparisonAdditionalTopMargin,
                    isVisible: true,
                    showsStepCounter: true
                )
            default:
                nil
            }
        }

        private var addToDockPromoView: some View {
            AddToDockPromoContent(
                isAnimating: $model.addToDockState.isAnimating,
                isSkipped: $model.isSkipped,
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
                animateTitle: $model.appIconPickerContentState.animateTitle,
                animateMessage: $model.appIconPickerContentState.animateMessage,
                showContent: $model.appIconPickerContentState.showContent,
                isSkipped: $model.isSkipped,
                action: model.appIconPickerContinueAction
            )
            .onboardingDaxDialogStyle()
        }

        private var addressBarPreferenceSelectionView: some View {
            AddressBarPositionContent(
                animateTitle: $model.addressBarPositionContentState.animateTitle,
                showContent: $model.addressBarPositionContentState.showContent,
                isSkipped: $model.isSkipped,
                action: model.selectAddressBarPositionAction
            )
            .onboardingDaxDialogStyle()
        }

        private var searchExperienceSelectionView: some View {
            SearchExperienceContent(
                animateTitle: $model.searchExperienceContentState.animateTitle,
                isSkipped: $model.isSkipped,
                action: model.selectSearchExperienceAction
            )
            .onboardingDaxDialogStyle()
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
