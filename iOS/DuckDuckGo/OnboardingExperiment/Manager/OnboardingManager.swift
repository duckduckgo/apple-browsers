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

enum OnboardingAddToDockState: String, Equatable, CaseIterable, CustomStringConvertible {
    case disabled
    case intro
    case contextual

    var description: String {
        switch self {
        case .disabled:
            "Disabled"
        case .intro:
            "Onboarding Intro"
        case .contextual:
            "Dax Dialogs"
        }
    }
}

typealias OnboardingIntroExperimentManaging = OnboardingSetAsDefaultExperimentManaging
typealias OnboardingManaging = OnboardingSettingsURLProvider & OnboardingIntroExperimentManaging

final class OnboardingManager {
    private let featureFlagger: FeatureFlagger
    private let variantManager: VariantManager
    private let isIphone: Bool

    private var isNewUser: Bool {
#if DEBUG || ALPHA
        // If debug or alpha build enable testing the experiment with cohort override.
        // If running unit tests do not override behaviour.
        if ProcessInfo().arguments.contains("testing") {
            variantManager.currentVariant?.name != VariantIOS.returningUser.name
        } else {
            true
        }
#else
        variantManager.currentVariant?.name != VariantIOS.returningUser.name
#endif
    }

    init(
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        variantManager: VariantManager = DefaultVariantManager(),
        isIphone: Bool = UIDevice.current.userInterfaceIdiom == .phone
    ) {
        self.featureFlagger = featureFlagger
        self.variantManager = variantManager
        self.isIphone = isIphone
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
