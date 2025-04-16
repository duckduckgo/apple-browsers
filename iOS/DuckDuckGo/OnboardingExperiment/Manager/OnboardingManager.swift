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

import BrowserServicesKit
import Core

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

typealias OnboardingIntroExperimentManaging = OnboardingSetAsDefaultExperimentManaging
typealias OnboardingManaging = OnboardingSettingsURLProvider & OnboardingStepsProvider & OnboardingIntroExperimentManaging

final class OnboardingManager {
    private var appDefaults: OnboardingDebugAppSettings
    private let featureFlagger: FeatureFlagger
    private let variantManager: VariantManager
    private let isIphone: Bool

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
        isIphone: Bool = UIDevice.current.userInterfaceIdiom == .phone
    ) {
        self.appDefaults = appDefaults
        self.featureFlagger = featureFlagger
        self.variantManager = variantManager
        self.isIphone = isIphone
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

// MARK: - Settings URL Provider

protocol OnboardingSettingsURLProvider: AnyObject {
    var settingsURLPath: String { get }
}

extension OnboardingSettingsURLProvider {

    var settingsURLPath: String {
        UIApplication.openSettingsURLString
    }

}

extension OnboardingManager: OnboardingSettingsURLProvider {}


// MARK: - Onboarding Steps Provider

enum OnboardingIntroStep: Equatable {
    case introDialog(isReturningUser: Bool)
    case browserComparison
    case appIconSelection
    case addressBarPositionSelection
    case addToDockPromo

    private static let iPhoneFlow: [OnboardingIntroStep] = [.browserComparison, .addToDockPromo, .appIconSelection, .addressBarPositionSelection]
    private static let iPadFlow: [OnboardingIntroStep] = [.browserComparison, .appIconSelection]

    static func newUserSteps(isIphone: Bool) -> [OnboardingIntroStep] {
        let introStep = OnboardingIntroStep.introDialog(isReturningUser: false)
        return [introStep] + steps(isIphone: isIphone)
    }

    static func returningUserSteps(isIphone: Bool) -> [OnboardingIntroStep] {
        let introStep = OnboardingIntroStep.introDialog(isReturningUser: true)
        return [introStep] + steps(isIphone: isIphone)
    }

    private static func steps(isIphone: Bool) -> [OnboardingIntroStep] {
        isIphone ? iPhoneFlow : iPadFlow
    }
}

protocol OnboardingStepsProvider: AnyObject {
    var onboardingSteps: [OnboardingIntroStep] { get }
}

extension OnboardingManager: OnboardingStepsProvider {

    var onboardingSteps: [OnboardingIntroStep] {
        isNewUser ? OnboardingIntroStep.newUserSteps(isIphone: isIphone) : OnboardingIntroStep.returningUserSteps(isIphone: isIphone)
    }

    var userHasSeenAddToDockPromoDuringOnboarding: Bool {
        onboardingSteps.contains(.addToDockPromo)
    }

}

// MARK: - Set Default Browser Experiment

protocol OnboardingSetAsDefaultExperimentManaging: AnyObject {
    var isEnrolledInSetAsDefaultBrowserExperiment: Bool { get }
    func resolveSetAsDefaultBrowserExperimentCohort() -> OnboardingSetAsDefaultBrowserCohort?
}

extension OnboardingManager: OnboardingSetAsDefaultExperimentManaging {

    var isEnrolledInSetAsDefaultBrowserExperiment: Bool {
        resolveSetAsDefaultBrowserExperimentCohort() != nil
    }

    func resolveSetAsDefaultBrowserExperimentCohort() -> OnboardingSetAsDefaultBrowserCohort? {
        // The experiment runs only for users on iOS 18.3+ and for non returning users
        guard #available(iOS 18.3, *), isNewUser else { return nil }

        return featureFlagger.resolveCohort(for: FeatureFlag.onboardingSetAsDefaultBrowser) as? OnboardingSetAsDefaultBrowserCohort
    }

}

// MARK: - Settings URL Provider + Set As Default Browser Experiment

extension OnboardingSettingsURLProvider where Self: OnboardingSetAsDefaultExperimentManaging {

    // If running iOS 18.3 check if the user should be enrolled in the SetAsDefaultBrowser experiment.
    // If the user is enrolled in the control group or SetAsDefaultBrowser is not running, deep link to DDG custom settings in the Settings app.
    // If the user is enrolled in the treatment group, deep link to the Settings app for default app selection.
    var settingsURLPath: String {
        if #available(iOS 18.3, *) {
            switch resolveSetAsDefaultBrowserExperimentCohort() {
            case .none:
                Logger.onboarding.debug("SetAsDefaultBrowser experiment not running")
                return UIApplication.openSettingsURLString
            case .control:
                Logger.onboarding.debug("User enrolled in the control group of the SetAsDefaultBrowser experiment")
                return UIApplication.openSettingsURLString
            case .treatment:
                Logger.onboarding.debug("User enrolled in the treatment group of the SetAsDefaultBrowser experiment")
                return UIApplication.openDefaultApplicationsSettingsURLString
            }
        } else {
            Logger.onboarding.debug("User running an iOS version lower than iOS 18.3. Returning DDG’s custom settings url in the Settings app.")
            return UIApplication.openSettingsURLString
        }
    }

}
