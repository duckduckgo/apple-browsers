//
//  AppVersion.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

public protocol OSVersionProviding {

    var osVersionMajorMinorPatch: String { get }

}

public struct AppVersion: OSVersionProviding {

    public static let shared = AppVersion()

    private let bundle: InfoBundle

    public init(bundle: InfoBundle = Bundle.main) {
        self.bundle = bundle
    }

    public var name: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.name) as? String ?? ""
    }

    public var productName: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.executableName) as? String ?? ""
    }

    public var identifier: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.identifier) as? String ?? ""
    }

    public var majorVersionNumber: String {
        return String(versionNumber.split(separator: ".").first ?? "")
    }

    public var versionNumber: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.versionNumber) as? String ?? ""
    }

    public var buildNumber: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.buildNumber) as? String ?? ""
    }

    public var alphaBuildSuffix: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.alphaBuildSuffix) as? String ?? ""
    }

    public var commitSHA: String {
        return bundle.object(forInfoDictionaryKey: Bundle.Key.commitSHA) as? String ?? ""
    }

    public var commitSHAShort: String {
        return String(commitSHA.prefix(7))
    }

    public var versionAndBuildNumber: String {
        let baseVersion = "\(versionNumber).\(buildNumber)"
        let suffix = alphaBuildSuffix
        return suffix.isEmpty ? baseVersion : "\(baseVersion)-\(suffix)"
    }

    public var localized: String {
        return "\(name) \(versionAndBuildNumber)"
    }

    public var osVersionMajorMinorPatch: String {
        let os = ProcessInfo().operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }

    public var osVersionMajorMinor: String {
        let os = ProcessInfo().operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion)"
    }

    public enum AppRunType: String {
        case normal
        case unitTests
        case integrationTests
        case uiTests
        case uiTestsOnboarding
        case uiTestsStartupPerformance
        case xcPreviews

        /// Whether the Sparkle Updater should be allowed or not.
        public var allowsUpdates: Bool {
            switch self {
            case .normal, .integrationTests, .unitTests, .uiTestsOnboarding, .xcPreviews:
                return true
            case .uiTests, .uiTestsStartupPerformance:
                return false
            }
        }

        /// Whether Onboarding is allowed or not.
        public var allowsOnboarding: Bool {
            switch self {
            case .normal, .integrationTests, .unitTests, .uiTestsOnboarding, .xcPreviews:
                return true
            case .uiTests, .uiTestsStartupPerformance:
                return false
            }
        }

        /// Whether the app should open a fallback window on launch when no window was restored or opened by a URL event.
        public var opensWindowOnStartupIfNeeded: Bool {
            switch self {
            case .normal, .uiTestsStartupPerformance:
                return true
            case .integrationTests, .unitTests, .uiTests, .uiTestsOnboarding, .xcPreviews:
                return false
            }
        }

        /// Defines if app run type requires loading full environment, i.e. databases, saved state, keychain etc.
        public var requiresEnvironment: Bool {
            switch self {
            case .normal, .integrationTests, .uiTests, .uiTestsOnboarding, .uiTestsStartupPerformance:
                return true
            case .unitTests, .xcPreviews:
                return false
            }
        }

        /// Whether the app should attempt to restore windows and tabs from the previous session on launch.
        public var stateRestorationAllowed: Bool {
            switch self {
            case .normal, .uiTests, .uiTestsStartupPerformance:
                return true
            case .integrationTests, .unitTests, .uiTestsOnboarding, .xcPreviews:
                return false
            }
        }
    }

    public static let runType: AppRunType = {
        let isCI = !(ProcessInfo.processInfo.environment["CI"]?.isEmpty ?? true)

        if let testBundlePath = ProcessInfo().environment["XCTestBundlePath"] {
            if testBundlePath.contains("Unit") {
                return .unitTests
            } else if testBundlePath.contains("Integration") || testBundlePath.contains("DBPE2ETests") {
                return .integrationTests
            } else {
                return .uiTests
            }
        } else if ProcessInfo().environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .xcPreviews
        } else if ProcessInfo.processInfo.environment["UITEST_MODE_ONBOARDING"] == "1" {
            return .uiTestsOnboarding
        } else if ProcessInfo.processInfo.environment["UITEST_MODE_STARTUP_PERFORMANCE"] == "1" {
            return .uiTestsStartupPerformance
        } else if ProcessInfo.processInfo.environment["UITEST_MODE"] == "1" || isCI {
            return .uiTests
        } else {
            return .normal
        }
    }()

    public var runType: AppRunType { Self.runType }

    /// Returns true if this is an App Store build.
    /// Returns false for DMG/Sparkle builds.
    ///
    /// This check works across all targets including VPN agents and system extensions
    /// by examining the bundle identifier prefix.
    public static var isAppStoreBuild: Bool = {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        return bundleId.hasPrefix("com.duckduckgo.mobile.ios")
    }()

}
