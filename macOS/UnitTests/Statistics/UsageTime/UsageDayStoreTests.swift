//
//  UsageDayStoreTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class UsageDayStoreTests: XCTestCase {
    private var directory: URL!
    private let start = Date(timeIntervalSince1970: 1_795_582_800)
    private var discards = 0

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func store() -> UsageDayStore {
        UsageDayStore(directory: directory) { self.discards += 1 }
    }

    func testRestorePreservesFirstSignalAndMergesUsageObservedWhileUnavailable() throws {
        do {
            let first = store()
            try first.restore()
            first.add([.init(start: start, open: 300, active: 20)])
            try first.checkpoint(at: start)
            XCTAssertThrowsError(try store().restore())
        }
        let second = store()
        second.add([.init(start: start.addingTimeInterval(3600), open: 100, active: 5)])
        try second.restore()
        XCTAssertEqual(second.days[start], UsageDayRecord(firstSignal: start, open: 400, active: 25))
        XCTAssertEqual(discards, 0)
    }

    func testCorruptStoreIsDiscardedOnceAndNewUsagePersists() throws {
        do {
            let first = store()
            try first.restore()
            try first.checkpoint(at: start)
        }
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data([0xff]).write(to: file)
        do {
            let reset = store()
            try reset.restore()
            XCTAssertEqual(discards, 1)
            reset.add([.init(start: start, open: 10, active: 5)])
            try reset.checkpoint(at: start)
        }
        let recovered = store()
        try recovered.restore()
        XCTAssertEqual(recovered.days[start]?.open, 10)
        XCTAssertEqual(discards, 1)
    }

    func testFailedFinalizationLeavesPendingUsageUntilCutoff() throws {
        let item = store()
        try item.restore()
        item.add([.init(start: start, open: 90_000, active: 87_000)])
        try FileManager.default.removeItem(at: directory)
        let daySeven = start.addingTimeInterval(7 * 86_400)
        XCTAssertThrowsError(try item.checkpoint(at: daySeven) { record in
            record.reportIfEligible(asOf: daySeven)
        })
        XCTAssertNil(item.days[start]?.delivery)
        XCTAssertEqual(item.days[start]?.active, 86_400)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try item.checkpoint(at: daySeven.addingTimeInterval(86_400))
        XCTAssertTrue(item.days.isEmpty)
        XCTAssertEqual(discards, 0)
    }

    func testRestoredDeliveryRemainsImmutable() throws {
        let tomorrow = start.addingTimeInterval(86_400)
        let delivery = UsageDayRecord.Delivery(finalizedAt: tomorrow, payload: DailyUsagePayload(record: .init(firstSignal: start, open: 300, active: 20), asOf: tomorrow))
        do {
            let first = store()
            try first.restore()
            first.add([.init(start: start, open: 300, active: 20)])
            try first.checkpoint(at: tomorrow) { _ in delivery }
        }
        let reopened = store()
        try reopened.restore()
        reopened.add([.init(start: start, open: 20, active: 10)])
        try reopened.checkpoint(at: tomorrow) { _ in
            XCTFail("Already finalized")
            return nil
        }
        XCTAssertEqual(reopened.days[start], UsageDayRecord(firstSignal: start, open: 300, active: 20, delivery: delivery))
    }

    func testInvalidInnerSnapshotAndFailedDiscard() throws {
        do {
            let first = store()
            try first.restore()
            try first.checkpoint(at: start)
        }
        let manager = FileManager.default
        let file = try XCTUnwrap(manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let invalid = try PropertyListSerialization.data(fromPropertyList: ["days.v1": Data([0xff])], format: .binary, options: 0)
        try invalid.write(to: file)
        let reopened = store()
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertThrowsError(try reopened.restore())
        XCTAssertEqual(discards, 0)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try reopened.restore()
        XCTAssertEqual(discards, 1)
    }
}
