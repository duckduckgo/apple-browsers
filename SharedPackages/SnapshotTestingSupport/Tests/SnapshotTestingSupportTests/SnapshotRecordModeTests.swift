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
import XCTest

final class SnapshotRecordModeTests: XCTestCase {

    func testRecordArgumentEnablesRecording() {
        XCTAssertTrue(SnapshotRecordMode.shouldRecord(record: true, environment: [:]))
        XCTAssertEqual(
            SnapshotRecordMode.snapshotTestingRecord(record: true, environment: [:]),
            .all
        )
    }

    func testEnvironmentFlagEnablesRecording() {
        XCTAssertTrue(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "1"]))
        XCTAssertTrue(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "true"]))
        XCTAssertTrue(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "YES"]))
        XCTAssertEqual(
            SnapshotRecordMode.snapshotTestingRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "1"]),
            .all
        )
    }

    func testOnlyMissingSnapshotsAreRecordedByDefault() {
        XCTAssertFalse(SnapshotRecordMode.shouldRecord(record: false, environment: [:]))
        XCTAssertFalse(SnapshotRecordMode.shouldRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "0"]))
        XCTAssertEqual(
            SnapshotRecordMode.snapshotTestingRecord(record: false, environment: [:]),
            .missing
        )
        XCTAssertEqual(
            SnapshotRecordMode.snapshotTestingRecord(record: false, environment: ["GENERATE_SNAPSHOTS": "0"]),
            .missing
        )
    }
}
