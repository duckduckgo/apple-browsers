//
//  LaunchOptionsHandler.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Common

/// Handles launch options and user defaults for automation and testing scenarios
public final class LaunchOptionsHandler {

    /// Launch argument key used by UI tests to override onboarding completion state.
    private static let onboardingOverrideCompletedKey = "isOnboardingCompleted"

    private static let automationPortKey = "automationPort"
    private let userDefaults: UserDefaults

    public init(
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
    }

    /// Returns the automation port if set, nil otherwise.
    /// The automation server will listen on this port when launched.
    /// Port must be in the valid UInt16 range (1-65535).
    public var automationPort: Int? {
        let port = userDefaults.integer(forKey: Self.automationPortKey)
        guard UInt16(exactly: port) != nil, port > 0 else { return nil }
        return port
    }

    /// Returns true if the app is running in UI testing mode
    private var isUITesting: Bool {
        [.uiTests, .uiTestsOnboarding].contains(AppVersion.runType)
    }

    /// Returns true if the app is running in any automation mode (WebDriver or UI Tests)
    public var isAutomationSession: Bool {
        automationPort != nil || isUITesting
    }

    public var onboardingStatus: OnboardingStatus {
        // If we're running UI Tests override onboarding settings permanently to keep state consistency across app launches. Some test re-launch the app within the same tests.
        // Launch Arguments can be read via userDefaults for easy value access.
        if isUITesting,
           let uiTestingOnboardingOverride = userDefaults.string(forKey: Self.onboardingOverrideCompletedKey) {
            return .overridden(.uiTests(completed: uiTestingOnboardingOverride == "true"))
        }

        // If developer override via Scheme Environment variable temporarily it means we want to show the onboarding.
        if let developerOnboardingOverride = ProcessInfo.processInfo.environment["ONBOARDING"] {
            return .overridden(.developer(completed: developerOnboardingOverride == "false"))
        }

        return .notOverridden
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
