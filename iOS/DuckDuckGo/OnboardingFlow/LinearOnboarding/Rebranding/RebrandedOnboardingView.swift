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
import MetricBuilder

private enum OnboardingViewMetrics {
    static let landingScreenDuration = 2.0
}

private enum OnboardingViewCopy {
    static let introTitle = "Hi There!"
    static let introMessage = "Ready for a faster browser that keeps you protected?"
    static let browsersComparisonTitle = "Protections activated!"
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
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @ObservedObject private var model: OnboardingIntroViewModel

        @State private var isPlayingSetAsDefaultVideo: Bool = false

        init(model: OnboardingIntroViewModel) {
            self.model = model
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
                    switch state.type {
                    case .startOnboardingDialog(let shouldShowSkipOnboardingButton):
                        introView(shouldShowSkipOnboardingButton: shouldShowSkipOnboardingButton)
                            .frame(width: geometry.size.width, alignment: .center)
                    case .browsersComparisonDialog:
                        browsersComparisonView(step: state.step)
                            .frame(width: geometry.size.width, alignment: .center)
                            .padding(.top, OnboardingTheme.rebranding2026.linearOnboardingMetrics.minTopMargin + BrowsersComparisonContentMetrics.additionalTopMargin)
                    default:
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
                        .onboardingProgressIndicator(
                            currentStep: state.step.currentStep,
                            totalSteps: 0
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
                        animateTitle: $model.skipOnboardingState.animateTitle,
                        animateMessage: $model.skipOnboardingState.animateMessage,
                        showCTA: $model.skipOnboardingState.showContent,
                        isSkipped: $model.isSkipped,
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
            .onboardingDaxDialogStyle()
            .visibility(model.introState.showIntroViewContent ? .visible : .invisible)
        }

        private func browsersComparisonView(step: ViewState.Intro.StepInfo) -> some View {
            BrowsersComparisonContent(
                title: OnboardingViewCopy.browsersComparisonTitle,
                currentStep: step.currentStep,
                totalSteps: step.totalSteps,
                setAsDefaultBrowserAction: model.setDefaultBrowserAction,
                cancelAction: model.cancelSetDefaultBrowserAction
            )
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

private struct OnboardingProgressIndicatorModifier: ViewModifier {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let currentStep: Int
    let totalSteps: Int

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                RebrandedOnboardingView.OnboardingProgressIndicator(
                    stepInfo: .init(currentStep: currentStep, totalSteps: totalSteps)
                )
                .padding(.trailing, onboardingTheme.linearOnboardingMetrics.progressBarTrailingPadding)
                .padding(.top, onboardingTheme.linearOnboardingMetrics.progressBarTopPadding)
                .transition(.identity)
                .visibility(totalSteps == 0 ? .invisible : .visible)
            }
    }
}

private extension View {

    func onboardingProgressIndicator(currentStep: Int, totalSteps: Int) -> some View {
        modifier(OnboardingProgressIndicatorModifier(currentStep: currentStep, totalSteps: totalSteps))
    }

}
