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
import Testing

@Suite("Snapshot Environment Tests")
struct SnapshotEnvironmentTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOS2660IsAccepted() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)
        )

        #expect(message == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSWrongMajorVersionIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 25, minorVersion: 6, patchVersion: 0)
        )

        #expect(message == "UI snapshots must run on macOS 26.6.0. Current OS is 25.6.0.")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSDifferentMinorVersionIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)
        )

        #expect(message == "UI snapshots must run on macOS 26.6.0. Current OS is 26.1.0.")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSDifferentPatchVersionIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 1)
        )

        #expect(message == "UI snapshots must run on macOS 26.6.0. Current OS is 26.6.1.")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOS2651At3xIsAccepted() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1),
            displayScale: 3
        )

        #expect(message == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSWrongMinorVersionIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0),
            displayScale: 3
        )

        #expect(message == "UI snapshots must run on iOS 26.5. Current OS is 26.1.0.")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOS26At2xIsRejected() {
        let message = SnapshotEnvironment.validationMessage(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1),
            displayScale: 2
        )

        #expect(message == "iOS UI snapshots must run at @3x scale. Current scale is 2.0.")
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func referenceEnvironmentSuffixMatchesGuardGranularity() {
        #expect(
            SnapshotEnvironment.referenceEnvironmentSuffix(
                platform: .iOS,
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1)
            ) == "iOS-26-5"
        )

        #expect(
            SnapshotEnvironment.referenceEnvironmentSuffix(
                platform: .macOS,
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0)
            ) == "macOS-26-6-0"
        )
    }
}
