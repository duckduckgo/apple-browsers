//
//  OnboardingConfiguration.swift
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

import Foundation

/// Configuration needed to set up the FE onboarding
struct OnboardingConfiguration: Codable, Equatable {
    var stepDefinitions: StepDefinitions
    var exclude: [String]
    var steps: [String]
    var order: String
    var env: String
    var locale: String
    /// The OS region as an ISO 3166-1 alpha-2 code; the top sites picker uses it for regional site URLs
    var region: String?
    var platform: OnboardingPlatform
}

/// Defines the onboarding steps desired
struct StepDefinitions: Codable, Equatable {
    var systemSettings: SystemSettings
    var getStarted: GetStarted
}

struct GetStarted: Codable, Equatable {
    var options: [String]
}

struct SystemSettings: Codable, Equatable {
    var rows: [String]
}

struct OnboardingPlatform: Codable, Equatable {
    var name: String
}

struct OnboardingImportResponse: Codable, Equatable {
    var enabled: Bool
}

/// Answer to the page's `shouldShowTopSitesPicker` request, sent right before the user would reach the step
struct TopSitesPickerAnswer: Encodable, Equatable {
    let show: Bool
    /// URLs of the user's favorites, which the page shows as picked and locked
    let existingFavorites: [String]?
}
