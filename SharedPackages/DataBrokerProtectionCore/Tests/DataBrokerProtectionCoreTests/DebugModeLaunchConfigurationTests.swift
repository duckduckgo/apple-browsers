//
//  DebugModeLaunchConfigurationTests.swift
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

#if DEBUG
import XCTest
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class DebugModeLaunchConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var settings: DataBrokerProtectionSettings!

    override func setUpWithError() throws {
        suite = "DebugModeLaunchConfigurationTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        settings = DataBrokerProtectionSettings(defaults: defaults)
        settings.selectedEnvironment = .staging
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testLaunchSettingsOverrideEnvironmentWithoutWritingPreferences() {
        settings.selectedEnvironment = .production
        settings.serviceRoot = "https://example.com"
        let isolated = settings.isolatedDebugSettingsForLaunch(arguments: [], environment: [
            "PIR_DEBUG_INSTANCE_ID": UUID().uuidString,
            "PIR_DEBUG_PORT": "8765",
            "PIR_DEBUG_SERVER": "true",
            "PIR_DEBUG_ENVIRONMENT": "staging"
        ])
        XCTAssertEqual(isolated.selectedEnvironment, .staging)
        XCTAssertEqual(isolated.endpointURL.absoluteString, "https://dbp-staging.duckduckgo.com")
        XCTAssertEqual(settings.selectedEnvironment, .production)
        XCTAssertEqual(settings.endpointURL.absoluteString, "https://example.com")
        let normal = settings.isolatedDebugSettingsForLaunch(arguments: [], environment: ["PIR_DEBUG_ENVIRONMENT": "staging"])
        XCTAssertTrue(normal === settings)
    }

    func testArgumentOnlyLaunchConfigurationAndSettings() throws {
        let instance = UUID().uuidString
        let arguments = ["Agent", "-pirDebugServer", "true", "-pirDebugPort", "8765", "-pirDebugInstanceID", instance,
                         "-pirDebugEnvironment", "production"]
        let configuration = try XCTUnwrap(DebugModeLaunchConfiguration.parse(arguments: arguments, environment: [:]))
        XCTAssertEqual(configuration.instanceID, instance)
        XCTAssertEqual(configuration.port, 8765)
        XCTAssertEqual(configuration.environment, .production)
        let isolated = settings.isolatedDebugSettingsForLaunch(arguments: arguments, environment: [:])
        XCTAssertEqual(isolated.selectedEnvironment, .production)
        XCTAssertEqual(isolated.endpointURL.absoluteString, "https://dbp.duckduckgo.com")
        XCTAssertEqual(settings.selectedEnvironment, .staging)
    }

    func testEnvironmentOnlyLaunchConfiguration() throws {
        let instance = UUID().uuidString
        let configuration = try XCTUnwrap(DebugModeLaunchConfiguration.parse(arguments: [], environment: [
            "PIR_DEBUG_INSTANCE_ID": instance, "PIR_DEBUG_PORT": "8765",
            "PIR_DEBUG_SERVER": "true", "PIR_DEBUG_ENVIRONMENT": "staging"
        ]))
        XCTAssertEqual(configuration.instanceID, instance)
        XCTAssertEqual(configuration.port, 8765)
        XCTAssertEqual(configuration.environment, .staging)
    }

    func testLaunchArgumentsOverrideEnvironmentAndDoNotFallbackWhenMalformed() throws {
        let instance = UUID().uuidString
        let environment = ["PIR_DEBUG_INSTANCE_ID": UUID().uuidString, "PIR_DEBUG_PORT": "9000",
                           "PIR_DEBUG_SERVER": "false", "PIR_DEBUG_ENVIRONMENT": "production"]
        let arguments = ["-pirDebugServer", "true", "-pirDebugPort", "8765", "-pirDebugInstanceID", instance,
                         "-pirDebugEnvironment", "staging"]
        let configuration = try XCTUnwrap(DebugModeLaunchConfiguration.parse(arguments: arguments, environment: environment))
        XCTAssertEqual(configuration.instanceID, instance)
        XCTAssertEqual(configuration.port, 8765)
        XCTAssertEqual(configuration.environment, .staging)
        XCTAssertThrowsError(try DebugModeLaunchConfiguration.parse(arguments: arguments + ["-pirDebugPort"], environment: environment)) { error in
            XCTAssertEqual(error as? DebugModeLaunchConfiguration.ConfigurationError, .invalidPort)
        }
    }

    func testMalformedStandaloneRequestStillSelectsIsolatedMode() throws {
        for arguments in [["-pirDebugInstanceID"], ["-pirDebugInstanceID", "invalid"], ["-pirDebugInstanceID", ""]] {
            XCTAssertTrue(DebugModeLaunchConfiguration.isRequested(arguments: arguments, environment: [:]))
            XCTAssertThrowsError(try DebugModeLaunchConfiguration.parse(arguments: arguments, environment: [:])) { error in
                XCTAssertEqual(error as? DebugModeLaunchConfiguration.ConfigurationError, .invalidInstanceID)
            }
        }
        XCTAssertTrue(DebugModeLaunchConfiguration.isRequested(arguments: [], environment: ["PIR_DEBUG_INSTANCE_ID": ""]))
        XCTAssertNil(try DebugModeLaunchConfiguration.parse(arguments: [], environment: [:]))
    }

    func testAnyStandaloneMarkerWithoutInstanceRemainsIsolatedAndRejectsConfiguration() {
        let arguments = ["-pirDebugServer", "-pirDebugPort", "-pirDebugEnvironment"]
        let environments = ["PIR_DEBUG_SERVER", "PIR_DEBUG_PORT", "PIR_DEBUG_ENVIRONMENT"]
        for argument in arguments {
            let values = [argument, "true"]
            XCTAssertTrue(DebugModeLaunchConfiguration.isRequested(arguments: values, environment: [:]))
            XCTAssertThrowsError(try DebugModeLaunchConfiguration.parse(arguments: values, environment: [:])) { error in
                XCTAssertEqual(error as? DebugModeLaunchConfiguration.ConfigurationError, .invalidInstanceID)
            }
        }
        for marker in environments {
            let values = [marker: ""]
            XCTAssertTrue(DebugModeLaunchConfiguration.isRequested(arguments: [], environment: values))
            XCTAssertThrowsError(try DebugModeLaunchConfiguration.parse(arguments: [], environment: values)) { error in
                XCTAssertEqual(error as? DebugModeLaunchConfiguration.ConfigurationError, .invalidInstanceID)
            }
        }
        let environment = ["PIR_DEBUG_SERVER": "true", "PIR_DEBUG_PORT": "8765", "PIR_DEBUG_ENVIRONMENT": "staging"]
        XCTAssertTrue(DebugModeLaunchConfiguration.isRequested(arguments: [], environment: environment))
        XCTAssertThrowsError(try DebugModeLaunchConfiguration.parse(arguments: [], environment: environment)) { error in
            XCTAssertEqual(error as? DebugModeLaunchConfiguration.ConfigurationError, .invalidInstanceID)
        }
    }

    func testStandaloneConfigurationRejectsInvalidPortEnvironmentAndServerWithoutEchoingValues() throws {
        typealias Failure = DebugModeLaunchConfiguration.ConfigurationError
        let base = ["-pirDebugInstanceID", UUID().uuidString, "-pirDebugPort", "8765", "-pirDebugEnvironment", "staging", "-pirDebugServer", "true"]
        let invalid: [(String, String, Failure)] = [
            ("-pirDebugPort", "0", .invalidPort), ("-pirDebugPort", "65536", .invalidPort),
            ("-pirDebugEnvironment", "unexpected-value", .invalidEnvironment),
            ("-pirDebugServer", "false", .serverNotRequested)
        ]
        for (argument, value, expected) in invalid {
            XCTAssertThrowsError(try DebugModeLaunchConfiguration.parse(arguments: base + [argument, value], environment: [:])) { error in
                XCTAssertEqual(error as? Failure, expected)
            }
        }
    }

}
#endif
