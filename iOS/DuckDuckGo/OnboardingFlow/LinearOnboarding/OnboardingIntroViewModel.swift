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

import class UIKit.UIApplication
import Common
import Core
import Foundation
import Onboarding
import SystemSettingsPiPTutorial
import SetDefaultBrowserCore
import PrivacyConfig

@MainActor
final class OnboardingIntroViewModel: ObservableObject {
    enum DuckAIExperimentSelection {
        // TODO: Why `searchOnly` and `searchAndDuckAI`?, why DuckAIExperimentDefaultExperience not used here?
        case searchOnly
        case searchAndDuckAI
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

    struct RestorePromptState {
        var animateTitle = false
        var animateBody = false
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

    @Published private(set) var state: OnboardingView.ViewState = .landing {
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
    @Published var restorePromptState = RestorePromptState()

    /// Set to true when the view controller is tapped
    @Published var isSkipped = false

    let copy: Copy
    var onCompletingOnboardingIntro: (() -> Void)?
    var onOpenAIChatFromOnboarding: ((String?, Bool) -> Void)?
    var onSearchFromOnboarding: ((String) -> Void)?
    private var introSteps: [OnboardingIntroStep]
    private var currentIntroStep: OnboardingIntroStep

    private let defaultBrowserManager: DefaultBrowserManaging
    private let contextualDaxDialogs: ContextualDaxDialogDisabling
    private let pixelReporter: LinearOnboardingPixelReporting
    private let onboardingManager: OnboardingManaging
    private let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging
    private let onboardingSearchExperienceProvider: OnboardingSearchExperienceProvider
    private let appIconProvider: () -> AppIcon
    private let addressBarPositionProvider: () -> AddressBarPosition
    private let featureFlagger: FeatureFlagger
    private let restorePromptHandler: OnboardingRestorePromptHandling

    convenience init(pixelReporter: LinearOnboardingPixelReporting,
                     systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
                     daxDialogsManager: ContextualDaxDialogDisabling,
                     restorePromptHandler: OnboardingRestorePromptHandling) {
        let onboardingManager = OnboardingManager()
        let defaultBrowserInfoStore = DefaultBrowserInfoStore()
        let defaultBrowserEventMapper = DefaultBrowserPromptManagerDebugPixelHandler()
        let onboardingSearchExperienceProvider = OnboardingSearchExperience()
        self.init(
            defaultBrowserManager: DefaultBrowserManager(defaultBrowserInfoStore: defaultBrowserInfoStore,
                                                         defaultBrowserEventMapper: defaultBrowserEventMapper, defaultBrowserChecker: SystemCheckDefaultBrowserService(application: UIApplication.shared)),
            contextualDaxDialogs: daxDialogsManager,
            pixelReporter: pixelReporter,
            onboardingManager: onboardingManager,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            currentOnboardingStep: onboardingManager.onboardingSteps.first ?? .introDialog(isReturningUser: false),
            onboardingSearchExperienceProvider: onboardingSearchExperienceProvider,
            appIconProvider: { AppIconManager.shared.appIcon },
            addressBarPositionProvider: { AppUserDefaults().currentAddressBarPosition },
            featureFlagger: AppDependencyProvider.shared.featureFlagger,
            restorePromptHandler: restorePromptHandler
        )
    }

    init(
        defaultBrowserManager: DefaultBrowserManaging,
        contextualDaxDialogs: ContextualDaxDialogDisabling,
        pixelReporter: LinearOnboardingPixelReporting,
        onboardingManager: OnboardingManaging,
        systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
        currentOnboardingStep: OnboardingIntroStep,
        onboardingSearchExperienceProvider: OnboardingSearchExperienceProvider,
        appIconProvider: @escaping () -> AppIcon,
        addressBarPositionProvider: @escaping () -> AddressBarPosition,
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        restorePromptHandler: OnboardingRestorePromptHandling
    ) {
        self.defaultBrowserManager = defaultBrowserManager
        self.contextualDaxDialogs = contextualDaxDialogs
        self.pixelReporter = pixelReporter
        self.onboardingManager = onboardingManager
        self.systemSettingsPiPTutorialManager = systemSettingsPiPTutorialManager
        self.onboardingSearchExperienceProvider = onboardingSearchExperienceProvider
        self.appIconProvider = appIconProvider
        self.addressBarPositionProvider = addressBarPositionProvider
        self.featureFlagger = featureFlagger
        self.restorePromptHandler = restorePromptHandler

        introSteps = onboardingManager.onboardingSteps
        currentIntroStep = currentOnboardingStep
        copy = .default

        // TODO: Temporary override for dev validation; remove when onboarding should no longer launch on every app start.
        // let forcedExperimentStep: OnboardingIntroStep = .searchExperienceSelection
        // introSteps = [forcedExperimentStep]
        // currentIntroStep = forcedExperimentStep

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
        onboardingSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoice(enable: true)
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

    func selectSearchExperienceAction() {
        if onboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding {
            pixelReporter.measureChooseAIChat()
            insertExperimentStepIfNeeded()
        } else {
            pixelReporter.measureChooseSearchOnly()
        }
        makeNextViewState()
    }

    func selectDuckAIQueryExperimentAction(selection: DuckAIExperimentSelection) {
        switch selection {
        case .searchAndDuckAI:
            pixelReporter.measureDuckAIQueryExperimentChooseAIChat()
        case .searchOnly:
            pixelReporter.measureDuckAIQueryExperimentChooseSearchOnly()
        }
        makeNextViewState()
    }

    func tapped() {
        isSkipped = true
    }

    func openAIChatFromOnboarding(prompt: String?, autoSend: Bool) {
        onOpenAIChatFromOnboarding?(prompt, autoSend)
    }

    func searchFromOnboarding(query: String) {
        onSearchFromOnboarding?(query)
    }

    func measureDuckAIQueryExperimentQuerySubmission(isDuckAISelected: Bool, promptSource: DuckAIQueryExperimentPromptSource) {
        pixelReporter.measureDuckAIQueryExperimentQuerySubmission(
            isDuckAISelected: isDuckAISelected,
            promptSource: promptSource
        )
    }

    func restoreSyncAccountAction() {
        pixelReporter.measureAutoRestoreOnboardingRestoreCTAAction()
        restorePromptHandler.restoreSyncAccount()
        contextualDaxDialogs.disableContextualDaxDialogs()
    }

    func restorePromptSkipAction() {
        pixelReporter.measureAutoRestoreOnboardingSkipCTAAction()
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
        case .introDialog(let isReturningUser):
            OnboardingView.ViewState.onboarding(.init(type: .startOnboardingDialog(type: introDialogType(isReturningUser: isReturningUser)), step: .hidden))
        case .browserComparison:
            OnboardingView.ViewState.onboarding(.init(type: .browsersComparisonDialog, step: stepInfo()))
        case .addToDockPromo:
            OnboardingView.ViewState.onboarding(.init(type: .addToDockPromoDialog, step: stepInfo()))
        case .appIconSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAppIconDialog, step: stepInfo()))
        case .addressBarPositionSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseAddressBarPositionDialog, step: stepInfo()))
        case .searchExperienceSelection:
            OnboardingView.ViewState.onboarding(.init(type: .chooseSearchExperienceDialog, step: stepInfo()))
        case .duckAIQueryExperimentSelection(let defaultExperience):
            OnboardingView.ViewState.onboarding(.init(type: .duckAIQueryExperimentDialog(defaultExperience: defaultExperience), step: stepInfo()))
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
        case .startOnboardingDialog(let dialogType):
            pixelReporter.measureOnboardingIntroImpression()
            measureAutoRestorePromptImpressionIfNeeded(dialogType: dialogType)
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
        case .duckAIQueryExperimentDialog:
            pixelReporter.measureDuckAIQueryExperimentSelectionImpression()
        }
    }

    func insertExperimentStepIfNeeded() {
        guard let currentStepIndex = introSteps.firstIndex(of: currentIntroStep) else { return }
        guard !introSteps.contains(where: {
            if case .duckAIQueryExperimentSelection = $0 { return true }
            return false
        }) else { return }
        guard let cohort = resolveDuckAIQueryExperimentCohortID() else { return }

        switch cohort {
        case .control:
            // Control keeps the baseline flow and does not add the experiment dialog.
            return
        case .treatmentA:
            // Treatment A defaults picker to Duck.ai.
            introSteps.insert(.duckAIQueryExperimentSelection(defaultExperience: .duckAI), at: currentStepIndex + 1)
        case .treatmentB:
            // Treatment B defaults picker to Search.
            introSteps.insert(.duckAIQueryExperimentSelection(defaultExperience: .search), at: currentStepIndex + 1)
        }
    }

    func resolveDuckAIQueryExperimentCohortID() -> FeatureFlag.DuckAIQueryExperimentCohort? {
        guard featureFlagger.isFeatureOn(.onboardingDuckAIQueryExperiment) else { return nil }
        // TODO: Temporary override for dev validation; remove once remote cohort mapping is finalized.
        // return featureFlagger.resolveCohort(for: FeatureFlag.onboardingDuckAIQueryExperiment) as? FeatureFlag.DuckAIQueryExperimentCohort
        return .treatmentA
    }

    func introDialogType(isReturningUser: Bool) -> OnboardingView.ViewState.Intro.IntroDialogType {
        guard isReturningUser else {
            return .default
        }
        return restorePromptHandler.isEligibleForRestorePrompt() ? .restoreData : .skipTutorial
    }

    func measureAutoRestorePromptImpressionIfNeeded(dialogType: OnboardingView.ViewState.Intro.IntroDialogType) {
        guard dialogType == .restoreData else {
            return
        }
        pixelReporter.measureAutoRestoreOnboardingPromptShown()
    }

}
