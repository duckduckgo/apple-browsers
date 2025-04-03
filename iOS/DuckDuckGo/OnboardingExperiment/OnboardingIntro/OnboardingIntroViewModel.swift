//
//  OnboardingIntroViewModel.swift
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

import Foundation
import Core
import Onboarding
import class UIKit.UIApplication

@MainActor
final class OnboardingIntroViewModel: ObservableObject {

    struct IntroState {
        var showDaxDialogBox = false
        var showIntroViewContent = true
        var showIntroButton = false
        var animateIntroText = false
    }

    struct BrowserComparisonState {
        var showComparisonButton = false
        var animateComparisonText = false
    }

    struct AppIconPickerContentState {
        var animateTitle = true
        var animateMessage = false
        var showContent = false
    }

    struct AddressBarPositionContentState {
        var animateTitle = true
        var showContent = false
    }

    struct AddToDockState {
        var isAnimating = true
    }

    @Published private(set) var state: OnboardingView.ViewState = .landing {
        didSet {
            measureScreenImpression()
        }
    }

    @Published var appIconPickerContentState = AppIconPickerContentState()
    @Published var addressBarPositionContentState = AddressBarPositionContentState()
    @Published var addToDockState = AddToDockState()
    @Published var browserComparisonState = BrowserComparisonState()
    @Published var introState = IntroState()

    /// Set to true when the view controller is tapped
    @Published var isSkipped = false

    let copy: Copy
    var onCompletingOnboardingIntro: (() -> Void)?
    private let introSteps: [OnboardingIntroStep]
    private var currentIntroStep: OnboardingIntroStep

    private let defaultBrowserManager: DefaultBrowserManaging
    private let pixelReporter: LinearOnboardingPixelReporting
    private let onboardingManager: OnboardingManaging
    private let urlOpener: URLOpener
    private let appIconProvider: () -> AppIcon
    private let addressBarPositionProvider: () -> AddressBarPosition

    convenience init(pixelReporter: LinearOnboardingPixelReporting) {
        let onboardingManager = OnboardingManager()
        self.init(
            defaultBrowserManager: DefaultBrowserManager(),
            pixelReporter: pixelReporter,
            onboardingManager: onboardingManager,
            urlOpener: UIApplication.shared,
            currentOnboardingStep: onboardingManager.onboardingSteps.first ?? .introDialog,
            appIconProvider: { AppIconManager.shared.appIcon },
            addressBarPositionProvider: { AppUserDefaults().currentAddressBarPosition }
        )
    }

    init(
        defaultBrowserManager: DefaultBrowserManaging,
        pixelReporter: LinearOnboardingPixelReporting,
        onboardingManager: OnboardingManaging,
        urlOpener: URLOpener,
        currentOnboardingStep: OnboardingIntroStep,
        appIconProvider: @escaping () -> AppIcon,
        addressBarPositionProvider: @escaping () -> AddressBarPosition
    ) {
        self.defaultBrowserManager = defaultBrowserManager
        self.pixelReporter = pixelReporter
        self.onboardingManager = onboardingManager
        self.urlOpener = urlOpener
        self.appIconProvider = appIconProvider
        self.addressBarPositionProvider = addressBarPositionProvider

        introSteps = onboardingManager.onboardingSteps
        currentIntroStep = currentOnboardingStep
        copy = .default
    }

    func onAppear() {
        makeInitialViewState()
    }

    func startOnboardingAction() {
        makeNextViewState()
    }

    func setDefaultBrowserAction() {
        let urlPath = onboardingManager.settingsURLPath

        if let url = URL(string: urlPath) {
            urlOpener.open(url)
        }
        pixelReporter.measureChooseBrowserCTAAction()

        makeNextViewState()
    }

    func cancelSetDefaultBrowserAction() {
        makeNextViewState()
    }

    func addToDockContinueAction(isShowingAddToDockTutorial: Bool) {
        makeNextViewState()

        if isShowingAddToDockTutorial {
            pixelReporter.measureAddToDockTutorialDismissCTAAction()
        } else {
            pixelReporter.measureAddToDockPromoDismissCTAAction()
        }
    }

    func addtoDockShowTutorialAction() {
        pixelReporter.measureAddToDockPromoShowTutorialCTAAction()
    }

    func appIconPickerContinueAction() {
        // Check if user set DDG as default browser.
        measureDDGDefaultBrowserIfNeeded()

        if appIconProvider() != .defaultAppIcon {
            pixelReporter.measureChooseCustomAppIconColor()
        }

        makeNextViewState()
    }

    func selectAddressBarPositionAction() {
        if addressBarPositionProvider() == .bottom {
            pixelReporter.measureChooseBottomAddressBarPosition()
        }
        makeNextViewState()
    }

    func tapped() {
        isSkipped = true
    }

#if DEBUG || ALPHA
    public func overrideOnboardingCompleted() {
        LaunchOptionsHandler().overrideOnboardingCompleted()
        onCompletingOnboardingIntro?()
    }
#endif
}

// MARK: - Private

private extension OnboardingIntroViewModel {

    func makeInitialViewState() {
        setViewState(introStep: currentIntroStep)
    }

    func setViewState(introStep: OnboardingIntroStep) {
        func stepInfo() -> OnboardingView.ViewState.Intro.StepInfo {
            guard let currentStepIndex = introSteps.firstIndex(of: introStep) else { return .hidden }

            // Remove startOnboardingDialog from the count of total steps since we don't show the progress for that step.
            return OnboardingView.ViewState.Intro.StepInfo(currentStep: currentStepIndex, totalSteps: introSteps.count - 1)
        }

        let viewState = switch introStep {
        case .introDialog:
            OnboardingView.ViewState.onboarding(.init(type: .startOnboardingDialog, step: .hidden))
        case .browserComparison:
            OnboardingView.ViewState.onboarding(.init(type: .browsersComparisonDialog, step: stepInfo()))
        case .addToDockPromo:
            OnboardingView.ViewState.onboarding(.init(type: .addToDockPromoDialog, step: stepInfo()))
        case .appIconSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAppIconDialog, step: stepInfo()))
        case .addressBarPositionSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAddressBarPositionDialog, step: stepInfo()))
        }

        state = viewState
    }

    func makeNextViewState() {
        guard let currentStepIndex = introSteps.firstIndex(of: currentIntroStep) else {
            assertionFailure("Onboarding Step index not found.")
            onCompletingOnboardingIntro?()
            return
        }

        // Get next onboarding step index
        let nextStepIndex = currentStepIndex + 1

        // If the flow does not have any step remaining dismiss it
        guard let nextIntroStep = introSteps[safe: nextStepIndex] else {
            onCompletingOnboardingIntro?()
            return
        }

        // Otherwise advance to the next onboarding step
        isSkipped = false
        currentIntroStep = nextIntroStep
        setViewState(introStep: currentIntroStep)
    }

    func makeViewState(for introStep: OnboardingIntroStep) -> OnboardingView.ViewState {
        
        func stepInfo() -> OnboardingView.ViewState.Intro.StepInfo {
            guard let currentStepIndex = introSteps.firstIndex(of: introStep) else { return .hidden }

            // Remove startOnboardingDialog from the count of total steps since we don't show the progress for that step.
            return OnboardingView.ViewState.Intro.StepInfo(currentStep: currentStepIndex, totalSteps: introSteps.count - 1)
        }

        let viewState = switch introStep {
        case .introDialog:
            OnboardingView.ViewState.onboarding(.init(type: .startOnboardingDialog, step: .hidden))
        case .browserComparison:
            OnboardingView.ViewState.onboarding(.init(type: .browsersComparisonDialog, step: stepInfo()))
        case .addToDockPromo:
            OnboardingView.ViewState.onboarding(.init(type: .addToDockPromoDialog, step: stepInfo()))
        case .appIconSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAppIconDialog, step: stepInfo()))
        case .addressBarPositionSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAddressBarPositionDialog, step: stepInfo()))
        }

        return viewState
    }

    func measureDDGDefaultBrowserIfNeeded() {
        guard onboardingManager.isEnrolledInSetAsDefaultBrowserExperiment else { return }

        defaultBrowserManager.defaultBrowserInfo()
            .onNewValue { newInfo in
                if newInfo.isDefaultBrowser {
                    pixelReporter.measureDidSetDDGAsDefaultBrowser()
                } else {
                    pixelReporter.measureDidNotSetDDGAsDefaultBrowser()
                }
            }
    }

    func measureScreenImpression() {
        guard let intro = state.intro else { return }
        switch intro.type {
        case .startOnboardingDialog:
            pixelReporter.measureOnboardingIntroImpression()
        case .browsersComparisonDialog:
            pixelReporter.measureBrowserComparisonImpression()
        case .addToDockPromoDialog:
            pixelReporter.measureAddToDockPromoImpression()
        case .chooseAppIconDialog:
            pixelReporter.measureChooseAppIconImpression()
        case .chooseAddressBarPositionDialog:
            pixelReporter.measureAddressBarPositionSelectionImpression()
        }
    }

}
