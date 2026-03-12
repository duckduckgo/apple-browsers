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
    public static let isOnboardingCompleted = "isOnboardingCompleted"
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

    /// Returns true only when WebDriver automation is active.
    public var isWebDriverAutomationSession: Bool {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild else { return false }
        return AutomationSession.isWebDriverActive(automationPort: automationPort)
    }

    /// Returns true if the app is running in any automation mode (WebDriver or UI Tests)
    public var isAutomationSession: Bool {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild else { return isUITesting }
        return isWebDriverAutomationSession || isUITesting
    }

    public var onboardingStatus: OnboardingStatus {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild else { return .notOverridden }

        // Override onboarding settings permanently to keep state consistency across app launches.
        // This applies to both UI Tests and WebDriver automation sessions.
        // Launch Arguments can be read via userDefaults for easy value access.
        if let uiTestingOnboardingOverride = userDefaults.string(forKey: Self.isOnboardingCompleted) {
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
    }

}
