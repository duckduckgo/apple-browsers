//
//  PIRDebugLaunchOptionsTests.swift
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

final class PIRDebugLaunchOptionsTests: XCTestCase {
    private var pirProfileJSON: String {
        """
        {"names":[{"firstName":"Test","lastName":"Person"}],"addresses":[{"city":"Test City","state":"CA"}],"phones":[],"birthYear":1980}
        """
    }

    private func managedEnvironment(mode: String = "seed") -> [String: String] {
        [
            "PIR_SCHEDULER_MODE": mode,
            "PIR_SCHEDULER_INSTANCE_ID": "123e4567-e89b-42d3-a456-426614174000",
            "PIR_SCHEDULER_RECEIPT": FileManager.default.temporaryDirectory.appendingPathComponent("scheduler-launch-\(UUID().uuidString).json").path,
            "PIR_PROFILE_JSON": pirProfileJSON,
        ]
    }

    func testPIRDebugLaunchReadsEnvironmentAndNativeProfile() throws {
        let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [], environment: [
            "PIR_DEBUG_SERVER": "true",
            "PIR_PROFILE_JSON": pirProfileJSON,
        ]))
        XCTAssertTrue(options.startServer)
        XCTAssertNil(options.managedSeed)
        let setup = try XCTUnwrap(options.profileSetup)
        XCTAssertFalse(setup.resetBeforeSeeding)
        let profile = setup.profile
        XCTAssertEqual(profile.names.first?.firstName, "Test")
        XCTAssertEqual(profile.addresses.first?.city, "Test City")
        XCTAssertEqual(profile.birthYear, 1980)
        XCTAssertTrue(profile.phones.isEmpty)
    }

    func testPIRDebugLaunchRawJSONArgumentsOverrideEnvironmentIncludingFalse() throws {
        let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [
            "DuckDuckGo", "-pirDebugServer", "false", "-pirProfileJSON", pirProfileJSON, "-pirResetBeforeSeeding", "true",
        ], environment: [
            "PIR_DEBUG_SERVER": "true",
            "PIR_PROFILE_JSON": "invalid",
            "PIR_RESET_BEFORE_SEEDING": "false",
        ]))
        let setup = try XCTUnwrap(options.profileSetup)
        XCTAssertTrue(setup.resetBeforeSeeding)
        let profile = setup.profile
        XCTAssertEqual(profile.names.first?.firstName, "Test")
        XCTAssertEqual(profile.addresses.first?.city, "Test City")
        XCTAssertEqual(profile.birthYear, 1980)
        XCTAssertFalse(options.startServer)
    }

    func testPIRDebugLaunchRejectsResetWithoutValidFixtureEvenWithServer() {
        XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: ["DuckDuckGo", "-pirResetBeforeSeeding", "true"], environment: [:]))
        XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [
            "DuckDuckGo", "-pirResetBeforeSeeding", "true", "-pirDebugServer", "true", "-pirProfileJSON", "invalid",
        ], environment: [:]))
        XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [
            "DuckDuckGo", "-pirResetBeforeSeeding", "true", "-pirProfileJSON", pirProfileJSON.replacingOccurrences(of: "Test City", with: " "),
        ], environment: [:]))
    }

    func testManagedSeedRequiresCompleteIdentityAndFixture() {
        let environment = managedEnvironment()
        for key in ["PIR_SCHEDULER_MODE", "PIR_SCHEDULER_INSTANCE_ID", "PIR_SCHEDULER_RECEIPT", "PIR_PROFILE_JSON"] {
            var incomplete = environment
            incomplete.removeValue(forKey: key)
            XCTAssertTrue(PIRDebugLaunchOptions.hasManagedRequest(environment: incomplete))
            XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [], environment: incomplete), key)
        }
        for (key, value) in [("PIR_SCHEDULER_MODE", "reset"), ("PIR_SCHEDULER_INSTANCE_ID", "invalid"), ("PIR_PROFILE_JSON", "invalid")] {
            var invalid = environment
            invalid[key] = value
            XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [], environment: invalid), key)
        }
        XCTAssertFalse(PIRDebugLaunchOptions.hasManagedRequest(environment: [:]))
    }

    func testManagedModesImplyServerAndPreserveInstanceIdentity() throws {
        for mode in ["seed", "reseed"] {
            let environment = managedEnvironment(mode: mode)
            let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: ["DuckDuckGo", "-pirDebugServer", "false"], environment: environment))
            XCTAssertTrue(options.startServer)
            XCTAssertNotNil(options.profileSetup)
            let managed = try XCTUnwrap(options.managedSeed)
            XCTAssertEqual(managed.mode.rawValue, mode)
            XCTAssertEqual(managed.instanceID, environment["PIR_SCHEDULER_INSTANCE_ID"])
            XCTAssertEqual(managed.receiptURL.path, environment["PIR_SCHEDULER_RECEIPT"])
            XCTAssertEqual(managed.resetBeforeSeeding, mode == "reseed")
        }
    }

    func testManagedModesRejectAnyLegacyResetOption() {
        for mode in ["seed", "reseed"] {
            for value in ["true", "false"] {
                var environment = managedEnvironment(mode: mode)
                environment["PIR_RESET_BEFORE_SEEDING"] = value
                XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [], environment: environment))
                environment.removeValue(forKey: "PIR_RESET_BEFORE_SEEDING")
                XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [
                    "DuckDuckGo", "-pirResetBeforeSeeding", value,
                ], environment: environment))
            }
        }
    }

    func testManagedSeedRefusesExistingProfileAndEitherAuthenticationSource() throws {
        for mode in ["seed", "reseed"] {
            let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [], environment: managedEnvironment(mode: mode)))
            let managed = try XCTUnwrap(options.managedSeed)
            XCTAssertNoThrow(try managed.validateAccount(rawAuthenticated: false, pirAuthenticated: false))
            for (raw, pir) in [(true, false), (false, true), (true, true)] {
                XCTAssertThrowsError(try managed.validateAccount(rawAuthenticated: raw, pirAuthenticated: pir)) { error in
                    XCTAssertEqual((error as? PIRDebugLaunchOptions.ParseError)?.receiptErrorCode, "authenticatedAccount")
                }
            }
            XCTAssertNoThrow(try managed.validateExistingProfile(false))
            if mode == "seed" {
                XCTAssertThrowsError(try managed.validateExistingProfile(true)) { error in
                    XCTAssertEqual((error as? PIRDebugLaunchOptions.ParseError)?.receiptErrorCode, "profileAlreadyExists")
                }
            } else {
                XCTAssertNoThrow(try managed.validateExistingProfile(true))
            }
        }
    }

    func testManagedReceiptRejectsRelativeDirectoryAndNoncanonicalDestinations() {
        for path in ["", "scheduler-launch.json", "/", "/tmp/../tmp/scheduler-launch.json", "/tmp/"] {
            var environment = managedEnvironment()
            environment["PIR_SCHEDULER_RECEIPT"] = path
            XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [], environment: environment), path)
        }
    }

    func testManagedReceiptRejectsSymlinks() throws {
        let link = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/tmp/absent-pir-receipt.json")
        defer { try? FileManager.default.removeItem(at: link) }
        var environment = managedEnvironment()
        environment["PIR_SCHEDULER_RECEIPT"] = link.path
        XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [], environment: environment))
    }

    func testMalformedManagedFixtureStillResolvesSafeErrorReceiptDestination() throws {
        var environment = managedEnvironment()
        environment["PIR_PROFILE_JSON"] = "invalid"
        XCTAssertThrowsError(try PIRDebugLaunchOptions.parse(arguments: [], environment: environment))
        let managed = try XCTUnwrap(PIRDebugLaunchOptions.managedSeed(environment: environment))
        XCTAssertEqual(managed.instanceID, environment["PIR_SCHEDULER_INSTANCE_ID"])
    }

    func testManagedReceiptRecordsReadyJobsAndErrorCodes() throws {
        let environment = managedEnvironment(mode: "reseed")
        let managed = try XCTUnwrap(PIRDebugLaunchOptions.managedSeed(environment: environment))
        defer { try? FileManager.default.removeItem(at: managed.receiptURL) }
        let since = Date(timeIntervalSince1970: 1_800_000_000)
        let job = PIRDebugLaunchOptions.DebugScanJob(brokerURL: "example.com", profileQueryId: 7)

        try managed.writeReceipt(since: since, jobs: [job])
        let ready = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: managed.receiptURL)) as? [String: Any])
        XCTAssertEqual(ready["instanceID"] as? String, environment["PIR_SCHEDULER_INSTANCE_ID"])
        XCTAssertEqual(ready["mode"] as? String, "reseed")
        XCTAssertEqual(ready["status"] as? String, "ready")
        XCTAssertEqual(ready["since"] as? String, "2027-01-15T08:00:00Z")
        XCTAssertEqual(ready["jobs"] as? [[String: AnyHashable]], [["brokerURL": "example.com", "profileQueryId": 7]])
        XCTAssertNil(ready["errorCode"])

        try managed.writeReceipt(since: since, error: PIRDebugLaunchOptions.ParseError.existingProfile)
        let failed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: managed.receiptURL)) as? [String: Any])
        XCTAssertEqual(failed["status"] as? String, "error")
        XCTAssertEqual(failed["errorCode"] as? String, "profileAlreadyExists")
        XCTAssertEqual((failed["jobs"] as? [Any])?.count, 0)
    }
}
#endif
