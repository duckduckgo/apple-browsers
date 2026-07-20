//
//  TutorialSettings.swift
//  DuckDuckGo
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
import Core
import Onboarding

protocol TutorialSettings: AnyObject {

    var lastVersionSeen: Int { get }
    var hasSeenOnboarding: Bool { get set }
    var hasSkippedOnboarding: Bool { get set }

    /// The configured onboarding flow type for the current user.
    ///
    /// This property is optional to distinguish between three states:
    /// - `nil`: Flow has not yet been determined (first launch, before configuration)
    /// - `.default`: Flow has been explicitly set to default onboarding
    /// - `.duckAI`: Flow has been explicitly set to Duck.ai tailored onboarding
    ///
    /// Once set, this value persists and should not change, even if the app is reopened
    /// with a different launch context. This prevents flow switching mid-onboarding.
    var onboardingFlowType: OnboardingFlowType? { get set }

    /// The download reason the user selected on the Download Screen, or `nil` if not yet chosen.
    ///
    /// Persisted alongside ``onboardingFlowType`` so the tailored default flow can be
    /// reconstructed when onboarding resumes after an app relaunch. Remains `nil` for flows
    /// that don't show the Download Screen (e.g. the Duck.ai Custom Product Page flow).
    var onboardingDownloadReason: OnboardingDownloadReason? { get set }

}

final class DefaultTutorialSettings: TutorialSettings {

    private struct Constants {
        // Set the build number of the last build that didn't force them to appear to force them to appear.
        static let onboardingVersion = 1
    }

    private struct Keys {
        static let lastVersionSeen = "com.duckduckgo.tutorials.lastVersionSeen"
        static let hasSeenOnboarding = "com.duckduckgo.tutorials.hasSeenOnboarding"
        static let hasSkippedOnboarding = "com.duckduckgo.tutorials.hasSkippedOnboarding"
        static let onboardingFlowType = "com.duckduckgo.tutorials.onboardingFlowType"
        static let onboardingDownloadReason = "com.duckduckgo.tutorials.onboardingDownloadReason"
    }

    private func userDefaults() -> UserDefaults {
        return UserDefaults.app
    }

    public var lastVersionSeen: Int {
        return userDefaults().integer(forKey: Keys.lastVersionSeen)
    }

    public var hasSeenOnboarding: Bool {
        get {
            if Constants.onboardingVersion > lastVersionSeen {
                return false
            }
            return userDefaults().bool(forKey: Keys.hasSeenOnboarding, defaultValue: false)
        }
        set(newValue) {
            userDefaults().set(Constants.onboardingVersion, forKey: Keys.lastVersionSeen)
            userDefaults().set(newValue, forKey: Keys.hasSeenOnboarding)
        }
    }

    public var hasSkippedOnboarding: Bool {
        get {
            userDefaults().bool(forKey: Keys.hasSkippedOnboarding, defaultValue: false)
        }
        set {
            userDefaults().set(newValue, forKey: Keys.hasSkippedOnboarding)
        }
    }

    public var onboardingFlowType: OnboardingFlowType? {
        get {
            guard let rawValue = userDefaults().string(forKey: Keys.onboardingFlowType) else {
                return nil
            }
            return OnboardingFlowType(rawValue: rawValue)
        }
        set {
            userDefaults().set(newValue?.rawValue, forKey: Keys.onboardingFlowType)
        }
    }

    public var onboardingDownloadReason: OnboardingDownloadReason? {
        get {
            guard let rawValue = userDefaults().string(forKey: Keys.onboardingDownloadReason) else {
                return nil
            }
            return OnboardingDownloadReason(rawValue: rawValue)
        }
        set {
            userDefaults().set(newValue?.rawValue, forKey: Keys.onboardingDownloadReason)
        }
    }

}
