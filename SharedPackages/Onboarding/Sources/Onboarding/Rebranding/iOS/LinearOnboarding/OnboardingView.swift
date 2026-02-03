//
//  OnboardingView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import SwiftUI
import UIKit
import SystemSettingsPiPTutorial
import MetricBuilder

// MARK: - OnboardingView

extension OnboardingRebranding {
    public struct OnboardingView: View {

        static let daxGeometryEffectID = "DaxIcon"

        @Namespace var animationNamespace
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.onboardingTheme) private var onboardingTheme
        @ObservedObject private var model: OnboardingIntroViewModel

        public init(model: OnboardingIntroViewModel) {
            self.model = model
        }

        public var body: some View {
            ZStack(alignment: .topTrailing) {
                OnboardingBackground()

                switch model.state {
                case .landing:
                    landingView
                case let .onboarding(viewState):
                    onboardingDialogView(state: viewState)
#if DEBUG || ALPHA
                        .safeAreaInset(edge: .bottom) {
                            SecondaryButton(title: OnboardingRebranding.UserText.Onboarding.Intro.Debug.skip) {
                                model.overrideOnboardingCompleted()
                            }
                        }
#endif
                }
            }
            .overlay(alignment: .topTrailing) {
                rebrandingBadge
            }
        }

        private func onboardingDialogView(state: ViewState.Intro) -> some View {
            GeometryReader { geometry in
                VStack(alignment: .center) {
                    DaxDialogView(
                        logoPosition: .top,
                        matchLogoAnimation: (Self.daxGeometryEffectID, animationNamespace),
                        showDialogBox: $model.introState.showDaxDialogBox,
                        onTapGesture: {
                            withAnimation {
                                model.tapped()
                            }
                        },
                        content: {
                            VStack {
                                switch state.type {
                                case .startOnboardingDialog(let shouldShowSkipOnboardingButton):
                                    introView(shouldShowSkipOnboardingButton: shouldShowSkipOnboardingButton)
                                case .browsersComparisonDialog:
                                    browsersComparisonView
                                case .addToDockPromoDialog:
                                    addToDockPromoView
                                case .chooseAppIconDialog:
                                    appIconPickerView
                                case .chooseAddressBarPositionDialog:
                                    addressBarPreferenceSelectionView
                                case .chooseSearchExperienceDialog:
                                    searchExperienceSelectionView
                                }
                            }
                        }
                    )
                    .onboardingProgressIndicator(currentStep: state.step.currentStep, totalSteps: state.step.totalSteps)
                }
                .frame(width: geometry.size.width, alignment: .center)
                .offset(y: geometry.size.height * Metrics.dialogVerticalOffsetPercentage.build(v: verticalSizeClass, h: horizontalSizeClass))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.daxDialogVisibilityDelay) {
                        model.introState.showDaxDialogBox = true
                        model.introState.animateIntroText = true
                    }
                }
            }
            .padding()
        }

        private var landingView: some View {
            return LandingView(animationNamespace: animationNamespace)
                .ignoresSafeArea(edges: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.daxDialogDelay) {
                        withAnimation {
                            model.onAppear()
                        }
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
                title: model.copy.introTitle,
                skipOnboardingView: skipOnboardingView,
                animateText: $model.introState.animateIntroText,
                showCTA: $model.introState.showIntroButton,
                isSkipped: $model.isSkipped,
                continueAction: {
                    animateBrowserComparisonViewState(isResumingOnboarding: false)
                },
                skipAction: model.skipOnboardingAction
            )
            .onboardingDaxDialogStyle()
            .visibility(model.introState.showIntroViewContent ? .visible : .invisible)
        }

        private var browsersComparisonView: some View {
            BrowsersComparisonContent(
                title: model.copy.browserComparisonTitle,
                animateText: $model.browserComparisonState.animateComparisonText,
                showContent: $model.browserComparisonState.showComparisonButton,
                isSkipped: $model.isSkipped,
                setAsDefaultBrowserAction: model.setDefaultBrowserAction,
                cancelAction: model.cancelSetDefaultBrowserAction
            )
            .onboardingDaxDialogStyle()
        }

        private var addToDockPromoView: some View {
            AddToDockPromoContent(
                appIconManager: model.appIconManager,
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
                appIconManager: model.appIconManager,
                action: model.appIconPickerContinueAction
            )
            .onboardingDaxDialogStyle()
        }

        private var addressBarPreferenceSelectionView: some View {
            AddressBarPositionContent(
                animateTitle: $model.addressBarPositionContentState.animateTitle,
                showContent: $model.addressBarPositionContentState.showContent,
                isSkipped: $model.isSkipped,
                addressBarPositionManager: model.addressBarPositionManager,
                action: model.selectAddressBarPositionAction
            )
            .onboardingDaxDialogStyle()
        }

        private var searchExperienceSelectionView: some View {
            SearchExperienceContent(
                animateTitle: $model.searchExperienceContentState.animateTitle,
                isSkipped: $model.isSkipped,
                searchExperienceProvider: model.searchExperienceProvider,
                action: model.selectSearchExperienceAction
            )
            .onboardingDaxDialogStyle()
        }

        private var rebrandingBadge: some View {
            Text("REBRANDED")
                .font(onboardingTheme.typography.progressIndicator)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(onboardingTheme.colorPalette.primaryButtonBackgroundColor)
                .foregroundColor(onboardingTheme.colorPalette.primaryButtonTextColor)
                .clipShape(Capsule())
                .padding(.top, 8)
                .padding(.trailing, 8)
                .accessibilityIdentifier("OnboardingRebrandingBadge")
        }

        private func animateBrowserComparisonViewState(isResumingOnboarding: Bool) {
            // Hide content of Intro dialog before animating
            model.introState.showIntroViewContent = false

            // Animation with small delay for a better effect when intro content disappear
            let animationDuration = Metrics.comparisonChartAnimationDuration
            let animation = Animation
                .linear(duration: animationDuration)
                .delay(0.2)

            if #available(iOS 17, *) {
                withAnimation(animation) {
                    model.startOnboardingAction(isResumingOnboarding: isResumingOnboarding)
                } completion: {
                    model.browserComparisonState.animateComparisonText = true
                }
            } else {
                withAnimation(animation) {
                    model.startOnboardingAction(isResumingOnboarding: isResumingOnboarding)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                    model.browserComparisonState.animateComparisonText = true
                }
            }
        }

    }
}

// MARK: - View State

extension OnboardingRebranding.OnboardingView {

    enum ViewState: Equatable {
        case landing
        case onboarding(Intro)

        var intro: Intro? {
            switch self {
            case .landing:
                return nil
            case let .onboarding(intro):
                return intro
            }
        }
    }
    
}

extension OnboardingRebranding.OnboardingView.ViewState {
    
    struct Intro: Equatable {
        let type: IntroType
        let step: StepInfo
    }

}

extension OnboardingRebranding.OnboardingView.ViewState.Intro {

    enum IntroType: Equatable {
        case startOnboardingDialog(canSkipTutorial: Bool)
        case browsersComparisonDialog
        case addToDockPromoDialog
        case chooseAppIconDialog
        case chooseAddressBarPositionDialog
        case chooseSearchExperienceDialog
    }

    struct StepInfo: Equatable {
        let currentStep: Int
        let totalSteps: Int

        static let hidden = StepInfo(currentStep: 0, totalSteps: 0)
    }

}

// MARK: - Metrics

private enum Metrics {
    static let daxDialogDelay: TimeInterval = 2.0
    static let daxDialogVisibilityDelay: TimeInterval = 0.5
    static let comparisonChartAnimationDuration = 0.25
    static let dialogVerticalOffsetPercentage = MetricBuilder<CGFloat>(default: 0.1).iPhoneSmallScreen(0.01)
    static let progressBarTrailingPadding: CGFloat = 16.0
    static let progressBarTopPadding: CGFloat = 12.0
}

// MARK: - Helpers

private extension View {

    func onboardingProgressIndicator(currentStep: Int, totalSteps: Int) -> some View {
        overlay(alignment: .topTrailing) {
            OnboardingRebranding.OnboardingProgressIndicator(stepInfo: .init(currentStep: currentStep, totalSteps: totalSteps))
                .padding(.trailing, Metrics.progressBarTrailingPadding)
                .padding(.top, Metrics.progressBarTopPadding)
                .transition(.identity)
                .visibility(totalSteps == 0 ? .invisible : .visible)
        }
    }

}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    final class MockDaxDialogDisabling: OnboardingRebranding.ContextualDaxDialogDisabling {
        func disableContextualDaxDialogs() {}
    }

    final class MockPixelReporter: OnboardingRebranding.LinearOnboardingPixelReporting {
        func measureOnboardingIntroImpression() {}
        func measureSkipOnboardingCTAAction() {}
        func measureConfirmSkipOnboardingCTAAction() {}
        func measureResumeOnboardingCTAAction() {}
        func measureBrowserComparisonImpression() {}
        func measureChooseBrowserCTAAction() {}
        func measureChooseAppIconImpression() {}
        func measureChooseCustomAppIconColor() {}
        func measureAddressBarPositionSelectionImpression() {}
        func measureChooseBottomAddressBarPosition() {}
        func measureSearchExperienceSelectionImpression() {}
        func measureChooseAIChat() {}
        func measureChooseSearchOnly() {}
        func measureAddToDockPromoImpression() {}
        func measureAddToDockPromoShowTutorialCTAAction() {}
        func measureAddToDockPromoDismissCTAAction() {}
        func measureAddToDockTutorialDismissCTAAction() {}
    }

    final class MockAppIconManager: OnboardingRebranding.AppIconManaging {
        var appIcon: OnboardingRebranding.AppIcon = .defaultAppIcon

        func changeAppIcon(_ appIcon: OnboardingRebranding.AppIcon, completionHandler: ((Error?) -> Void)?) {
            self.appIcon = appIcon
            completionHandler?(nil)
        }
    }

    final class MockAddressBarPositionManager: OnboardingRebranding.AddressBarPositionManaging {
        var currentAddressBarPosition: OnboardingRebranding.AddressBarPosition = .top
    }

    static var previews: some View {
        let dependencies = OnboardingRebranding.OnboardingIntroViewModel.Dependencies(
            pixelReporter: MockPixelReporter(),
            systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManager(
                playerView: UIView(),
                videoPlayer: OnboardingRebranding.VideoPlayerCoordinator(configuration: OnboardingRebranding.VideoPlayerConfiguration()),
                eventMapper: SystemSettingsPiPTutorialPixelHandler()
            ),
            daxDialogsManager: MockDaxDialogDisabling(),
            introSteps: [
                .introDialog(isReturningUser: false),
                .browserComparison,
                .addToDockPromo,
                .appIconSelection,
                .addressBarPositionSelection,
                .searchExperienceSelection
            ],
            currentOnboardingStep: .introDialog(isReturningUser: false),
            searchExperienceProvider: OnboardingRebranding.OnboardingSearchExperience(),
            appIconManager: MockAppIconManager(),
            addressBarPositionManager: MockAddressBarPositionManager()
        )

        return ForEach(ColorScheme.allCases, id: \.self) {
            OnboardingRebranding.OnboardingView(model: .init(dependencies: dependencies))
                .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
                .preferredColorScheme($0)
        }
    }
}
#endif
