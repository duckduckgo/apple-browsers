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
import Persistence
import PrivacyConfig
import SetDefaultBrowserCore
import SystemSettingsPiPTutorial

@MainActor
final class OnboardingIntroViewModel: ObservableObject {

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
    private let tutorialSettings: TutorialSettings
    private let duckAIOnboardingResumeStepStore: any KeyedStoring<DuckAIOnboardingStoringKeys>

    private var pendingOnboardingIntroActions: (() -> Void)?

    convenience init(pixelReporter: LinearOnboardingPixelReporting,
                     systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
                     daxDialogsManager: ContextualDaxDialogDisabling,
                     restorePromptHandler: OnboardingRestorePromptHandling,
                     onboardingManager: OnboardingManaging,
                     duckAIOnboardingResumeStepStore: (any KeyedStoring<DuckAIOnboardingStoringKeys>)? = nil) {
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
            restorePromptHandler: restorePromptHandler,
            tutorialSettings: DefaultTutorialSettings(),
            duckAIOnboardingResumeStepStore: duckAIOnboardingResumeStepStore
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
        restorePromptHandler: OnboardingRestorePromptHandling,
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        duckAIOnboardingResumeStepStore: (any KeyedStoring<DuckAIOnboardingStoringKeys>)? = nil
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
        self.tutorialSettings = tutorialSettings
        self.duckAIOnboardingResumeStepStore = if let duckAIOnboardingResumeStepStore { duckAIOnboardingResumeStepStore } else { UserDefaults.app.keyedStoring() }

        introSteps = onboardingManager.onboardingSteps
        currentIntroStep = currentOnboardingStep
        copy = .default
        restorePendingOnboardingStepIfNeeded()
    }

    func onAppear() {
        makeInitialViewState()
    }

    func startOnboardingAction(isResumingOnboarding: Bool = false) {
        if isResumingOnboarding {
            pixelReporter.measureResumeOnboardingCTAAction()
        } else {
            pixelReporter.measureStartOnboardingCTAAction()
        }
        makeNextViewState()
    }

    func skipOnboardingAction() {
        pixelReporter.measureSkipOnboardingCTAAction()
    }

    func skipOnboardingPresented() {
        pixelReporter.measureSkipOnboardingScreenImpression()
    }

    func confirmSkipOnboardingAction() {
        pixelReporter.measureConfirmSkipOnboardingCTAAction()
        onboardingSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoice(enable: true)
        tutorialSettings.hasSkippedOnboarding = true
        DuckAIOnboardingResumeCheckpointStore.clearAll(in: duckAIOnboardingResumeStepStore)
        contextualDaxDialogs.disableContextualDaxDialogs()
        onCompletingOnboardingIntro?()
    }

    func setDefaultBrowserAction() {
        pixelReporter.measureChooseBrowserCTAAction()
        systemSettingsPiPTutorialManager.playPiPTutorialAndNavigateTo(destination: .defaultBrowser)
        makeNextViewState()
    }

    func cancelSetDefaultBrowserAction() {
        pixelReporter.measureSetDefaultBrowserSkipped()
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
        pixelReporter.measureChooseAppIconColor(appIconProvider())
        makeNextViewState()
    }

    func selectAddressBarPositionAction() {
        pixelReporter.measureChooseAddressBarPosition(addressBarPositionProvider())
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

    func selectDuckAIQueryExperimentAction(selection: DuckAIQueryExperimentMode) {
        switch selection {
        case .duckAI:
            pixelReporter.measureDuckAIQueryExperimentChooseAIChat()
        case .search:
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

    func measureDuckAIQueryExperimentQuerySubmission(selection: DuckAIQueryExperimentMode, promptSource: DuckAIQueryExperimentPromptSource) {
        pixelReporter.measureDuckAIQueryExperimentQuerySubmission(
            selection: selection,
            promptSource: promptSource
        )
    }

    func restoreSyncAccountAction() {
        pixelReporter.measureAutoRestoreOnboardingRestoreCTAAction()
        restorePromptHandler.restoreSyncAccount()
        pendingOnboardingIntroActions = { [weak self] in
            self?.contextualDaxDialogs.disableContextualDaxDialogs()
        }
    }

    func restorePromptSkipAction() {
        pixelReporter.measureAutoRestoreOnboardingSkipCTAAction()
    }

#if DEBUG || ALPHA
    public func overrideOnboardingCompleted() {
        onboardingSearchExperienceProvider.storeAIChatSearchInputDuringOnboardingChoice(enable: true)
        tutorialSettings.hasSkippedOnboarding = true
        contextualDaxDialogs.disableContextualDaxDialogs()
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
        case .duckAIQueryExperimentSelection:
            OnboardingView.ViewState.onboarding(.init(type: .duckAIQueryExperimentDialog(defaultMode: duckAIQueryExperimentDefaultMode), step: stepInfo()))
        }

        state = viewState
    }

    func makeNextViewState() {
        guard let currentStepIndex = introSteps.firstIndex(of: currentIntroStep) else {
            assertionFailure("Onboarding Step index not found.")
            DuckAIOnboardingResumeCheckpointStore.clearAll(in: duckAIOnboardingResumeStepStore)
            completeOnboardingIntro()
            return
        }

        // Get next onboarding step index
        let nextStepIndex = currentStepIndex + 1

        // If the flow does not have any step remaining dismiss it
        guard let nextIntroStep = introSteps[safe: nextStepIndex] else {
            if currentIntroStep != .duckAIQueryExperimentSelection {
                DuckAIOnboardingResumeCheckpointStore.clearAll(in: duckAIOnboardingResumeStepStore)
            }
            completeOnboardingIntro()
            return
        }

        // Otherwise advance to the next onboarding step
        isSkipped = false
        currentIntroStep = nextIntroStep
        persistPendingOnboardingStep(for: currentIntroStep)
        setViewState(introStep: currentIntroStep)
    }

    func completeOnboardingIntro() {
        performPendingOnboardingIntroActions()
        onCompletingOnboardingIntro?()
    }

    func performPendingOnboardingIntroActions() {
        pendingOnboardingIntroActions?()
        pendingOnboardingIntroActions = nil
    }

    func restorePendingOnboardingStepIfNeeded() {
        guard duckAIOnboardingResumeStepStore.resumeStep == .duckAIQueryExperimentSelection else {
            return
        }
        guard featureFlagger.isFeatureOn(.onboardingDuckAIQueryExperiment) else {
            DuckAIOnboardingResumeCheckpointStore.clearAll(in: duckAIOnboardingResumeStepStore)
            return
        }

        if !introSteps.contains(.duckAIQueryExperimentSelection) {
            if let searchExperienceIndex = introSteps.firstIndex(of: .searchExperienceSelection) {
                introSteps.insert(.duckAIQueryExperimentSelection, at: searchExperienceIndex + 1)
            } else {
                introSteps.append(.duckAIQueryExperimentSelection)
            }
        }
        currentIntroStep = .duckAIQueryExperimentSelection
    }

    func persistPendingOnboardingStep(for step: OnboardingIntroStep) {
        switch step {
        case .duckAIQueryExperimentSelection:
            duckAIOnboardingResumeStepStore.resumeExperimentPrompt = nil
            duckAIOnboardingResumeStepStore.resumeStep = .duckAIQueryExperimentSelection
        default:
            break
        }
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
        guard let currentStepIndex = introSteps.firstIndex(of: currentIntroStep),
              let cohort = resolveDuckAIQueryExperimentCohortID(), cohort != .control,
              !introSteps.contains(.duckAIQueryExperimentSelection) else {
            return
        }
        introSteps.insert(.duckAIQueryExperimentSelection, at: currentStepIndex + 1)
    }

    var duckAIQueryExperimentDefaultMode: DuckAIQueryExperimentMode {
        switch resolveDuckAIQueryExperimentCohortID() {
        case .treatmentB:
            .search
        case .treatmentA:
            .duckAI
        case .control, .none:
            .search
        }
    }

    func resolveDuckAIQueryExperimentCohortID() -> FeatureFlag.DuckAIQueryExperimentCohort? {
        guard featureFlagger.isFeatureOn(.onboardingDuckAIQueryExperiment) else { return nil }
        return featureFlagger.resolveCohort(for: FeatureFlag.onboardingDuckAIQueryExperiment) as? FeatureFlag.DuckAIQueryExperimentCohort
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
