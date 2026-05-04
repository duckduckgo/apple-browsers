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

typealias OnboardingManaging = OnboardingStepsProvider

final class OnboardingManager {
    private var appDefaults: OnboardingDebugAppSettings
    private let variantManager: VariantManager
    private let isIphone: Bool

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
        variantManager: VariantManager = DefaultVariantManager(),
        isIphone: Bool = UIDevice.current.userInterfaceIdiom == .phone
    ) {
        self.appDefaults = appDefaults
        self.variantManager = variantManager
        self.isIphone = isIphone
    }

    func newUserSteps(isIphone: Bool) -> [OnboardingIntroStep] {
        let introStep = OnboardingIntroStep.introDialog(isReturningUser: false)
        return [introStep] + steps(isIphone: isIphone)
    }

    func returningUserSteps(isIphone: Bool) -> [OnboardingIntroStep] {
        let introStep = OnboardingIntroStep.introDialog(isReturningUser: true)
        return [introStep] + steps(isIphone: isIphone)
    }

    private func steps(isIphone: Bool) -> [OnboardingIntroStep] {
        isIphone ? iPhoneFlow : iPadFlow
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
        if isNewUser {
            newUserSteps(isIphone: isIphone)
        } else {
            returningUserSteps(isIphone: isIphone)
        }
    }

    var userHasSeenAddToDockPromoDuringOnboarding: Bool {
        onboardingSteps.contains(.addToDockPromo)
    }

}
