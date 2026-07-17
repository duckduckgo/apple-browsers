//
//  OnboardingManager.swift
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

import AVKit
import BrowserServicesKit
import Core
import Onboarding
import Persistence
import PrivacyConfig

enum OnboardingUserType: String, Equatable, CaseIterable, CustomStringConvertible {
    case notSet
    case newUser
    case returningUser

    var description: String {
        switch self {
        case .notSet:
            "Not Set - Using Real Value"
        case .newUser:
            "New User"
        case .returningUser:
            "Returning User"
        }
    }
}

protocol OnboardingAddToDockVisibilityManager {
    var userHasSeenAddToDockPromoDuringOnboarding: Bool { get }
}

protocol OnboardingFlowProviding {
    var currentOnboardingFlow: OnboardingFlowType { get }
}

protocol OnboardingFlowManaging: OnboardingFlowProviding {
    func configureOnboardingFlow(from url: URL?)
}

typealias OnboardingManaging = OnboardingStepsProvider & OnboardingDownloadReasonHandling & OnboardingAddToDockVisibilityManager & OnboardingFlowManaging

final class OnboardingManager {
    private let onboardingFlowEvaluator: OnboardingFlowEvaluating
    private var appDefaults: OnboardingDebugAppSettings
    private let featureFlagger: FeatureFlagger
    private let variantManager: VariantManager
    private let isIphone: Bool
    private let tutorialSettings: TutorialSettings
    private let sharedPixelsStorage: any KeyedStoring<OnboardingSharedPixelsKeys>
    private let onboardingResumeStepStore: any KeyedStoring<OnboardingStoringKeys>

    private let iPhoneFlow: [OnboardingIntroStep] = [
        .setDefaultBrowser,
        .addToDockPromo,
        .appIconSelection,
        .addressBarPositionSelection,
        .searchExperienceSelection
    ]
    private let iPadFlow: [OnboardingIntroStep] = [.setDefaultBrowser, .appIconSelection]

    var isNewUser: Bool {
#if DEBUG || ALPHA
        // If debug or alpha build enable testing the experiment with cohort override.
        // If running unit tests do not override behaviour.
        switch appDefaults.onboardingUserType {
        case .notSet:
            variantManager.currentVariant?.name != VariantIOS.returningUser.name
        case .newUser:
            true
        case .returningUser:
            false
        }
#else
        variantManager.currentVariant?.name != VariantIOS.returningUser.name
#endif
    }

    init(
        appDefaults: OnboardingDebugAppSettings = AppDependencyProvider.shared.appSettings,
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        variantManager: VariantManager = DefaultVariantManager(),
        isIphone: Bool = UIDevice.current.userInterfaceIdiom == .phone,
        onboardingFlowEvaluator: OnboardingFlowEvaluating = AppStoreCustomProductPageEvaluator(),
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        sharedPixelsStorage: (any KeyedStoring<OnboardingSharedPixelsKeys>)? = nil,
        onboardingResumeStepStore: (any KeyedStoring<OnboardingStoringKeys>)? = nil
    ) {
        self.appDefaults = appDefaults
        self.featureFlagger = featureFlagger
        self.variantManager = variantManager
        self.isIphone = isIphone
        self.onboardingFlowEvaluator = onboardingFlowEvaluator
        self.tutorialSettings = tutorialSettings
        self.sharedPixelsStorage = if let sharedPixelsStorage { sharedPixelsStorage } else { UserDefaults.app.keyedStoring() }
        self.onboardingResumeStepStore = if let onboardingResumeStepStore { onboardingResumeStepStore } else { UserDefaults.app.keyedStoring() }
    }
}

// MARK: - New User Debugging

protocol OnboardingNewUserProviderDebugging: AnyObject {
    var onboardingUserTypeDebugValue: OnboardingUserType { get set }
}

extension OnboardingManager: OnboardingNewUserProviderDebugging {

    var onboardingUserTypeDebugValue: OnboardingUserType {
        get {
            appDefaults.onboardingUserType
        }
        set {
            appDefaults.onboardingUserType = newValue
        }
    }
}

// MARK: - Onboarding Steps Provider

/// Represent a single step in the linear-onboarding sequence.
enum OnboardingIntroStep: Equatable {
    /// A step that render a `ViewState` in the onboarding view. Maps to a dialog in the linear onboarding sequence.
    case renderable(RenderableStep)

    /// A step that pauses the linear onboarding to hand control to the host (e.g. for a short, contextual browsing session), then expects the host to resume the linear flow once it completes.
    /// Unlike renderable cases, an interlude step does not render a view state in the onboarding view.
    case interlude(Interlude)

    var isInterlude: Bool {
        switch self {
        case .interlude:
            return true
        default:
            return false
        }
    }
}

// Ergonomic factories so call sites can write `.setDefaultBrowser` instead of `.renderable(.setDefaultBrowser)`.
// Mirror every new `RenderableStep` case here.
extension OnboardingIntroStep {
    static let downloadReasonSelection: Self = .renderable(.downloadReasonSelection)
    static let searchPrivacySettingsSelection: Self = .renderable(.searchPrivacySettingsSelection)
    static let aiSearchSettingsSelection: Self = .renderable(.aiSearchSettingsSelection)
    static let aiModelSelection: Self = .renderable(.aiModelSelection)
    static let toggleInputModeSelection: Self = .renderable(.toggleInputModeSelection)
    static let keepDuckAISelection: Self = .renderable(.keepDuckAISelection)
    static let duckPlayerSelection: Self = .renderable(.duckPlayerSelection)
    static let setDefaultBrowser: Self = .renderable(.setDefaultBrowser)
    static let aiIntro: Self = .renderable(.aiIntro)
    static let addToDockPromo: Self = .renderable(.addToDockPromo)
    static let appIconSelection: Self = .renderable(.appIconSelection)
    static let addressBarPositionSelection: Self = .renderable(.addressBarPositionSelection)
    static let searchExperienceSelection: Self = .renderable(.searchExperienceSelection)
    static let duckAIQuerySelection: Self = .renderable(.duckAIQuerySelection)

    static func introDialog(isReturningUser: Bool) -> Self {
        .renderable(.introDialog(isReturningUser: isReturningUser))
    }
}

extension OnboardingIntroStep {

    enum RenderableStep: Equatable {
        case introDialog(isReturningUser: Bool)
        case downloadReasonSelection // NA Experiment: Asks the user why they downloaded the app to tailor the remaining default-flow steps.
        case searchPrivacySettingsSelection  // NA Experiment Search Personalisation: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=426-90387&m=dev
        case aiSearchSettingsSelection // NA Experiment AI Personalisation: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=437-33717&m=dev
        case aiModelSelection // NA Experiment AI Model Personalisation: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=426-77761&m=dev
        case toggleInputModeSelection // NA Experiment Omnibar Input Mode Personalisation: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=426-76416&m=dev
        case keepDuckAISelection // NA Experiment Duck.ai Personalisation: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=437-33810&m=dev
        case duckPlayerSelection // NA Experiment Duck Player Personalisation: https://www.figma.com/design/vsuCJP9OGykRkk1iZIU0ek/Mobile-Onboarding---Segmented?node-id=426-83427&m=dev
        case setDefaultBrowser
        case aiIntro
        case appIconSelection
        case addToDockPromo
        case addressBarPositionSelection
        case searchExperienceSelection
        case duckAIQuerySelection
    }

    /// Identifies which interlude experience the host should run.
    ///
    /// New interlude types can be added here without changing the linear
    /// onboarding's view-state mapping — the view model treats all interludes
    /// uniformly (callback out, no view state).
    enum Interlude: Equatable {
        /// Hands off to the Duck.ai Fire onboarding flow after the user
        /// submits their first query on the Duck.ai query-selection step.
        case duckAI
    }
}

extension OnboardingIntroStep {
    /// The resume checkpoint that should be persisted when this step is reached, or `nil` if no checkpoint is needed.
    var resumeStep: OnboardingResumeStep? {
        switch self {
        case .renderable(.introDialog): return nil
        case .renderable(.downloadReasonSelection): return .downloadReasonSelection
        case .renderable(.searchPrivacySettingsSelection): return .searchPrivacySettingsSelection
        case .renderable(.aiSearchSettingsSelection): return .aiSearchSettingsSelection
        case .renderable(.aiModelSelection): return .aiModelSelection
        case .renderable(.toggleInputModeSelection): return .toggleInputModeSelection
        case .renderable(.keepDuckAISelection): return .keepDuckAISelection
        case .renderable(.duckPlayerSelection): return .duckPlayerSelection
        case .renderable(.setDefaultBrowser): return .setDefaultBrowser
        case .renderable(.aiIntro): return .aiIntro
        case .renderable(.addToDockPromo): return .addToDockPromo
        case .renderable(.appIconSelection): return .appIconSelection
        case .renderable(.addressBarPositionSelection): return .addressBarPositionSelection
        case .renderable(.searchExperienceSelection): return .searchExperienceSelection
        case .renderable(.duckAIQuerySelection): return .duckAIQuerySelection
        case .interlude(.duckAI): return .interludeDuckAI
        }
    }
}

extension OnboardingIntroStep {
    /// Whether this step counts toward the onboarding progress indicator.
    ///
    /// Excludes steps that aren't part of the tracked sequence: the intro dialog, interludes
    /// (which render no view state), and the Download Reason Screen. Consumed when computing the
    /// current/total step counts shown in the progress bar.
    func countsTowardProgress(flow: OnboardingFlowType) -> Bool {
        switch self {
        case .renderable(.introDialog), .renderable(.downloadReasonSelection), .interlude:
            return false
        case .duckAIQuerySelection where flow == .duckAI:
            return true
        case .duckAIQuerySelection where flow == .default:
            return false
        default:
            return true
        }
    }
}

/// Persisted checkpoint allowing the onboarding flow to resume after an app relaunch.
enum OnboardingResumeStep: String {
    /// User reached the Download Screen but has not yet selected a download reason.
    case downloadReasonSelection
    case searchPrivacySettingsSelection // NA Experiment: reason-tailored step checkpoints.
    case aiSearchSettingsSelection // NA Experiment: reason-tailored step checkpoints.
    case aiModelSelection // NA Experiment: reason-tailored step checkpoints.
    case toggleInputModeSelection // NA Experiment: reason-tailored step checkpoints.
    case keepDuckAISelection // NA Experiment: reason-tailored step checkpoints.
    case duckPlayerSelection // NA Experiment: reason-tailored step checkpoints.
    case setDefaultBrowser = "browserComparison"
    case aiIntro = "aiComparison"
    case addToDockPromo
    case appIconSelection
    case addressBarPositionSelection
    case searchExperienceSelection
    /// User reached the Duck.ai / search selection screen but has not yet submitted a query.
    case duckAIQuerySelection
    /// User submitted a Duck.ai query and is waiting for the Fire onboarding dialog.
    case duckAIAnswerStep
    /// User is currently inside the Duck.ai interlude (a contextual browsing session
    /// hosted outside the linear onboarding); on relaunch, the host re-enters the interlude.
    case interludeDuckAI
}

protocol OnboardingStepsProvider: AnyObject {
    var onboardingSteps: [OnboardingIntroStep] { get }
}

/// Handles the user's answer on the Download Screen for the `onboardingFlowByDownloadReasonExperiment` experiment.
protocol OnboardingDownloadReasonHandling: AnyObject {
    /// Records the user's selected download reason and returns the steps that follow the Download Screen.
    ///
    /// Called by the view model when the user answers the Download Screen. The reason is persisted
    /// (so the flow can resume after relaunch) and the returned steps are spliced into the live flow.
    func selectDownloadReason(_ reason: OnboardingDownloadReason) -> [OnboardingIntroStep]
}

extension OnboardingManager: OnboardingStepsProvider {

    var onboardingSteps: [OnboardingIntroStep] {
        stepsForCurrentFlow()
    }

}

extension OnboardingManager: OnboardingDownloadReasonHandling {

    func selectDownloadReason(_ reason: OnboardingDownloadReason) -> [OnboardingIntroStep] {
        tutorialSettings.onboardingDownloadReason = reason
        return remainingDefaultFlowSteps(for: reason)
    }

}

// MARK: - Onboarding Manager + Add To Dock

extension OnboardingManager: OnboardingAddToDockVisibilityManager {

    var userHasSeenAddToDockPromoDuringOnboarding: Bool {
        onboardingSteps.contains(.addToDockPromo)
    }

}

// MARK: - Onboarding Manager + Onboarding Flows

extension OnboardingManager: OnboardingFlowProviding {

    var currentOnboardingFlow: OnboardingFlowType {
        tutorialSettings.onboardingFlowType ?? .default
    }

}

extension OnboardingManager: OnboardingFlowManaging {

    /// Configure the onboarding flow based on the app action (e.g., deep link)
    /// This should be called early in the app lifecycle, before onboarding is presented
    func configureOnboardingFlow(from url: URL?) {
        Logger.onboarding.debug("Configuring Onboarding Flow")
        // Continue only if user hasn't seen
        guard !tutorialSettings.hasSeenOnboarding else {
            Logger.onboarding.debug("User has completed onboarding. Skipping.")
            return
        }

        // Don't reconfigure onboarding flow if already set. This prevents onboarding flow switching mid-onboarding.
        guard tutorialSettings.onboardingFlowType == nil else {
            Logger.onboarding.debug("Onboarding flow already configured, skipping reconfiguration")
            return
        }

        let resolvedFlow: OnboardingFlowType
        let onboardingSource: OnboardingSource

#if DEBUG || ALPHA
        switch appDefaults.onboardingFlowType {
        case .none:
            (resolvedFlow, onboardingSource) = resolveOnboardingFromEvaluator(url: url)
        case .default:
            Logger.onboarding.debug("Onboarding flow - Debug `.default` flow override active")
            resolvedFlow = .default
            onboardingSource = .default
        case .duckAI:
            Logger.onboarding.debug("Onboarding flow - Debug `.duckAI` flow override active")
            resolvedFlow = .duckAI
            onboardingSource = .duckAICPP
        }
#else
        (resolvedFlow, onboardingSource) = resolveOnboardingFromEvaluator(url: url)
#endif

        // Clear any stale resume checkpoint persisted before the flow was configured
        // (e.g. by a previous build that didn't set onboardingFlowType), so we don't
        // resume into a step that appears at a different point of the flow causing the user to skip important steps.
        OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)

        tutorialSettings.onboardingFlowType = resolvedFlow
        // Enrol the user in the download reason experiment before sending pixels.
        // Users enrolled in the experiment will override the flow type sent to the pixels to avoid polluting onboarding dashboards.
        enrollInDownloadReasonExperimentIfNeeded(resolvedFlow: resolvedFlow)
        persistOnboardingPixelContext(flow: resolvedFlow, source: onboardingSource)
    }

    private func resolveOnboardingFromEvaluator(url: URL?) -> (flow: OnboardingFlowType, source: OnboardingSource) {
        let evaluatedOnboarding = onboardingFlowEvaluator.evaluateOnboardingFlow(from: url)
        Logger.onboarding.debug("Configured onboarding flow: \(evaluatedOnboarding.flow.rawValue, privacy: .public)")

        let resolvedFlow: OnboardingFlowType
        switch evaluatedOnboarding.flow {
        case .duckAI where !featureFlagger.isFeatureOn(.onboardingDuckAIFlow):
            Logger.onboarding.debug("Duck.ai onboarding feature disabled. Reverting to default onboarding")
            resolvedFlow = .default
        case .duckAI where !isIphone:
            Logger.onboarding.debug("Duck.ai onboarding not available for iPad. Reverting to default onboarding")
            resolvedFlow = .default
        default:
            resolvedFlow = evaluatedOnboarding.flow
        }
        return (resolvedFlow, evaluatedOnboarding.source)
    }

}

// MARK: - Private

private extension OnboardingManager {

    var isEnrolledInDownloadReasonExperiment: Bool {
        return downloadReasonExperimentCohort != nil
    }

    var downloadReasonExperimentCohort: FeatureFlag.OnboardingFlowByDownloadReasonExperimentCohort? {
        // The experiment targets new installers on iPhone. Locale/region targeting is handled remotely
        // via the feature flag rollout, so it isn't gated here.
        guard isIphone, isNewUser else { return nil }
        return featureFlagger.resolveCohort(for: FeatureFlag.onboardingFlowByDownloadReasonExperiment) as? FeatureFlag.OnboardingFlowByDownloadReasonExperimentCohort
    }

    /// Enrolls default-flow users in the download-reason experiment.
    func enrollInDownloadReasonExperimentIfNeeded(resolvedFlow: OnboardingFlowType) {
        guard resolvedFlow == .default else { return }
        _ = downloadReasonExperimentCohort
    }

    /// Persist the flow and source for onboarding pixels based on the evaluated context.
    /// This must be called before onboarding is presented.
    func persistOnboardingPixelContext(flow: OnboardingFlowType, source: OnboardingSource) {
        /// Both download-reason experiment arms (control and treatment) are reported under the
        /// `.tailoredByDownloadReason` pixel so the experiment population is excluded from the `.default`
        /// onboarding dashboards. Reads the cohort assigned earlier by `enrollInDownloadReasonExperimentIfNeeded`.
        func onboardingPixelFlow(for flow: OnboardingFlowType) -> OnboardingPixelParameter.Flow {
            if flow == .default, isEnrolledInDownloadReasonExperiment {
                return .tailoredByDownloadReason
            }
            return OnboardingPixelParameter.Flow(flow)
        }

        sharedPixelsStorage.onboardingFlow = onboardingPixelFlow(for: flow)
        sharedPixelsStorage.onboardingSource = OnboardingPixelParameter.Source(source)
    }

    func stepsForCurrentFlow() -> [OnboardingIntroStep] {
        let introStep = OnboardingIntroStep.introDialog(isReturningUser: !isNewUser)
        switch tutorialSettings.onboardingFlowType {
        case .default where downloadReasonExperimentCohort == .treatment:
            // Download-reason experiment, treatment arm.
            return [introStep] + downloadReasonTreatmentSteps()
        case .none, .default:
            // Not-yet-configured, un-enrolled, or control, show the standard default flow.
            return [introStep] + defaultFlowSteps(isIphone: isIphone)
        case .duckAI:
            // Duck ai tailored flow for users installing the app from the Duck.ai CPP
            return [introStep] + duckAITailoredFlowSteps()
        }
    }

    func defaultFlowSteps(isIphone: Bool) -> [OnboardingIntroStep] {
        isIphone ? iPhoneFlow : iPadFlow
    }

    func duckAITailoredFlowSteps() -> [OnboardingIntroStep] {
        [.aiIntro, .duckAIQuerySelection, .interlude(.duckAI), .addToDockPromo, .setDefaultBrowser, .addressBarPositionSelection]
    }

    /// The treatment-arm flow for the download-reason experiment.
    ///
    /// Before the user answers, only the Download Screen is known. Once a reason is persisted (via
    /// `selectDownloadReason(_:)`), the reason-tailored steps are appended so the flow is complete
    /// when resumed after a relaunch.
    func downloadReasonTreatmentSteps() -> [OnboardingIntroStep] {
        guard let reason = tutorialSettings.onboardingDownloadReason else {
            return [.downloadReasonSelection]
        }
        return [.downloadReasonSelection] + remainingDefaultFlowSteps(for: reason)
    }

    /// The steps that follow the Download Screen for a given download reason.
    func remainingDefaultFlowSteps(for reason: OnboardingDownloadReason) -> [OnboardingIntroStep] {
        let commonSteps: [OnboardingIntroStep] = [.addressBarPositionSelection, .addToDockPromo, .appIconSelection, .duckAIQuerySelection]

        let personalisationSteps: [OnboardingIntroStep]
        switch reason {
        case .browserPrivately:
            personalisationSteps = [.searchPrivacySettingsSelection, .searchExperienceSelection]
        case .privateAIChat:
            personalisationSteps = [.aiModelSelection, .toggleInputModeSelection]
        case .noAI:
            personalisationSteps = [.aiSearchSettingsSelection, .keepDuckAISelection]
        case .blockAds:
            personalisationSteps = [.duckPlayerSelection, .searchExperienceSelection]
        }

        return [.setDefaultBrowser] + personalisationSteps + commonSteps
    }

}

private extension OnboardingPixelParameter.Source {

    init(_ source: OnboardingSource) {
        switch source {
        case .default:
            self = .default
        case .duckAICPP:
            self = .duckAICustomProductPage
        }
    }

}

private extension OnboardingPixelParameter.Flow {

    init(_ flow: OnboardingFlowType) {
        switch flow {
        case .default:
            self = .default
        case .duckAI:
            self = .duckAI
        }
    }
}
