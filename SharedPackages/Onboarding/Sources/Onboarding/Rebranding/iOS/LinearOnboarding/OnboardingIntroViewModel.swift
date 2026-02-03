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

#if os(iOS)
import Foundation
import Common
import SystemSettingsPiPTutorial

extension OnboardingRebranding {
@MainActor
public final class OnboardingIntroViewModel: ObservableObject {

    public struct Dependencies {
        public let pixelReporter: LinearOnboardingPixelReporting
        public let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging
        public let daxDialogsManager: ContextualDaxDialogDisabling
        public let introSteps: [OnboardingIntroStep]
        public let currentOnboardingStep: OnboardingIntroStep
        public let searchExperienceProvider: OnboardingSearchExperienceProvider
        public let appIconManager: AppIconManaging
        public let addressBarPositionManager: AddressBarPositionManaging

        public init(
            pixelReporter: LinearOnboardingPixelReporting,
            systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
            daxDialogsManager: ContextualDaxDialogDisabling,
            introSteps: [OnboardingIntroStep],
            currentOnboardingStep: OnboardingIntroStep,
            searchExperienceProvider: OnboardingSearchExperienceProvider,
            appIconManager: AppIconManaging,
            addressBarPositionManager: AddressBarPositionManaging
        ) {
            self.pixelReporter = pixelReporter
            self.systemSettingsPiPTutorialManager = systemSettingsPiPTutorialManager
            self.daxDialogsManager = daxDialogsManager
            self.introSteps = introSteps
            self.currentOnboardingStep = currentOnboardingStep
            self.searchExperienceProvider = searchExperienceProvider
            self.appIconManager = appIconManager
            self.addressBarPositionManager = addressBarPositionManager
        }
    }

    struct IntroState {
        var showDaxDialogBox = false
        var showIntroViewContent = true
        var showIntroButton = false
        var animateIntroText = false
    }

    struct SkipOnboardingState {
        var animateTitle = true
        var animateMessage = false
        var showContent = false
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

    struct SearchExperienceContentState {
        var animateTitle = true
        var showContent = false
    }

    struct AddToDockState {
        var isAnimating = true
    }

    @Published private(set) var state: OnboardingRebranding.OnboardingView.ViewState = .landing {
        didSet {
            measureScreenImpression()
        }
    }

    @Published var skipOnboardingState = SkipOnboardingState()
    @Published var appIconPickerContentState = AppIconPickerContentState()
    @Published var addressBarPositionContentState = AddressBarPositionContentState()
    @Published var searchExperienceContentState = SearchExperienceContentState()
    @Published var addToDockState = AddToDockState()
    @Published var browserComparisonState = BrowserComparisonState()
    @Published var introState = IntroState()

    /// Set to true when the view controller is tapped
    @Published var isSkipped = false

    let copy: Copy
    public var onCompletingOnboardingIntro: (() -> Void)?

    let appIconManager: AppIconManaging
    let addressBarPositionManager: AddressBarPositionManaging
    let searchExperienceProvider: OnboardingSearchExperienceProvider

    private let pixelReporter: LinearOnboardingPixelReporting
    private let contextualDaxDialogs: ContextualDaxDialogDisabling
    private let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging
    private let introSteps: [OnboardingIntroStep]
    private var currentIntroStep: OnboardingIntroStep

    public init(dependencies: Dependencies) {
        self.pixelReporter = dependencies.pixelReporter
        self.contextualDaxDialogs = dependencies.daxDialogsManager
        self.systemSettingsPiPTutorialManager = dependencies.systemSettingsPiPTutorialManager
        self.searchExperienceProvider = dependencies.searchExperienceProvider
        self.appIconManager = dependencies.appIconManager
        self.addressBarPositionManager = dependencies.addressBarPositionManager
        self.introSteps = dependencies.introSteps

        if dependencies.introSteps.contains(dependencies.currentOnboardingStep) {
            self.currentIntroStep = dependencies.currentOnboardingStep
        } else if let firstStep = dependencies.introSteps.first {
            assertionFailure("Current onboarding step not found in intro steps. Falling back to first step.")
            self.currentIntroStep = firstStep
        } else {
            assertionFailure("Intro steps are empty. Falling back to intro dialog.")
            self.currentIntroStep = .introDialog(isReturningUser: false)
        }

        self.copy = .default
    }

    func onAppear() {
        makeInitialViewState()
    }

    func startOnboardingAction(isResumingOnboarding: Bool = false) {
        if isResumingOnboarding {
            pixelReporter.measureResumeOnboardingCTAAction()
        }
        makeNextViewState()
    }

    func skipOnboardingAction() {
        pixelReporter.measureSkipOnboardingCTAAction()
    }

    func confirmSkipOnboardingAction() {
        pixelReporter.measureConfirmSkipOnboardingCTAAction()
        contextualDaxDialogs.disableContextualDaxDialogs()
        onCompletingOnboardingIntro?()
    }

    func setDefaultBrowserAction() {
        pixelReporter.measureChooseBrowserCTAAction()
        systemSettingsPiPTutorialManager.playPiPTutorialAndNavigateTo(destination: .defaultBrowser)
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

    func addToDockShowTutorialAction() {
        pixelReporter.measureAddToDockPromoShowTutorialCTAAction()
    }

    func appIconPickerContinueAction() {
        if appIconManager.appIcon != .defaultAppIcon {
            pixelReporter.measureChooseCustomAppIconColor()
        }

        makeNextViewState()
    }

    func selectAddressBarPositionAction() {
        if addressBarPositionManager.currentAddressBarPosition == .bottom {
            pixelReporter.measureChooseBottomAddressBarPosition()
        }
        makeNextViewState()
    }

    func selectSearchExperienceAction() {
        if searchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding {
            pixelReporter.measureChooseAIChat()
        } else {
            pixelReporter.measureChooseSearchOnly()
        }
        makeNextViewState()
    }

    public func tapped() {
        isSkipped = true
    }

#if DEBUG || ALPHA
    func overrideOnboardingCompleted() {
        onCompletingOnboardingIntro?()
    }
#endif
}
}

// MARK: - Private

private extension OnboardingRebranding.OnboardingIntroViewModel {

    func makeInitialViewState() {
        setViewState(introStep: currentIntroStep)
    }

    func setViewState(introStep: OnboardingRebranding.OnboardingIntroStep) {
        func stepInfo() -> OnboardingRebranding.OnboardingView.ViewState.Intro.StepInfo {
            guard let currentStepIndex = introSteps.firstIndex(of: introStep) else { return .hidden }

            // Remove startOnboardingDialog from the count of total steps since we don't show the progress for that step.
            return OnboardingRebranding.OnboardingView.ViewState.Intro.StepInfo(currentStep: currentStepIndex, totalSteps: introSteps.count - 1)
        }

        let viewState = switch introStep {
        case .introDialog(let isReturningUser):
            OnboardingRebranding.OnboardingView.ViewState.onboarding(.init(type: .startOnboardingDialog(canSkipTutorial: isReturningUser), step: .hidden))
        case .browserComparison:
            OnboardingRebranding.OnboardingView.ViewState.onboarding(.init(type: .browsersComparisonDialog, step: stepInfo()))
        case .addToDockPromo:
            OnboardingRebranding.OnboardingView.ViewState.onboarding(.init(type: .addToDockPromoDialog, step: stepInfo()))
        case .appIconSelection:
            OnboardingRebranding.OnboardingView.ViewState.onboarding(.init(type: .chooseAppIconDialog, step: stepInfo()))
        case .addressBarPositionSelection:
            OnboardingRebranding.OnboardingView.ViewState.onboarding(.init(type: .chooseAddressBarPositionDialog, step: stepInfo()))
        case .searchExperienceSelection:
            OnboardingRebranding.OnboardingView.ViewState.onboarding(.init(type: .chooseSearchExperienceDialog, step: stepInfo()))
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
        case .chooseSearchExperienceDialog:
            pixelReporter.measureSearchExperienceSelectionImpression()
        }
    }

}
#endif
