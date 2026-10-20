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

@testable import DuckDuckGo_Privacy_Browser

final class PIRDebugLaunchOptionsTests: XCTestCase {
    private var pirProfileJSON: String {
        """
        {"names":[{"firstName":"Test","lastName":"Person"}],"addresses":[{"city":"Test City","state":"CA"}],"phones":[],"birthYear":1980}
        """
    }

    func testPIRDebugLaunchWithoutOptionsReturnsNil() throws {
        XCTAssertNil(try PIRDebugLaunchOptions.parse(arguments: [], environment: [:]))
    }

    func testPIRDebugLaunchReadsEnvironmentAndNativeProfile() throws {
        let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [], environment: [
            "PIR_DEBUG_SERVER": "true",
            "PIR_PROFILE_JSON": pirProfileJSON,
            "PIR_RESET_BEFORE_SEEDING": "true",
        ]))
        XCTAssertTrue(options.startServer)
        guard case .resetAndSeed(let profile) = options.profileSetup else {
            return XCTFail("Expected explicit reset and seed")
        }
        XCTAssertEqual(profile.names.first?.firstName, "Test")
        XCTAssertEqual(profile.addresses.first?.city, "Test City")
        XCTAssertEqual(profile.birthYear, 1980)
        XCTAssertTrue(profile.phones.isEmpty)
    }

    func testPIRDebugLaunchArgumentsOverrideEnvironmentIncludingFalse() throws {
        let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [
            "DuckDuckGo", "-pirDebugServer", "false", "-pirProfileJSON", pirProfileJSON, "-pirResetBeforeSeeding", "false",
        ], environment: [
            "PIR_DEBUG_SERVER": "true",
            "PIR_PROFILE_JSON": "invalid",
            "PIR_RESET_BEFORE_SEEDING": "true",
        ]))
        guard case .seedIfMissing(let profile) = options.profileSetup else {
            return XCTFail("Expected non-destructive profile seeding")
        }
        XCTAssertEqual(profile.birthYear, 1980)
        XCTAssertFalse(options.startServer)
    }

    func testPIRDebugLaunchResetsWithRawJSONArgument() throws {
        let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [
            "DuckDuckGo", "-pirProfileJSON", pirProfileJSON, "-pirResetBeforeSeeding", "true", "-pirDebugServer", "true",
        ], environment: [:]))
        guard case .resetAndSeed(let profile) = options.profileSetup else {
            return XCTFail("Expected explicit reset and seed")
        }
        XCTAssertEqual(profile.names.first?.firstName, "Test")
        XCTAssertEqual(profile.addresses.first?.city, "Test City")
        XCTAssertTrue(options.startServer)
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
}
#endif
