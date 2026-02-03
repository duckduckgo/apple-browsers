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
import SystemSettingsPiPTutorial
import MetricBuilder
import Lottie
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

typealias LegacyOnboardingViewState = OnboardingView.ViewState

enum OnboardingRebranding {}

typealias RebrandedOnboardingView = OnboardingRebranding.OnboardingView

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
                OnboardingBackground()

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
            .applyOnboardingTheme(.rebranding2026, stepProgressTheme: .rebranding2026)
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
                .offset(y: geometry.size.height * OnboardingViewMetrics.dialogVerticalOffsetPercentage.build(v: verticalSizeClass, h: horizontalSizeClass))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingViewMetrics.daxDialogVisibilityDelay) {
                        model.introState.showDaxDialogBox = true
                        model.introState.animateIntroText = true
                    }
                }
            }
            .padding()
        }

        private var landingView: some View {
            LandingView(animationNamespace: animationNamespace)
                .ignoresSafeArea(edges: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + OnboardingViewMetrics.daxDialogDelay) {
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
            // Hide content of Intro dialog before animating
            model.introState.showIntroViewContent = false

            // Animation with small delay for a better effect when intro content disappear
            let animationDuration = OnboardingViewMetrics.comparisonChartAnimationDuration
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

private enum OnboardingViewMetrics {
    static let daxDialogDelay: TimeInterval = 2.0
    static let daxDialogVisibilityDelay: TimeInterval = 0.5
    static let comparisonChartAnimationDuration = 0.25
    static let dialogVerticalOffsetPercentage = MetricBuilder<CGFloat>(default: 0.1).iPhoneSmallScreen(0.01)
    static let progressBarTrailingPadding: CGFloat = 16.0
    static let progressBarTopPadding: CGFloat = 12.0
}

private extension View {

    func onboardingProgressIndicator(currentStep: Int, totalSteps: Int) -> some View {
        overlay(alignment: .topTrailing) {
            RebrandedOnboardingView.OnboardingProgressIndicator(
                stepInfo: .init(currentStep: currentStep, totalSteps: totalSteps)
            )
            .padding(.trailing, OnboardingViewMetrics.progressBarTrailingPadding)
            .padding(.top, OnboardingViewMetrics.progressBarTopPadding)
            .transition(.identity)
            .visibility(totalSteps == 0 ? .invisible : .visible)
        }
    }

}

// MARK: - Landing

extension OnboardingRebranding.OnboardingView {

    struct LandingView: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        let animationNamespace: Namespace.ID

        var body: some View {
            GeometryReader { proxy in
                if isIPadLandscape(v: verticalSizeClass, h: horizontalSizeClass) {
                    landingScreenIPadLandscape(proxy: proxy)
                } else {
                    landingScreenPortrait(proxy: proxy)
                }
            }
        }

        func landingScreenPortrait(proxy: GeometryProxy) -> some View {
            VStack {
                Spacer()

                welcomeView

                Spacer()

                Image(LandingViewMetrics.hikerImage.build(v: verticalSizeClass, h: horizontalSizeClass))
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }

        func landingScreenIPadLandscape(proxy: GeometryProxy) -> some View {
            HStack(spacing: 0) {
                // Divide screen in half with two containers:
                // 1. Hiker to be centered horizontally in the container and with a height of 90% of the screen size
                // 2. Welcome view horizontally centered in the container with min padding leading and trailing to wrap the text if needed.
                VStack(alignment: .center) {
                    Image(LandingViewMetrics.hikerImage.build(v: verticalSizeClass, h: horizontalSizeClass))
                        .resizable()
                        .scaledToFit()
                        .frame(height: proxy.size.height * LandingViewMetrics.Landscape.hikerHeightPercentage)
                }
                .frame(width: proxy.size.width / 2, height: proxy.size.height, alignment: .bottom)

                HStack {
                    Spacer(minLength: proxy.size.width / 2 * LandingViewMetrics.Landscape.textMinSpacerPercentage)

                    welcomeView
                        .padding(.top, proxy.size.height * LandingViewMetrics.Landscape.daxImagePositionPercentage)

                    Spacer(minLength: proxy.size.width / 2 * LandingViewMetrics.Landscape.textMinSpacerPercentage)
                }
                .frame(width: proxy.size.width / 2, height: proxy.size.height, alignment: .top)
            }
        }

        private var welcomeView: some View {
            let iconSize = LandingViewMetrics.iconSize.build(v: verticalSizeClass, h: horizontalSizeClass)

            return VStack(alignment: .center, spacing: LandingViewMetrics.welcomeMessageStackSpacing.build(v: verticalSizeClass, h: horizontalSizeClass)) {
                Image(.daxIconExperiment)
                    .resizable()
                    .matchedGeometryEffect(id: OnboardingView.daxGeometryEffectID, in: animationNamespace)
                    .frame(width: iconSize.width, height: iconSize.height)

                Text(UserText.onboardingWelcomeHeader)
                    .onboardingTitleStyle(fontSize: LandingViewMetrics.titleSize.build(v: verticalSizeClass, h: horizontalSizeClass))
                    .frame(width: LandingViewMetrics.titleWidth.build(v: verticalSizeClass, h: horizontalSizeClass), alignment: .top)
            }
        }

    }

}

private enum LandingViewMetrics {
    static let iconSize = MetricBuilder<CGSize>(default: .init(width: 70, height: 70)).iPad(landscape: .init(width: 96, height: 96))
    static let welcomeMessageStackSpacing = MetricBuilder<CGFloat>(iPhone: 13, iPad: 32)
    static let titleSize = MetricBuilder<CGFloat>(iPhone: 28, iPad: 36).iPad(landscape: 48)
    static let titleWidth = MetricBuilder<CGFloat?>(iPhone: 252, iPad: nil)
    static let hikerImage = MetricBuilder<ImageResource>(default: .hiker).iPhoneSmallScreen(.hikerSmall)
    enum Landscape {
        static let textMinSpacerPercentage: CGFloat = 0.15
        static let daxImagePositionPercentage: CGFloat = 0.15
        static let hikerHeightPercentage: CGFloat = 0.9
    }
}

// MARK: - Intro Dialog

extension OnboardingRebranding.OnboardingView {

    struct IntroDialogContent: View {

        private let title: String
        private let skipOnboardingView: AnyView?
        private var animateText: Binding<Bool>
        private var showCTA: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let continueAction: () -> Void
        private let skipAction: () -> Void

        @State private var showSkipOnboarding = false

        init(
            title: String,
            skipOnboardingView: AnyView?,
            animateText: Binding<Bool> = .constant(true),
            showCTA: Binding<Bool> = .constant(false),
            isSkipped: Binding<Bool>,
            continueAction: @escaping () -> Void,
            skipAction: @escaping () -> Void
        ) {
            self.title = title
            self.skipOnboardingView = skipOnboardingView
            self.animateText = animateText
            self.showCTA = showCTA
            self.isSkipped = isSkipped
            self.continueAction = continueAction
            self.skipAction = skipAction
        }

        var body: some View {
            if showSkipOnboarding {
                skipOnboardingView
            } else {
                introContent
            }
        }

        private var introContent: some View {
            VStack(spacing: 24.0) {
                AnimatableTypingText(title, startAnimating: animateText, skipAnimation: isSkipped) {
                    withAnimation {
                        showCTA.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 20, weight: .bold))

                VStack {
                    Button(action: continueAction) {
                        Text(UserText.Onboarding.Intro.continueCTA)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if skipOnboardingView != nil {
                        OnboardingBorderedButton(maxHeight: 50.0, content: {
                            Text(UserText.Onboarding.Intro.skipCTA)
                        }, action: {
                            isSkipped.wrappedValue = false
                            showSkipOnboarding = true
                            skipAction()
                        })
                    }
                }
                .visibility(showCTA.wrappedValue ? .visible : .invisible)
            }
        }

    }
}

// MARK: - Skip Onboarding

extension OnboardingRebranding.OnboardingView {

    struct SkipOnboardingContent: View {
        private static let fireButtonCopy = "Fire Button"

        typealias Copy = UserText.Onboarding.Skip

        private var animateTitle: Binding<Bool>
        private var animateMessage: Binding<Bool>
        private var showCTA: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let startBrowsingAction: () -> Void
        private let resumeOnboardingAction: () -> Void

        init(
            animateTitle: Binding<Bool>,
            animateMessage: Binding<Bool>,
            showCTA: Binding<Bool>,
            isSkipped: Binding<Bool>,
            startBrowsingAction: @escaping () -> Void,
            resumeOnboardingAction: @escaping () -> Void
        ) {
            self.animateTitle = animateTitle
            self.animateMessage = animateMessage
            self.showCTA = showCTA
            self.isSkipped = isSkipped
            self.startBrowsingAction = startBrowsingAction
            self.resumeOnboardingAction = resumeOnboardingAction
        }

        var body: some View {
            VStack(spacing: 24.0) {
                AnimatableTypingText(Copy.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                    withAnimation {
                        animateMessage.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 20, weight: .bold))

                AnimatableTypingText(Copy.message.attributed.withFont(.daxBodyBold(), forText: Self.fireButtonCopy), startAnimating: animateMessage, skipAnimation: isSkipped) {
                    withAnimation {
                        showCTA.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 16))

                VStack {
                    Button(action: startBrowsingAction) {
                        Text(Copy.confirmSkipOnboardingCTA)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    OnboardingBorderedButton(
                        maxHeight: 50.0,
                        content: {
                            Text(Copy.resumeOnboardingCTA)
                        },
                        action: resumeOnboardingAction
                    )
                }
                .visibility(showCTA.wrappedValue ? .visible : .invisible)
            }
        }

    }
}

// MARK: - Browsers Comparison

extension OnboardingRebranding.OnboardingView {

    struct BrowsersComparisonContent: View {

        private let title: String
        private var animateText: Binding<Bool>
        private var showContent: Binding<Bool>
        private let setAsDefaultBrowserAction: () -> Void
        private let cancelAction: () -> Void
        private var isSkipped: Binding<Bool>

        init(
            title: String,
            animateText: Binding<Bool> = .constant(true),
            showContent: Binding<Bool> = .constant(false),
            isSkipped: Binding<Bool>,
            setAsDefaultBrowserAction: @escaping () -> Void,
            cancelAction: @escaping () -> Void
        ) {
            self.title = title
            self.animateText = animateText
            self.showContent = showContent
            self.isSkipped = isSkipped
            self.setAsDefaultBrowserAction = setAsDefaultBrowserAction
            self.cancelAction = cancelAction
        }

        var body: some View {
            VStack(spacing: 16.0) {
                AnimatableTypingText(title, startAnimating: animateText, skipAnimation: isSkipped) {
                    withAnimation {
                        showContent.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 20, weight: .bold))


                VStack(spacing: 24) {
                    BrowsersComparisonChart(privacyFeatures: BrowsersComparisonModel.privacyFeatures)

                    RebrandedOnboardingView.OnboardingActions(
                        viewModel: .init(
                            primaryButtonTitle: UserText.Onboarding.BrowsersComparison.cta,
                            secondaryButtonTitle: UserText.onboardingSkip
                        ),
                        primaryAction: setAsDefaultBrowserAction,
                        secondaryAction: cancelAction
                    )

                }
                .visibility(showContent.wrappedValue ? .visible : .invisible)
            }
        }

    }

}

// MARK: - Add To Dock

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoContent: View {

        @State private var showAddToDockTutorial = false

        private let isAnimating: Binding<Bool>
        private let isSkipped: Binding<Bool>
        private let showTutorialAction: () -> Void
        private let dismissAction: (_ fromAddToDock: Bool) -> Void

        init(
            isAnimating: Binding<Bool> = .constant(true),
            isSkipped: Binding<Bool>,
            showTutorialAction: @escaping () -> Void,
            dismissAction: @escaping (_ fromAddToDock: Bool) -> Void
        ) {
            self.isAnimating = isAnimating
            self.isSkipped = isSkipped
            self.showTutorialAction = showTutorialAction
            self.dismissAction = dismissAction
        }

        var body: some View {
            if showAddToDockTutorial {
                RebrandedOnboardingView.AddToDockTutorialContent(cta: UserText.AddToDockOnboarding.Buttons.gotIt, isSkipped: isSkipped) {
                    dismissAction(true)
                }
            } else {
                ContextualDaxDialogContent(
                    title: UserText.AddToDockOnboarding.Promo.title,
                    titleFont: Font(UIFont.daxTitle3()),
                    message: NSAttributedString(string: UserText.AddToDockOnboarding.Promo.introMessage),
                    messageFont: Font.system(size: 16),
                    customView: AnyView(addToDockPromoView),
                    customActionView: AnyView(customActionView),
                    skipAnimations: isSkipped
                )
            }
        }

        private var addToDockPromoView: some View {
            RebrandedOnboardingView.AddToDockPromoView()
                .aspectRatio(contentMode: .fit)
                .padding(.vertical)
        }

        private var customActionView: some View {
            VStack {
                RebrandedOnboardingView.OnboardingCTAButton(
                    title: UserText.AddToDockOnboarding.Buttons.tutorial,
                    buttonStyle: .primary(compact: false),
                    action: {
                        showTutorialAction()
                        isSkipped.wrappedValue = false
                        showAddToDockTutorial = true
                    }
                )

                RebrandedOnboardingView.OnboardingCTAButton(
                    title: UserText.AddToDockOnboarding.Buttons.skip,
                    buttonStyle: .ghost,
                    action: {
                        dismissAction(false)
                    }
                )
            }
        }

    }

    struct AddToDockTutorialContent: View {
        let title = UserText.AddToDockOnboarding.Tutorial.title
        let message = UserText.AddToDockOnboarding.Tutorial.message

        let cta: String
        let isSkipped: Binding<Bool>
        let dismissAction: () -> Void

        var body: some View {
            RebrandedOnboardingView.AddToDockTutorialView(
                title: title,
                message: message,
                cta: cta,
                isSkipped: isSkipped,
                action: dismissAction
            )
        }
    }

}

// MARK: - App Icon Picker

extension OnboardingRebranding.OnboardingView {

    struct AppIconPickerContent: View {

        private var animateTitle: Binding<Bool>
        private var animateMessage: Binding<Bool>
        private var showContent: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let action: () -> Void

        init(
            animateTitle: Binding<Bool> = .constant(true),
            animateMessage: Binding<Bool> = .constant(true),
            showContent: Binding<Bool> = .constant(false),
            isSkipped: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.animateTitle = animateTitle
            self.animateMessage = animateMessage
            self.showContent = showContent
            self.isSkipped = isSkipped
            self.action = action
        }

        var body: some View {
            VStack(spacing: 16.0) {
                AnimatableTypingText(UserText.Onboarding.AppIconSelection.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                    animateMessage.wrappedValue = true
                }
                .foregroundColor(.primary)
                .font(AppIconPickerContentMetrics.titleFont)

                AnimatableTypingText(UserText.Onboarding.AppIconSelection.message, startAnimating: animateMessage, skipAnimation: isSkipped) {
                    withAnimation {
                        showContent.wrappedValue = true
                    }
                }
                .foregroundColor(.primary)
                .font(AppIconPickerContentMetrics.messageFont)

                VStack(spacing: 24) {
                    RebrandedOnboardingView.AppIconPicker()

                    Button(action: action) {
                        Text(UserText.Onboarding.AppIconSelection.cta)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .visibility(showContent.wrappedValue ? .visible : .invisible)
            }
        }

    }

}

private enum AppIconPickerContentMetrics {
    static let titleFont = Font.system(size: 20, weight: .semibold)
    static let messageFont = Font.system(size: 16)
}

// MARK: - Address Bar Position

extension OnboardingRebranding.OnboardingView {

    struct AddressBarPositionContent: View {

        private var animateTitle: Binding<Bool>
        private var showContent: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let action: () -> Void

        init(
            animateTitle: Binding<Bool> = .constant(true),
            showContent: Binding<Bool> = .constant(true),
            isSkipped: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.animateTitle = animateTitle
            self.showContent = showContent
            self.isSkipped = isSkipped
            self.action = action
        }

        var body: some View {
            VStack(spacing: 16.0) {
                AnimatableTypingText(UserText.Onboarding.AddressBarPosition.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                    showContent.wrappedValue = true
                }
                .foregroundColor(.primary)
                .font(AddressBarPositionContentMetrics.titleFont)

                VStack(spacing: 24) {
                    RebrandedOnboardingView.OnboardingAddressBarPositionPicker()

                    Button(action: action) {
                        Text(verbatim: UserText.Onboarding.AddressBarPosition.cta)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .visibility(showContent.wrappedValue ? .visible : .invisible)
            }
        }
    }

}

private enum AddressBarPositionContentMetrics {
    static let titleFont = Font.system(size: 20, weight: .semibold)
}

// MARK: - Search Experience

extension OnboardingRebranding.OnboardingView {

    struct SearchExperienceContent: View {
        private var animateTitle: Binding<Bool>
        private var isSkipped: Binding<Bool>
        private let action: () -> Void

        @State private var showContent = false
        @StateObject private var viewModel = OnboardingSearchExperiencePickerViewModel()

        init(animateTitle: Binding<Bool> = .constant(true),
             isSkipped: Binding<Bool>,
             action: @escaping () -> Void) {
            self.animateTitle = animateTitle
            self.isSkipped = isSkipped
            self.action = action
        }

        var body: some View {
            VStack(spacing: 16.0) {
                AnimatableTypingText(UserText.Onboarding.SearchExperience.title, startAnimating: animateTitle, skipAnimation: isSkipped) {
                    showContent = true
                }
                .foregroundColor(.primary)
                .font(SearchExperienceContentMetrics.titleFont)

                VStack(spacing: 24.0) {
                    RebrandedOnboardingView.OnboardingSearchExperiencePicker(viewModel: viewModel)

                    Text(AttributedString(UserText.Onboarding.SearchExperience.footerAttributed()))
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: {
                        viewModel.confirmChoice()
                        action()
                    }) {
                        Text(UserText.Onboarding.SearchExperience.cta)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 8)
                .visibility(showContent ? .visible : .invisible)
            }
        }
    }

}

private enum SearchExperienceContentMetrics {
    static let titleFont = Font.system(size: 20, weight: .semibold)
    static let messageFont = Font.system(size: 16)
}

// MARK: - CTA Button

extension OnboardingRebranding.OnboardingView {

    struct OnboardingCTAButton: View {
        enum ButtonStyle {
            case primary(compact: Bool = false)
            case ghost
        }

        let title: String
        var buttonStyle: ButtonStyle = .primary(compact: true)
        let action: () -> Void


        var body: some View {
            let button = Button(action: action) {
                Text(title)
            }

            switch buttonStyle {
            case .primary(let isCompact):
                button.buttonStyle(PrimaryButtonStyle(compact: isCompact))
            case .ghost:
                button.buttonStyle(GhostButtonStyle())
            }
        }
    }

}

// MARK: - Actions

extension OnboardingRebranding.OnboardingView {

    struct OnboardingActions: View {

        @ObservedObject var viewModel: Model

        var primaryAction: (() -> Void)?
        var secondaryAction: (() -> Void)?

        final class Model: ObservableObject {
            @Published var primaryButtonTitle: String
            @Published var secondaryButtonTitle: String
            @Published var isContinueEnabled: Bool

            init(primaryButtonTitle: String = "", secondaryButtonTitle: String = "", isContinueEnabled: Bool = true) {
                self.primaryButtonTitle = primaryButtonTitle
                self.secondaryButtonTitle = secondaryButtonTitle
                self.isContinueEnabled = isContinueEnabled
            }
        }

        var body: some View {
            VStack(spacing: 8) {
                Button(action: {
                    self.primaryAction?()
                }, label: {
                    Text(viewModel.primaryButtonTitle)
                })
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.isContinueEnabled)
                .accessibilityIdentifier("Continue")

                Button(action: {
                    self.secondaryAction?()
                }, label: {
                    Text(viewModel.secondaryButtonTitle)
                })
                .buttonStyle(GhostButtonStyle())
                .accessibilityIdentifier("Skip")
            }
        }
    }

}

// MARK: - Add To Dock Components

extension OnboardingRebranding.OnboardingView {

    struct AddToDockPromoView: View {
        private static let appIconFillKeyPath = "**.Backdrop.Fill 1.Color"

        private var model = AddToDockPromoViewModel()

        @State private var isAnimating = false

        var body: some View {
            LottieView(
                lottieFile: "add-to-dock-promo",
                isAnimating: $isAnimating,
                animationImageProvider: model,
                valueProvider: .init(
                    provider: ColorValueProvider(model.color),
                    keypath: AnimationKeypath(keypath: Self.appIconFillKeyPath)
                )
            )
            .onFirstAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isAnimating = true
                }
            }
        }
    }

    struct AddToDockTutorialView: View {
        private static let videoSize = CGSize(width: 898.0, height: 680.0)
        private static let videoURL = Bundle.main.url(forResource: "add-to-dock-demo", withExtension: "mp4")!

        private let title: String
        private let message: String
        private let cta: String
        private let action: () -> Void
        private let isSkipped: Binding<Bool>

        @State private var animateTitle = true
        @State private var animateMessage = false
        @State private var showContent = false
        @State private var videoPlayerWidth: CGFloat = 0.0
        @StateObject private var videoPlayerModel = VideoPlayerCoordinator(configuration: VideoPlayerConfiguration())

        init(
            title: String,
            message: String,
            cta: String,
            isSkipped: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.message = message
            self.cta = cta
            self.isSkipped = isSkipped
            self.action = action
        }

        var body: some View {
            VStack(spacing: 24.0) {
                AnimatableTypingText(title, startAnimating: $animateTitle, skipAnimation: isSkipped) {
                    withAnimation {
                        animateMessage = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 20, weight: .bold))

                AnimatableTypingText(message, startAnimating: $animateMessage, skipAnimation: isSkipped) {
                    withAnimation {
                        showContent = true
                    }
                }
                .foregroundColor(.primary)
                .font(Font.system(size: 16))

                videoPlayer
                    .visibility(showContent ? .visible : .invisible)
                    .onChange(of: showContent) { newValue in
                        if newValue {
                            // Need to delay playing a video. If calling play too early the video won't play.
                            DispatchQueue.main.async {
                                videoPlayerModel.play()
                            }
                        }
                    }
                    .onFirstAppear {
                        videoPlayerModel.loadAsset(url: Self.videoURL, shouldLoopVideo: true)
                    }

                Button(action: action) {
                    Text(cta)
                }
                .buttonStyle(PrimaryButtonStyle())
                .visibility(showContent ? .visible : .invisible)
            }
            .onFrameUpdate(in: .global, using: VideoPlayerFramePreferenceKey.self) { rect in
                videoPlayerWidth = rect.width
            }
        }

        private var videoPlayer: some View {
            // Calculate the height of the video based on the width it takes maintaining its aspect ratio
            let heightRatio = videoPlayerWidth * (Self.videoSize.height / Self.videoSize.width)
            return PlayerView(coordinator: videoPlayerModel)
                .frame(width: videoPlayerWidth, height: heightRatio)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    videoPlayerModel.pause()

                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    videoPlayerModel.play()
                }
        }

        private struct VideoPlayerFramePreferenceKey: PreferenceKey {
            static var defaultValue: CGRect = .zero
            static func reduce(value: inout CGRect, nextValue: () -> CGRect) {}
        }

    }

}

// MARK: - App Icon Picker Components

extension OnboardingRebranding.OnboardingView {

    struct AppIconPicker: View {
        @StateObject private var viewModel = AppIconPickerViewModel()

        let layout = [GridItem(.adaptive(minimum: AppIconPickerMetrics.iconSize), spacing: AppIconPickerMetrics.spacing, alignment: .leading)]

        var body: some View {
            LazyVGrid(columns: layout, spacing: AppIconPickerMetrics.spacing) {
                ForEach(viewModel.items, id: \.icon) { item in
                    Image(uiImage: item.icon.mediumImage ?? UIImage())
                        .resizable()
                        .frame(width: AppIconPickerMetrics.iconSize, height: AppIconPickerMetrics.iconSize)
                        .cornerRadius(AppIconPickerMetrics.cornerRadius)
                        .overlay {
                            strokeOverlay(isSelected: item.isSelected)
                        }
                        .onTapGesture {
                            viewModel.changeApp(icon: item.icon)
                        }
                }
            }
        }

        @ViewBuilder
        private func strokeOverlay(isSelected: Bool) -> some View {
            if isSelected {
                RoundedRectangle(cornerRadius: AppIconPickerMetrics.cornerRadius)
                    .foregroundColor(.clear)
                    .frame(width: AppIconPickerMetrics.strokeFrameSize, height: AppIconPickerMetrics.strokeFrameSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppIconPickerMetrics.cornerRadius)
                            .inset(by: -AppIconPickerMetrics.strokeInset)
                            .stroke(.blue, lineWidth: AppIconPickerMetrics.strokeWidth)
                    )
            }
        }
    }

}

private enum AppIconPickerMetrics {
    static let cornerRadius: CGFloat = 13.0
    static let iconSize: CGFloat = 56.0
    static let spacing: CGFloat = 16.0
    static let strokeFrameSize: CGFloat = 60
    static let strokeWidth: CGFloat = 3
    static let strokeInset: CGFloat = 1.5
}

// MARK: - Address Bar Position Components

extension OnboardingRebranding.OnboardingView {

    struct OnboardingAddressBarPositionPicker: View {
        @StateObject private var viewModel = OnboardingAddressBarPositionPickerViewModel()

        var body: some View {
            VStack(spacing: AddressBarPositionPickerMetrics.Button.itemSpacing) {
                ForEach(viewModel.items, id: \.type) { item in
                    AddressBarPositionButton(
                        icon: item.icon,
                        title: AttributedString(item.title),
                        message: item.message,
                        isSelected: item.isSelected,
                        action: {
                            viewModel.setAddressBar(position: item.type)
                        }
                    )
                }
            }
        }
    }

}

private enum AddressBarPositionPickerMetrics {
    enum Button {
        static let messageFont = Font.system(size: 15)
        static let overlayRadius: CGFloat = 13.0
        static let overlayStroke: CGFloat = 1
        static let itemSpacing: CGFloat = 16.0
        static let borderLightColor = Color.black.opacity(0.18)
        static let borderDarkColor = Color.white.opacity(0.18)
    }
    enum Checkbox {
        static let size: CGFloat = 24.0
        static let checkSize: CGFloat = 16.0
        static let strokeInset = 0.75
        static let strokeWidth = 1.5
    }
}

extension OnboardingRebranding.OnboardingView.OnboardingAddressBarPositionPicker {

    struct AddressBarPositionButton: View {
        @Environment(\.colorScheme) private var colorScheme

        let icon: ImageResource
        let title: AttributedString
        let message: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: AddressBarPositionPickerMetrics.Button.itemSpacing) {
                    Image(icon)

                    VStack(alignment: .leading) {
                        Text(title)
                        Text(message)
                            .font(AddressBarPositionPickerMetrics.Button.messageFont)
                            .foregroundStyle(Color.secondary)
                    }

                    Spacer()

                    Checkbox(isSelected: isSelected)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: AddressBarPositionPickerMetrics.Button.overlayRadius)
                    .stroke(strokeColor, lineWidth: AddressBarPositionPickerMetrics.Button.overlayStroke)
            }
            .buttonStyle(AddressBarPostionButtonStyle(isSelected: isSelected))
        }

        private var strokeColor: Color {
            if isSelected {
                Color(designSystemColor: .accent)
            } else {
                colorScheme == .light ? AddressBarPositionPickerMetrics.Button.borderLightColor : AddressBarPositionPickerMetrics.Button.borderDarkColor
            }
        }

    }

    struct Checkbox: View {
        @Environment(\.colorScheme) private var colorScheme

        let isSelected: Bool

        var body: some View {
            Circle()
                .frame(width: AddressBarPositionPickerMetrics.Checkbox.size, height: AddressBarPositionPickerMetrics.Checkbox.size)
                .foregroundColor(foregroundColor)
                .overlay {
                    selectionOverlay
                }
        }

        @ViewBuilder
        private var selectionOverlay: some View {
            if isSelected {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSolid)
                    .renderingMode(.template)
                    .resizable()
                    .background(
                        Circle()
                            .fill(Color.white)
                            // Use smaller frame for checkbox bg to not fill the transparent edge of the glyph
                            .frame(width: AddressBarPositionPickerMetrics.Checkbox.checkSize, height: AddressBarPositionPickerMetrics.Checkbox.checkSize)
                    )
                    .foregroundStyle(Color(designSystemColor: .accent))
                    .frame(width: AddressBarPositionPickerMetrics.Checkbox.size, height: AddressBarPositionPickerMetrics.Checkbox.size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .inset(by: AddressBarPositionPickerMetrics.Checkbox.strokeInset)
                    .stroke(.secondary, lineWidth: AddressBarPositionPickerMetrics.Checkbox.strokeWidth)
            }
        }

        private var foregroundColor: Color {
            switch (colorScheme, isSelected) {
            case (.light, true), (.dark, true):
                Color(designSystemColor: .accent)
            case (.light, false):
                .black.opacity(0.03)
            case (.dark, false):
                .white.opacity(0.06)
            default:
                .clear
            }
        }
    }

}

private struct AddressBarPostionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    private let minHeight = 63.0

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: minHeight)
            .background(backgroundColor(configuration.isPressed || isSelected))
            .cornerRadius(12)
            .contentShape(Rectangle()) // Makes whole button area tappable, when there's no background
    }

    private func backgroundColor(_ isHighlighted: Bool) -> Color {
        isHighlighted ? Color(designSystemColor: .buttonsGhostPressedFill) : .clear
    }
}

// MARK: - Search Experience Components

extension OnboardingRebranding.OnboardingView {

    struct OnboardingSearchExperiencePicker: View {
        @ObservedObject var viewModel: OnboardingSearchExperiencePickerViewModel

        var body: some View {
            SettingsAIExperimentalPickerView(
                isDuckAISelected: viewModel.isSearchAndAIChatEnabled)
        }
    }

}

// MARK: - Progress Indicator

extension OnboardingRebranding.OnboardingView {

    struct OnboardingProgressIndicator: View {
        let stepInfo: LegacyOnboardingViewState.Intro.StepInfo

        var body: some View {
            VStack(spacing: ProgressIndicatorMetrics.verticalSpacing) {
                HStack {
                    Spacer()
                    Text(verbatim: "\(stepInfo.currentStep) / \(stepInfo.totalSteps)")
                        .onboardingProgressTitleStyle()
                        .padding(.trailing, ProgressIndicatorMetrics.textPadding)
                }
                RebrandedOnboardingView.ProgressBarView(progress: percentage)
                    .frame(width: ProgressIndicatorMetrics.progressBarSize.width, height: ProgressIndicatorMetrics.progressBarSize.height)
            }
            .fixedSize()
        }

        private var percentage: Double {
            guard stepInfo.totalSteps > 0 else { return 0 }
            return Double(stepInfo.currentStep) / Double(stepInfo.totalSteps) * 100
        }
    }

    struct ProgressBarView: View {
        @Environment(\.colorScheme) private var colorScheme

        let progress: Double

        var body: some View {
            Capsule()
                .foregroundStyle(backgroundColor)
                .overlay(
                    GeometryReader { proxy in
                        RebrandedOnboardingView.ProgressBarGradient()
                            .clipShape(Capsule().inset(by: ProgressBarMetrics.strokeWidth / 2))
                            .frame(width: progress * proxy.size.width / 100)
                            .animation(.easeInOut, value: progress)
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: ProgressBarMetrics.strokeWidth)
                )
        }

        private var backgroundColor: Color {
            colorScheme == .light ? ProgressBarMetrics.backgroundLight : ProgressBarMetrics.backgroundDark
        }

        private var borderColor: Color {
            colorScheme == .light ? ProgressBarMetrics.borderLight : ProgressBarMetrics.borderDark
        }

    }

    struct ProgressBarGradient: View {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let colors: [Color]
            switch colorScheme {
            case .light:
                colors = lightGradientColors
            case .dark:
                colors = darkGradientColors
            @unknown default:
                colors = lightGradientColors
            }

            return LinearGradient(
                colors: colors,
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        private var lightGradientColors: [Color] {
            [
                Color(baseColor: .blue50),
                Color(baseColor: .purple40),
                Color(baseColor: .red50)
            ]
        }

        private var darkGradientColors: [Color] {
            [
                Color(baseColor: .blue50),
                Color(baseColor: .purple40),
                Color(baseColor: .red50)
            ]
        }
    }

}

private enum ProgressIndicatorMetrics {
    static let verticalSpacing: CGFloat = 8
    static let textPadding: CGFloat = 4
    static let progressBarSize = CGSize(width: 64, height: 4)
}

private enum ProgressBarMetrics {
    static let backgroundLight: Color = .shade(0.06)
    static let borderLight: Color = .shade(0.18)
    static let backgroundDark: Color = .tint(0.09)
    static let borderDark: Color = .tint(0.18)
    static let strokeWidth: CGFloat = 1
}

// MARK: - Previews

struct RebrandedOnboardingView_Previews: PreviewProvider {
    class MockDaxDialogDisabling: ContextualDaxDialogDisabling {
        func disableContextualDaxDialogs() {}
    }

    static var previews: some View {
        ForEach(ColorScheme.allCases, id: \.self) {
            RebrandedOnboardingView(
                model: .init(
                    pixelReporter: OnboardingPixelReporter(),
                    systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManager(
                        playerView: UIView(),
                        videoPlayer: VideoPlayerCoordinator(configuration: VideoPlayerConfiguration()),
                        eventMapper: SystemSettingsPiPTutorialPixelHandler(),
                    ),
                    daxDialogsManager: MockDaxDialogDisabling()
                )
            )
            .preferredColorScheme($0)
        }
    }
}

#Preview("Rebranded Landing Light") {
    RebrandedOnboardingView.LandingView(animationNamespace: Namespace().wrappedValue)
        .preferredColorScheme(.light)
}

#Preview("Rebranded Landing Dark") {
    RebrandedOnboardingView.LandingView(animationNamespace: Namespace().wrappedValue)
        .preferredColorScheme(.dark)
}

#Preview("Rebranded Address Bar Position") {
    RebrandedOnboardingView.AddressBarPositionContent(isSkipped: .constant(false), action: {})
}

#Preview("Rebranded Search Experience") {
    RebrandedOnboardingView.SearchExperienceContent(isSkipped: .constant(false), action: {})
}

#Preview("Rebranded App Icon Picker") {
    RebrandedOnboardingView.AppIconPicker()
}

#Preview("Rebranded Add To Dock Promo") {
    RebrandedOnboardingView.AddToDockPromoView()
}

#Preview("Rebranded Add To Dock Tutorial") {
    RebrandedOnboardingView.AddToDockTutorialView(
        title: UserText.AddToDockOnboarding.Tutorial.title,
        message: UserText.AddToDockOnboarding.Tutorial.message,
        cta: UserText.AddToDockOnboarding.Buttons.startBrowsing,
        isSkipped: .constant(false),
        action: {}
    )
    .padding()
}

#Preview("Rebranded Progress Indicator") {
    struct PreviewWrapper: View {
        @State var stepInfo = LegacyOnboardingViewState.Intro.StepInfo(currentStep: 1, totalSteps: 3)

        var body: some View {
            VStack(spacing: 100) {
                RebrandedOnboardingView.OnboardingProgressIndicator(stepInfo: stepInfo)

                Button(action: {
                    let nextStep = stepInfo.currentStep < stepInfo.totalSteps ? stepInfo.currentStep + 1 : 1
                    stepInfo = LegacyOnboardingViewState.Intro.StepInfo(currentStep: nextStep, totalSteps: stepInfo.totalSteps)
                }, label: {
                    Text(verbatim: "Update Progress")
                })
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Rebranded Progress Bar") {
    RebrandedOnboardingView.ProgressBarView(progress: 80)
        .frame(width: 200, height: 8)
}
