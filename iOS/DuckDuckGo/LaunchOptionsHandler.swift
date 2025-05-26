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
import enum Common.DevicePlatform

public final class LaunchOptionsHandler {

    // Used by debug controller
    public static let isOnboardingCompleted = "isOnboardingCompleted"

    private static let appVariantName = "currentAppVariant"
    private static let automationPort = "automationPort"

    private let environment: [String: String]
    private let userDefaults: UserDefaults

    private let isIpad: Bool
    private let systemVersion: String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .app,
        isIpad: Bool = DevicePlatform.isIpad,
        systemVersion: String = UIDevice.current.systemVersion
    ) {
        self.environment = environment
        self.userDefaults = userDefaults
        self.isIpad = isIpad
        self.systemVersion = systemVersion
    }

    public var onboardingStatus: OnboardingStatus {
        // Apple Issue affecting persistence storage on iPad 17.7.7
        // See: https://app.asana.com/1/137249556945/project/414709148257752/task/1210267814606214
        if isIpad && systemVersion == "17.7.7" {
            return .overridden(.developer(completed: true))
        }

        // If we're running UI Tests override onboarding settings permanently to keep state consistency across app launches. Some test re-launch the app within the same tests.
        // Launch Arguments can be read via userDefaults for easy value access.
        if let uiTestingOnboardingOverride = userDefaults.string(forKey: Self.isOnboardingCompleted) {
            return .overridden(.uiTests(completed: uiTestingOnboardingOverride == "true"))
        }

        // If developer override via Scheme Environment variable temporarily it means we want to show the onboarding.
        if let developerOnboardingOverride = environment["ONBOARDING"] {
            return .overridden(.developer(completed: developerOnboardingOverride == "false"))
        }

        return .notOverridden
    }

    public var automationPort: Int? {
        userDefaults.integer(forKey: Self.automationPort)
    }

#if DEBUG || ALPHA
    public func overrideOnboardingCompleted() {
        userDefaults.set("true", forKey: Self.isOnboardingCompleted)
    }
#endif

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
        case overridden(OverrideType)

        public enum OverrideType: Equatable {
            case developer(completed: Bool)
            case uiTests(completed: Bool)
        }

        public var isOverriddenCompleted: Bool {
            switch self {
            case .notOverridden:
                return false
            case .overridden(.developer(let completed)):
                return completed
            case .overridden(.uiTests(let completed)):
                return completed
            }
        }
    }

}
