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
import FoundationExtensions
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

    @Published private(set) var state: OnboardingView.ViewState {
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

    var onCompletingOnboardingIntro: (() -> Void)?
    var onOpenAIChatFromOnboarding: ((String?, Bool) -> Void)?
    var onSearchFromOnboarding: ((String) -> Void)?
    /// Invoked when the flow reaches an `OnboardingIntroStep.interlude(_)` step. The host is expected to dismiss the onboarding UI, run its own experience, and call `resumeOnboardingFromInterlude()` once finished.
    var onOnboardingInterlude: ((OnboardingIntroStep.Interlude) -> Void)?
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
    private let onboardingResumeStepStore: any KeyedStoring<OnboardingStoringKeys>
    private let contentProvider: OnboardingIntroContentProviding

    private var pendingOnboardingIntroActions: (() -> Void)?

    convenience init(pixelReporter: LinearOnboardingPixelReporting,
                     systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
                     daxDialogsManager: ContextualDaxDialogDisabling,
                     restorePromptHandler: OnboardingRestorePromptHandling,
                     onboardingManager: OnboardingManaging,
                     onboardingResumeStepStore: (any KeyedStoring<OnboardingStoringKeys>)? = nil) {
        let defaultBrowserInfoStore = DefaultBrowserInfoStore()
        let defaultBrowserEventMapper = DefaultBrowserPromptManagerDebugPixelHandler()
        let onboardingSearchExperienceProvider = OnboardingSearchExperience()
        let featureFlagger = AppDependencyProvider.shared.featureFlagger
        let tutorialSettings = DefaultTutorialSettings()
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
            featureFlagger: featureFlagger,
            restorePromptHandler: restorePromptHandler,
            tutorialSettings: tutorialSettings,
            contentProvider: OnboardingIntroContentProvider(
                flowType: onboardingManager.currentOnboardingFlow,
                featureFlagger: featureFlagger
            ),
            onboardingResumeStepStore: onboardingResumeStepStore
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
        featureFlagger: FeatureFlagger,
        restorePromptHandler: OnboardingRestorePromptHandling,
        tutorialSettings: TutorialSettings,
        contentProvider: OnboardingIntroContentProviding,
        onboardingResumeStepStore: (any KeyedStoring<OnboardingStoringKeys>)? = nil
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
        self.contentProvider = contentProvider
        self.onboardingResumeStepStore = if let onboardingResumeStepStore { onboardingResumeStepStore } else { UserDefaults.app.keyedStoring() }

        introSteps = onboardingManager.onboardingSteps
        state = .landing(contentProvider.landingContent)
        currentIntroStep = currentOnboardingStep
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
        OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)
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

    func aiComparisonAction() {
        pixelReporter.measureAiComparisonCTAAction()
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
            insertDuckAIQuerySelectionStepIfNeeded()
        } else {
            pixelReporter.measureChooseSearchOnly()
        }
        makeNextViewState()
    }

    func selectDuckAIQueryAction(selection: DuckAIQueryMode) {
        switch selection {
        case .duckAI:
            pixelReporter.measureDuckAIQueryChooseAIChat()
        case .search:
            pixelReporter.measureDuckAIQueryChooseSearchOnly()
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

    func measureDuckAIQuerySubmission(selection: DuckAIQueryMode, promptSource: DuckAIQueryPromptSource) {
        pixelReporter.measureDuckAIQuerySubmission(
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

    /// Resumes the linear onboarding after the host has finished an interlude.
    ///
    /// Call this once the host's interlude experience completes. The view model will advance to the step immediately after the current interlude in `introSteps`.
    func resumeOnboardingFromInterlude() {
        guard case .interlude = currentIntroStep else {
            assertionFailure("resumeOnboardingFromInterlude() called outside an interlude step (current: \(currentIntroStep))")
            return
        }
        makeNextViewState()
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
            // Remove interlude steps from counting the total number of steps as they're not rendered
            let stepsWithoutInterludes = introSteps.filter { !$0.isInterlude }

            guard let currentStepIndex = stepsWithoutInterludes.firstIndex(of: introStep) else { return .hidden }

            // Remove startOnboardingDialog from the count of total steps since we don't show the progress for that step.
            return OnboardingView.ViewState.Intro.StepInfo(currentStep: currentStepIndex, totalSteps: stepsWithoutInterludes.count - 1)
        }

        func mapToViewState(renderableStep: OnboardingIntroStep.RenderableStep) -> OnboardingView.ViewState {
            switch renderableStep {
            case .introDialog(let isReturningUser):
                return .onboarding(
                    .init(
                        type: .startOnboardingDialog(content: contentProvider.introStepContent, type: introDialogType(isReturningUser: isReturningUser)),
                        step: .hidden
                    )
                )
            case .browserComparison:
                return .onboarding(
                    .init(
                        type: .browsersComparisonDialog(content: contentProvider.browserComparisonContent),
                        step: stepInfo()
                    )
                )
            case .aiComparison:
                return .onboarding(
                    .init(
                        type: .aiComparisonDialog(content: contentProvider.aiComparisonContent),
                        step: stepInfo()
                    )
                )
            case .addToDockPromo:
                return .onboarding(
                    .init(
                        type: .addToDockPromoDialog(content: contentProvider.addToDockContent),
                        step: stepInfo()
                    )
                )
            case .appIconSelection:
                return .onboarding(
                    .init(
                        type: .chooseAppIconDialog(content: contentProvider.appIconColorContent),
                        step: stepInfo()
                    )
                )
            case .addressBarPositionSelection:
                return .onboarding(
                    .init(
                        type: .chooseAddressBarPositionDialog(content: contentProvider.addressBarPositionContent),
                        step: stepInfo()
                    )
                )
            case .searchExperienceSelection:
                return .onboarding(
                    .init(
                        type: .chooseSearchExperienceDialog(content: contentProvider.searchExperienceContent),
                        step: stepInfo()
                    )
                )
            case .duckAIQuerySelection:
                let isDuckAiTailoredFlow = onboardingManager.currentOnboardingFlow == .duckAI
                // Duck.ai Tailored flow pre-selects Duck.ai; the default flow always pre-selects Search.
                let duckAIQueryMode: DuckAIQueryMode = isDuckAiTailoredFlow ? .duckAI : .search
                // Duck.ai Tailored flow shows step counter; the default flow hides it.
                let progressStep: OnboardingView.ViewState.Intro.StepInfo = isDuckAiTailoredFlow ? stepInfo() : .hidden
                return .onboarding(
                    .init(
                        type: .duckAIQueryDialog(content: contentProvider.duckAIQueryContent, defaultMode: duckAIQueryMode),
                        step: progressStep
                    )
                )
            }
        }

        switch introStep {
        case let .interlude(interlude):
            // Interlude steps don't render a view state. They inform the delegate that an interlude is starting.
            // The delegate will resume the onboarding by calling `resumeOnboardingFromInterlude()` when finished.
            onOnboardingInterlude?(interlude)
        case let .renderable(renderable):
            state = mapToViewState(renderableStep: renderable)
        }
    }

    func makeNextViewState() {
        guard let currentStepIndex = introSteps.firstIndex(of: currentIntroStep) else {
            assertionFailure("Onboarding Step index not found.")
            OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)
            completeOnboardingIntro()
            return
        }

        // Get next onboarding step index
        let nextStepIndex = currentStepIndex + 1

        // If the flow does not have any step remaining dismiss it
        guard let nextIntroStep = introSteps[safe: nextStepIndex] else {
            if currentIntroStep != .duckAIQuerySelection {
                OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)
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
        guard let resumeStep = onboardingResumeStepStore.resumeStep else { return }

        switch resumeStep {
        case .duckAIQuerySelection:
            if !introSteps.contains(.duckAIQuerySelection) {
                let insertIndex = introSteps.firstIndex(of: .searchExperienceSelection).map { $0 + 1 } ?? introSteps.count
                introSteps.insert(.duckAIQuerySelection, at: insertIndex)
            }
            currentIntroStep = .duckAIQuerySelection

        case .browserComparison where introSteps.contains(.browserComparison):
            currentIntroStep = .browserComparison
        case .aiComparison where introSteps.contains(.aiComparison):
            currentIntroStep = .aiComparison
        case .addToDockPromo where introSteps.contains(.addToDockPromo):
            currentIntroStep = .addToDockPromo
        case .appIconSelection where introSteps.contains(.appIconSelection):
            currentIntroStep = .appIconSelection
        case .addressBarPositionSelection where introSteps.contains(.addressBarPositionSelection):
            currentIntroStep = .addressBarPositionSelection
        case .searchExperienceSelection where introSteps.contains(.searchExperienceSelection):
            currentIntroStep = .searchExperienceSelection
        case .duckAIAnswerStep:
            break // handled separately by restorePendingDuckAIAnswerStepIfNeeded in MainViewController
        case .interludeDuckAI where introSteps.contains(.interlude(.duckAI)):
            currentIntroStep = .interlude(.duckAI)

        default:
            // Stored step is not available in the current flow — clear and start from the beginning.
            OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)
        }
    }

    func persistPendingOnboardingStep(for step: OnboardingIntroStep) {
        if step == .duckAIQuerySelection {
            onboardingResumeStepStore.resumeDuckAIQueryPrompt = nil
        }
        onboardingResumeStepStore.resumeStep = step.resumeStep
    }

    func measureScreenImpression() {
        guard let intro = state.intro else { return }
        switch intro.type {
        case .startOnboardingDialog(_, let dialogType):
            pixelReporter.measureOnboardingIntroImpression()
            measureAutoRestorePromptImpressionIfNeeded(dialogType: dialogType)
        case .browsersComparisonDialog:
            pixelReporter.measureBrowserComparisonImpression()
        case .aiComparisonDialog:
            pixelReporter.measureAiComparisonImpression()
        case .addToDockPromoDialog:
            pixelReporter.measureAddToDockPromoImpression()
        case .chooseAppIconDialog:
            pixelReporter.measureChooseAppIconImpression()
        case .chooseAddressBarPositionDialog:
            pixelReporter.measureAddressBarPositionSelectionImpression()
        case .chooseSearchExperienceDialog:
            pixelReporter.measureSearchExperienceSelectionImpression()
        case .duckAIQueryDialog:
            pixelReporter.measureDuckAIQuerySelectionImpression()
        }
    }

    func insertDuckAIQuerySelectionStepIfNeeded() {
        guard let currentStepIndex = introSteps.firstIndex(of: currentIntroStep),
              onboardingManager.currentOnboardingFlow == .default,
              !introSteps.contains(.duckAIQuerySelection) else {
            return
        }
        introSteps.insert(.duckAIQuerySelection, at: currentStepIndex + 1)
    }

    func introDialogType(isReturningUser: Bool) -> OnboardingView.ViewState.Intro.IntroDialogType {
        guard isReturningUser else {
            return .default
        }
        // Restore-data prompt is suppressed in the Duck.ai tailored flow.
        guard onboardingManager.currentOnboardingFlow != .duckAI else {
            // Fire a pixel to measure the volume of re‑installers who previously synced their device and would normally see the restore-data flow but instead experience the CPP onboarding (honouring the CPP install context).
            // Consider deleting this pixel ini the future if the information is no longer needed
            if restorePromptHandler.isEligibleForRestorePrompt() {
                DailyPixel.fireDailyAndCount(pixel: .onboardingSyncAutoRestoreUserFromDuckAiFlow)
            }
            return .skipTutorial
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
