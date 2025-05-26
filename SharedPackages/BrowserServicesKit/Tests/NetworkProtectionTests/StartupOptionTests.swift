//
//  StartupOptionTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import XCTest
@testable import NetworkProtection

final class StartupOptionsTests: XCTestCase {

    /// Tests that the startup options have correct default values when the VPN is started by the system.
    ///
    /// If a check fails it means that either:
    /// - The default option changed, and this test must be adjusted; or
    /// - The default option was changed by mistake, and there's a regression
    ///
    func testStartupOptionsHaveCorrectDefaultValuesWhenStartedByTheSystem() {
        let rawOptions = [String: Any]()
        let options = StartupOptions(options: rawOptions)

        XCTAssertEqual(options.authToken, .useExisting)
        XCTAssertEqual(options.enableTester, .useExisting)
        XCTAssertEqual(options.keyValidity, .useExisting)
        XCTAssertFalse(options.simulateCrash)
        XCTAssertFalse(options.simulateError)
        XCTAssertFalse(options.simulateMemoryCrash)
        XCTAssertEqual(options.startupMethod, .manualByTheSystem)
    }

    /// Tests that the startup options have correct default values when the VPN is started by the system.
    ///
    /// If a check fails it means that either:
    /// - The default option changed, and this test must be adjusted; or
    /// - The default option was changed by mistake, and there's a regression
    ///
    func testStartupOptionsHaveCorrectDefaultValuesWhenStartedByTheApp() async throws {
        let rawOptions: [String: Any] = [
            NetworkProtectionOptionKey.activationAttemptId: UUID().uuidString,
            NetworkProtectionOptionKey.isOnDemand: NSNumber(value: false)
        ]
        let options = StartupOptions(options: rawOptions)

        XCTAssertEqual(options.authToken, .reset)
        XCTAssertEqual(options.enableTester, .reset)
        XCTAssertEqual(options.keyValidity, .reset)
        XCTAssertFalse(options.simulateCrash)
        XCTAssertFalse(options.simulateError)
        XCTAssertFalse(options.simulateMemoryCrash)
        XCTAssertEqual(options.startupMethod, .manualByMainApp)
    }

    /// Tests that the startup options have correct default values when the VPN is started by the system.
    ///
    /// If a check fails it means that either:
    /// - The default option changed, and this test must be adjusted; or
    /// - The default option was changed by mistake, and there's a regression
    ///
    func testStartupOptionsHaveCorrectDefaultValuesWhenStartedByOnDemand() async throws {
        let rawOptions: [String: Any] = [
            NetworkProtectionOptionKey.isOnDemand: NSNumber(value: true)
        ]
        let options = StartupOptions(options: rawOptions)

        XCTAssertEqual(options.authToken, .useExisting)
        XCTAssertEqual(options.enableTester, .useExisting)
        XCTAssertEqual(options.keyValidity, .useExisting)
        XCTAssertFalse(options.simulateCrash)
        XCTAssertFalse(options.simulateError)
        XCTAssertFalse(options.simulateMemoryCrash)
        XCTAssertEqual(options.startupMethod, .automaticOnDemand)
    }
}
