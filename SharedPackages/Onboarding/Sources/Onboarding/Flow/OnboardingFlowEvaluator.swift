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
public protocol OnboardingFlowEvaluating {

    /// Evaluates and returns the appropriate onboarding flow type based on the provided URL.
    ///
    /// - Parameter url: The deep link URL from app launch, or `nil` for normal app icon launches.
    ///                  Expected format: `<scheme>://<identifier>` (e.g., `ddgCPP://duck-ai`)
    ///
    /// - Returns: The determined `OnboardingFlowType`. Defaults to `.default` if URL is `nil`, unrecognised or has an invalid format.
    func evaluateOnboardingFlow(from url: URL?) -> OnboardingFlowType
}
