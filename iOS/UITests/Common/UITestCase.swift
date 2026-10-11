//
//  UITestCase.swift
//  DuckDuckGo
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

import XCTest

class UITestCase: XCTestCase {

    private enum ConfigurationError: LocalizedError {
        case invalidInternalUserMode(String)

        var errorDescription: String? {
            switch self {
            case .invalidInternalUserMode(let value):
                return "INTERNAL_USER_MODE must be either 'true' or 'false'; received '\(value)'."
            }
        }
    }

    let app = XCUIApplication()

    var additionalLaunchArguments: [String] {
        []
    }

    var additionalLaunchEnvironment: [String: String] {
        [:]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        try configureAppLaunch(clearingState: true)
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try super.tearDownWithError()
    }

    /// Relaunches without resetting defaults so tests can exercise multi-launch flows.
    /// Internal-user mode and subclass launch arguments/environment are applied on every launch.
    func relaunchAppPreservingState() throws {
        app.terminate()
        try configureAppLaunch(clearingState: false)
        app.launch()
    }

    private func configureAppLaunch(clearingState: Bool) throws {
        var launchArguments: [String] = []
        if clearingState {
            launchArguments += ["-clearAllDefaults"]
        }
        launchArguments += [
            "isRunningUITests",
            "-isOnboardingCompleted", "true",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        launchArguments += additionalLaunchArguments
        if try isInternalUserModeEnabled() {
            launchArguments += ["-isInternalUser", "true"]
        }

        app.launchArguments = launchArguments
        app.launchEnvironment = additionalLaunchEnvironment
        app.launchEnvironment["UITEST_MODE"] = "1"
    }

    private func isInternalUserModeEnabled() throws -> Bool {
        guard let value = ProcessInfo.processInfo.environment["INTERNAL_USER_MODE"] else {
            return false
        }

        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            throw ConfigurationError.invalidInternalUserMode(value)
        }
    }
}
