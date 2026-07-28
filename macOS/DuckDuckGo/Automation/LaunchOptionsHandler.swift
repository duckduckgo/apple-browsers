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
import FoundationExtensions

/// Handles launch options and user defaults for automation and testing scenarios
public final class LaunchOptionsHandler {
    public static let isOnboardingCompleted = "isOnboardingCompleted"
    private static let automationPortKey = "automationPort"
    private static let isInternalUserKey = "isInternalUser"
    private static let webViewProxyKey = "webViewProxy"
    private static let acceptInsecureCertsKey = "acceptInsecureCerts"
    private let userDefaults: UserDefaults
    private let applicationBuildType: ApplicationBuildType
    private let environment: [String: String]

    public init(
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        self.applicationBuildType = StandardApplicationBuildType()
        self.environment = ProcessInfo.processInfo.environment
    }

    init(
        userDefaults: UserDefaults,
        applicationBuildType: ApplicationBuildType,
        environment: [String: String]
    ) {
        self.userDefaults = userDefaults
        self.applicationBuildType = applicationBuildType
        self.environment = environment
    }

    public var isInternalUserRequested: Bool {
        userDefaults.string(forKey: Self.isInternalUserKey)?.lowercased() == "true"
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
        guard isDebugOrReviewBuild else { return false }
        return AutomationSession.isWebDriverActive(automationPort: automationPort)
    }

    var webViewProxy: WebViewProxy? {
        guard isAuthenticatedWebDriverAutomationSession,
              let value = argumentDomain[Self.webViewProxyKey] as? String else {
            return nil
        }
        return WebViewProxy(value)
    }

    var acceptsInsecureCertificates: Bool {
        guard isAuthenticatedWebDriverAutomationSession,
              webViewProxy != nil else {
            return false
        }
        return argumentBoolean(forKey: Self.acceptInsecureCertsKey)
    }

    /// Returns true if the app is running in any automation mode (WebDriver or UI Tests)
    public var isAutomationSession: Bool {
        guard isDebugOrReviewBuild else { return isUITesting }
        return isWebDriverAutomationSession || isUITesting
    }

    public var onboardingStatus: OnboardingStatus {
        guard isDebugOrReviewBuild else { return .notOverridden }

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

    private var isDebugOrReviewBuild: Bool {
        applicationBuildType.isDebugBuild || applicationBuildType.isReviewBuild
    }

    private var isAuthenticatedWebDriverAutomationSession: Bool {
        guard isWebDriverAutomationSession else { return false }
        return environment["AUTOMATION_TOKEN"]?.isEmpty == false
    }

    private var argumentDomain: [String: Any] {
        userDefaults.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    private func argumentBoolean(forKey key: String) -> Bool {
        switch argumentDomain[key] {
        case let value as Bool:
            return value
        case let value as String:
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return false
        }
    }
}

struct WebViewProxy: Equatable {
    let host: String
    let port: UInt16

    init?(_ value: String) {
        guard let components = URLComponents(string: value),
              components.scheme == "socks5",
              components.user == nil,
              components.password == nil,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              let host = components.host.map(Self.normalizedHost),
              ["127.0.0.1", "::1"].contains(host),
              let portValue = components.port,
              let port = UInt16(exactly: portValue),
              port > 0 else {
            return nil
        }
        self.host = host
        self.port = port
    }

    private static func normalizedHost(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]") else {
            return host
        }
        return String(host.dropFirst().dropLast())
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
