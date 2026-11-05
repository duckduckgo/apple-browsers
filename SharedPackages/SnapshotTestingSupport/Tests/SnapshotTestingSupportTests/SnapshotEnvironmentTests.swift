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
    func macOSCIVersionIsCompared() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0),
            environment: [:]
        )

        #expect(mode == .compare)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSCIVersionWithDifferentPatchIsCompared() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1),
            environment: ["REQUIRE_SNAPSHOT_REFERENCES": "1"]
        )

        #expect(mode == .compare)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSWrongMajorVersionSkipsAssertionsLocally() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0),
            environment: [:]
        )

        #expect(mode == .skipAssertion(reason: "UI snapshots must run on macOS 27. Current OS is 26.6.0. Snapshot assertions are skipped."))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSWrongMajorVersionIsRejectedWhenReferencesAreRequired() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 6, patchVersion: 0),
            environment: ["REQUIRE_SNAPSHOT_REFERENCES": "1"]
        )

        #expect(mode == .unsupported(reason: "UI snapshots must run on macOS 27. Current OS is 26.6.0."))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSDifferentMinorVersionSkipsComparisonLocally() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0),
            environment: [:]
        )

        #expect(mode == .skipComparison(
            reason: "macOS 27.2.0 isn't the CI version (27.0), so existing references aren't compared and CI verifies them instead. Missing references are still recorded. Set COMPARE_SNAPSHOTS=1 to compare anyway."
        ))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSDifferentMinorVersionIsComparedWhenForced() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0),
            environment: ["COMPARE_SNAPSHOTS": "1"]
        )

        #expect(mode == .compare)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func macOSDifferentMinorVersionIsComparedWithWarningWhenReferencesAreRequired() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .macOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0),
            environment: ["REQUIRE_SNAPSHOT_REFERENCES": "1"]
        )

        #expect(mode == .compareWithWarning(
            reason: "macOS 27.2.0 isn't the CI version (27.0), so references are compared anyway. Bump SnapshotEnvironment.ciMacOSVersion, and re-record the references that no longer match."
        ))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOS270At3xIsCompared() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0),
            displayScale: 3,
            environment: [:]
        )

        #expect(mode == .compare)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOSWrongMinorVersionIsRejected() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0),
            displayScale: 3,
            environment: [:]
        )

        #expect(mode == .unsupported(reason: "UI snapshots must run on iOS 27.0. Current OS is 27.1.0."))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func iOS27At2xIsRejected() {
        let mode = SnapshotEnvironment.comparisonMode(
            platform: .iOS,
            operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0),
            displayScale: 2,
            environment: [:]
        )

        #expect(mode == .unsupported(reason: "iOS UI snapshots must run at @3x scale. Current scale is 2.0."))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func onlyIOSReferencesCarryAnEnvironmentSuffix() {
        #expect(
            SnapshotEnvironment.referenceEnvironmentSuffix(
                platform: .iOS,
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
            ) == "iOS-27-0"
        )

        #expect(
            SnapshotEnvironment.referenceEnvironmentSuffix(
                platform: .macOS,
                operatingSystemVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
            ) == nil
        )
    }
}
