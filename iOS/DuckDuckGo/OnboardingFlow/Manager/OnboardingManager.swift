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

protocol OnboardingFlowManaging {
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
        sharedPixelsStorage: (any KeyedStoring<OnboardingSharedPixelsKeys>)? = nil
    ) {
        self.appDefaults = appDefaults
        self.featureFlagger = featureFlagger
        self.variantManager = variantManager
        self.isIphone = isIphone
        self.onboardingFlowEvaluator = onboardingFlowEvaluator
        self.tutorialSettings = tutorialSettings
        self.sharedPixelsStorage = if let sharedPixelsStorage { sharedPixelsStorage } else { UserDefaults.app.keyedStoring() }
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

enum OnboardingIntroStep: Equatable {
    case introDialog(isReturningUser: Bool)
    case browserComparison
    case appIconSelection
    case addToDockPromo
    case addressBarPositionSelection
    case searchExperienceSelection
    case duckAIQueryExperimentSelection
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
        default:
            resolvedFlow = evaluatedOnboarding.flow
        }

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
            return [introStep] + steps(isIphone: isIphone)
        case .duckAI:
            // Temporarily return steps for default flow
            return [introStep] + steps(isIphone: isIphone)
        }
    }

    func steps(isIphone: Bool) -> [OnboardingIntroStep] {
        isIphone ? iPhoneFlow : iPadFlow
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
