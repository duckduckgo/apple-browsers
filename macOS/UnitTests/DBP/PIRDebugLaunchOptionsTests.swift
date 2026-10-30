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

    func testPIRDebugLaunchReadsEnvironmentAndNativeProfile() throws {
        let options = try XCTUnwrap(PIRDebugLaunchOptions.parse(arguments: [], environment: [
            "PIR_DEBUG_SERVER": "true",
            "PIR_PROFILE_JSON": pirProfileJSON,
        ]))
        XCTAssertTrue(options.startServer)
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
}
#endif
