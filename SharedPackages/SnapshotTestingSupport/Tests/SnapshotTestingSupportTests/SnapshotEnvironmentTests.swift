//
//  SnapshotEnvironmentTests.swift
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

import Foundation
import SnapshotTestingSupport
import XCTest

final class SnapshotEnvironmentTests: XCTestCase {

    func testMacOS26IsAccepted() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)
        )

        XCTAssertNil(message)
    }

    func testMacOSWrongMajorVersionIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 25, minorVersion: 6, patchVersion: 0)
        )

        XCTAssertEqual(message, "UI snapshots must run on macOS 26.x. Current OS is 25.6.0.")
    }

    func testMacOSDifferentMinorVersionIsAccepted() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        )

        XCTAssertNil(message)
    }

    func testIOS264At3xIsAccepted() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
            displayScale: 3
        )

        XCTAssertNil(message)
    }

    func testIOSWrongMinorVersionIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0),
            displayScale: 3
        )

        XCTAssertEqual(message, "UI snapshots must run on iOS 26.4. Current OS is 26.1.0.")
    }

    func testIOS26At2xIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0),
            displayScale: 2
        )

        XCTAssertEqual(message, "iOS UI snapshots must run at @3x scale. Current scale is 2.0.")
    }
}
