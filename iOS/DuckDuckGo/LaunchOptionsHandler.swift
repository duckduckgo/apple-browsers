//
//  LaunchOptionsHandler.swift
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

import Foundation

public final class LaunchOptionsHandler {
    private static let isOnboardingCompleted = "isOnboardingCompleted"
    private static let appVariantName = "currentAppVariant"

    private let launchArguments: [String]
    private let environment: [String: String]
    private let userDefaults: UserDefaults

    public init(launchArguments: [String] = ProcessInfo.processInfo.arguments, environment: [String: String] =  ProcessInfo.processInfo.environment, userDefaults: UserDefaults = .app) {
        self.launchArguments = launchArguments
        self.environment = environment
        self.userDefaults = userDefaults
    }

    public var onboardingStatus: OnboardingStatus {
        // Launch Arguments can be read via userDefaults for easy value access.
        switch (environment["ONBOARDING"], userDefaults.string(forKey: Self.isOnboardingCompleted)) {
        // No Environment Variables or Launch Arguments override the onboarding
        case (.none, .none):
            return .notOverridden
        // Launch Argument override onboarding. This happens from UITest Maestro workflow.
        case (.none, .some(let argumentValue)):
            return .overridden(completed: argumentValue == "true")
        // Launch Environment override onboarding. Developer can override this setting in the App scheme to show onboarding when working on the feature
        case (.some(let environmentValue), .none):
            return .overridden(completed: environmentValue == "false")
        // We need to handle this case
        case (.some(let environmentValue), .some(let argumentValue)):
            return .overridden(completed: environmentValue == "false" || argumentValue == "true")
        }
    }

    public var appVariantName: String? {
        sanitisedEnvParameter(string: userDefaults.string(forKey: Self.appVariantName))
    }

    private func sanitisedEnvParameter(string: String?) -> String? {
        guard let string, string != "null" else { return nil }
        return string
    }
}

// MARK: - LaunchOptionsHandler + VariantManager

extension LaunchOptionsHandler: VariantNameOverriding {

    public var overriddenAppVariantName: String? {
        return appVariantName
    }

}


// MARK: - LaunchOptionsHandler + Onboarding

extension LaunchOptionsHandler {
    public enum OnboardingStatus: Equatable {
        case notOverridden
        case overridden(completed: Bool)
    }
}
