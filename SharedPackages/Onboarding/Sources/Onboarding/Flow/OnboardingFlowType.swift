//
//  OnboardingFlowType.swift
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

/// Represents the different onboarding flow variations that can be presented to users.
///
/// The onboarding flow type determines which steps, content, and UI are shown during
/// the initial user onboarding experience. Different flows can be triggered based on
/// the user's acquisition context (e.g., App Store Custom Product Page, marketing campaign).
public enum OnboardingFlowType: String, Equatable {

    /// The default onboarding experience shown to users who install the app
    /// through standard channels (e.g., direct App Store download).
    case `default`

    /// A Duck.ai-focused onboarding experience for users who install the app
    /// via a Duck.ai Custom Product Page.
    ///
    /// This flow emphasises AI features and is tailored for users who downloaded the app specifically for Duck.ai capabilities.
    case duckAI
}
