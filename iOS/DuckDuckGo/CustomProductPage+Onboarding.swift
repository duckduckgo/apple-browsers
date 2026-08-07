//
//  CustomProductPage+Onboarding.swift
//  DuckDuckGo
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
import Onboarding

/// Extends `AppStoreCustomProductPageEvaluator` to provide onboarding flow evaluation.
extension AppStoreCustomProductPageEvaluator: OnboardingFlowEvaluating {

    /// Evaluates a URL and returns the corresponding onboarding flow and source.
    ///
    /// If the URL represents a recognised Custom Product Page, returns the tailored onboarding flow and source for that page.
    /// Otherwise, returns the `.default` onboarding flow and source.
    /// - Parameter url: The URL to evaluate (typically from app launch via CPP deep link)
    /// - Returns: A tuple containing `OnboardingFlowType` and `OnboardingSource`
    func evaluateOnboardingFlow(from url: URL?) -> (flow: OnboardingFlowType, source: OnboardingSource) {
        Logger.onboarding.debug("Evaluating onboarding flow for url: \(url?.shortDescription ?? "nil")")

        guard let url else {
            Logger.onboarding.debug("No URL Provided. Default to standard onboarding.")
            return (.default, .default)
        }

        guard let cpp = evaluateCustomProductPage(from: url) else {
            Logger.onboarding.debug("Unsupported Custom Product Page URL. Default to standard onboarding")
            return (.default, .default)
        }

        let onboardingType = OnboardingFlowType(cpp)
        let onboardingSource = OnboardingSource(cpp)
        Logger.onboarding.debug("Evaluated tailored onboarding type: \(onboardingType.rawValue, privacy: .public)")

        return (onboardingType, onboardingSource)
    }

}

// MARK: - Helpers

private extension OnboardingFlowType {

    init(_ value: AppStoreCustomProductPage) {
        switch value {
        case .duckAI:
            self = .duckAI
        }
    }

}

private extension OnboardingSource {

    init(_ value: AppStoreCustomProductPage) {
        switch value {
        case .duckAI:
            self = .duckAICPP
        }
    }

}
