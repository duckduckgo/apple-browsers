//
//  SnapshotRecordModeTests.swift
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

@Suite("Snapshot Record Mode Tests")
struct SnapshotRecordModeTests {

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recordArgumentEnablesRecording() {
        #expect(SnapshotRecordMode.shouldRecord(record: true, environment: [:]))
        #expect(
            SnapshotRecordMode.snapshotTestingRecord(record: true, environment: [:]) == .all
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func environmentFlagEnablesRecording() {
        #expect(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "1"]))
        #expect(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "true"]))
        #expect(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "YES"]))
        #expect(
            SnapshotRecordMode.snapshotTestingRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "1"]) == .all
        )
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func onlyMissingSnapshotsAreRecordedByDefault() {
        #expect(!SnapshotRecordMode.shouldRecord(record: false, environment: [:]))
        #expect(!SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "0"]))
        #expect(
            SnapshotRecordMode.snapshotTestingRecord(record: false, environment: [:]) == .missing
        )
        #expect(
            SnapshotRecordMode.snapshotTestingRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "0"]) == .missing
        )
    }
}
