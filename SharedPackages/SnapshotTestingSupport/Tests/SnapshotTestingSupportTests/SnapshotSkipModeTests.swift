//
//  SnapshotSkipModeTests.swift
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

@testable import SnapshotTestingSupport
import Testing

@Suite("Snapshot Skip Mode Tests")
struct SnapshotSkipModeTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func environmentFlagEnablesSkipping() {
        #expect(SnapshotSkipMode.isEnabled(environment: ["SKIP_SNAPSHOT_TESTS": "1"]))
        #expect(SnapshotSkipMode.isEnabled(environment: ["SKIP_SNAPSHOT_TESTS": "true"]))
        #expect(SnapshotSkipMode.isEnabled(environment: ["SKIP_SNAPSHOT_TESTS": "YES"]))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func snapshotsRunByDefault() {
        #expect(!SnapshotSkipMode.isEnabled(environment: [:]))
        #expect(!SnapshotSkipMode.isEnabled(environment: ["SKIP_SNAPSHOT_TESTS": "0"]))
        #expect(!SnapshotSkipMode.isEnabled(environment: ["SKIP_SNAPSHOT_TESTS": "false"]))
        #expect(!SnapshotSkipMode.isEnabled(environment: ["SKIP_SNAPSHOT_TESTS": ""]))
    }
}
