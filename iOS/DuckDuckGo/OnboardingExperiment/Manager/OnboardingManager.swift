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
