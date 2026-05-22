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

typealias OnboardingManaging = OnboardingStepsProvider & OnboardingAddToDockVisibilityManager & OnboardingFlowManaging

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
        .browserComparison,
        .addToDockPromo,
        .appIconSelection,
        .addressBarPositionSelection,
        .searchExperienceSelection
    ]
    private let iPadFlow: [OnboardingIntroStep] = [.browserComparison, .appIconSelection]

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

// Ergonomic factories so call sites can write `.browserComparison` instead of `.renderable(.browserComparison)`.
// Mirror every new `RenderableStep` case here.
extension OnboardingIntroStep {
    static let browserComparison: Self = .renderable(.browserComparison)
    static let aiComparison: Self = .renderable(.aiComparison)
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
        case browserComparison
        case aiComparison
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
        case .renderable(.browserComparison): return .browserComparison
        case .renderable(.aiComparison): return .aiComparison
        case .renderable(.addToDockPromo): return .addToDockPromo
        case .renderable(.appIconSelection): return .appIconSelection
        case .renderable(.addressBarPositionSelection): return .addressBarPositionSelection
        case .renderable(.searchExperienceSelection): return .searchExperienceSelection
        case .renderable(.duckAIQuerySelection): return .duckAIQuerySelection
        case .interlude(.duckAI): return .interludeDuckAI
        }
    }
}

/// Persisted checkpoint allowing the onboarding flow to resume after an app relaunch.
enum OnboardingResumeStep: String {
    case browserComparison
    case aiComparison
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

extension OnboardingManager: OnboardingStepsProvider {

    var onboardingSteps: [OnboardingIntroStep] {
        stepsForCurrentFlow()
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

        // Clear any stale resume checkpoint persisted before the flow was configured
        // (e.g. by a previous build that didn't set onboardingFlowType), so we don't
        // resume into a step that appears at a different point of the flow causing the user to skip important steps.
        OnboardingResumeCheckpointStore.clearAll(in: onboardingResumeStepStore)

        tutorialSettings.onboardingFlowType = resolvedFlow
        persistOnboardingPixelContext(flow: resolvedFlow, source: evaluatedOnboarding.source)
    }

}

// MARK: - Private

private extension OnboardingManager {

    /// Persist the flow and source for onboarding pixels based on the evaluated context.
    /// This must be called before onboarding is presented.
    func persistOnboardingPixelContext(flow: OnboardingFlowType, source: OnboardingSource) {
        sharedPixelsStorage.onboardingFlow = OnboardingPixelParameter.Flow(flow)
        sharedPixelsStorage.onboardingSource = OnboardingPixelParameter.Source(source)
    }

    func stepsForCurrentFlow() -> [OnboardingIntroStep] {
        let introStep = OnboardingIntroStep.introDialog(isReturningUser: !isNewUser)
        switch tutorialSettings.onboardingFlowType {
        case .none, .default:
            return [introStep] + defaultFlowSteps(isIphone: isIphone)
        case .duckAI:
            return [introStep] + duckAITailoredFlowSteps()
        }
    }

    func defaultFlowSteps(isIphone: Bool) -> [OnboardingIntroStep] {
        isIphone ? iPhoneFlow : iPadFlow
    }

    func duckAITailoredFlowSteps() -> [OnboardingIntroStep] {
        [.aiComparison, .duckAIQuerySelection, .interlude(.duckAI), .addToDockPromo, .browserComparison, .addressBarPositionSelection]
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
