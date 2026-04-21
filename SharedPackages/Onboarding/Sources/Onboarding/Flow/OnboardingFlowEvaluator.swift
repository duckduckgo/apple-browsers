//
//  OnboardingFlowEvaluator.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Foundation

/// Evaluates which onboarding flow to present based on the app's launch context.
///
/// The evaluator determines the appropriate `OnboardingFlowType` by inspecting
/// deep link URLs. This allows the app to deliver tailored onboarding experiences based on how the user installed the app.
public protocol OnboardingFlowEvaluating {

    /// Evaluates and returns the appropriate onboarding flow type based on the provided URL.
    ///
    /// This method inspects the deep link URL (if provided) to determine which onboarding
    /// experience should be shown. If the URL is `nil` or cannot be mapped to a specific
    /// flow, it defaults to `.default`.
    ///
    /// - Parameter url: The deep link URL from app launch, or `nil` for normal app icon launches.
    ///                  Expected format: `<scheme>://<identifier>` (e.g., `ddgCPP://duck-ai`)
    ///
    /// - Returns: The determined `OnboardingFlowType`. Defaults to `.default` if URL is `nil`, unrecognised or has an invalid format.
    func evaluateOnboardingFlow(from url: URL?) -> OnboardingFlowType
}

public struct OnboardingFlowEvaluator: OnboardingFlowEvaluating {
    public static let customProductPageScheme = "ddgCPP"

    private let customProductPageScheme: String

    public init(customProductPageScheme: String = OnboardingFlowEvaluator.customProductPageScheme) {
        self.customProductPageScheme = customProductPageScheme
    }

    public func evaluateOnboardingFlow(from url: URL?) -> OnboardingFlowType {
        Logger.onboarding.debug("Evaluating onboarding flow for url: \(url?.absoluteString ?? "nil", privacy: .public)")

        guard let url else {
            Logger.onboarding.debug("No URL Provided. Default to standard onboarding.")
            return .default
        }

        guard
            url.scheme == customProductPageScheme,
            let identifier = url.host
        else {
            Logger.onboarding.debug("URL provided is not a Custom Product Page URL. Default to standard onboarding.")
            return .default
        }

        guard let onboardingType = OnboardingFlowType(rawValue: identifier) else {
            Logger.onboarding.debug("Identifier \(identifier, privacy: .public) provided for Custom Product Page is not currently supported. Default to standard onboarding.")
            return .default
        }

        Logger.onboarding.debug("Evaluated tailored onboarding type: \(onboardingType.rawValue, privacy: .public)")
        return onboardingType
    }

}
