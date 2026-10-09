//
//  PrivacyStatsDatabaseTests.swift
//  DuckDuckGo
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

import CoreData
import Foundation
@_spi(Testing) import PixelKit
import PrivacyStats
import XCTest
@testable import DuckDuckGo

final class PrivacyStatsDatabaseTests: XCTestCase {

    private var location: URL!
    private var pixelKit: PixelKitMock!

    override func setUpWithError() throws {
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        pixelKit = PixelKitMock()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenStoreLoadsThenPrivacyStatsIsUsableAndNoPixelIsFired() async throws {
        let privacyStats = PrivacyStatsDatabase.makePrivacyStats(location: location, pixelFiring: pixelKit)

        XCTAssertFalse(privacyStats is UnavailablePrivacyStats)
        try await assertStoreIsUsable(privacyStats)
        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
    }

    func testWhenStoreIsCorruptedThenItIsRecreatedAndPixelIsFired() async throws {
        try Data(repeating: 0xAB, count: 4096).write(to: location.appendingPathComponent("PrivacyStats.sqlite"))

        // Before the fix, creating PrivacyStats never returned here.
        let privacyStats = PrivacyStatsDatabase.makePrivacyStats(location: location, pixelFiring: pixelKit)

        XCTAssertFalse(privacyStats is UnavailablePrivacyStats)
        try await assertStoreIsUsable(privacyStats)
        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixelKit.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "privacy-stats_database_load_failed")
        XCTAssertEqual(call.pixel.parameters, ["stage": "initial"])
        XCTAssertEqual(call.pixel.error?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(call.frequency, .dailyAndCount)
    }

    func testWhenStoreFolderCannotBeCreatedThenUnavailablePrivacyStatsIsReturnedWithoutRetrying() throws {
        // A regular file in the store's path means the store directory can never be created.
        let blockingFile = location.appendingPathComponent("blocker")
        try Data().write(to: blockingFile)

        let privacyStats = PrivacyStatsDatabase.makePrivacyStats(location: blockingFile.appendingPathComponent("store"), pixelFiring: pixelKit)

        XCTAssertTrue(privacyStats is UnavailablePrivacyStats)
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.parameters), [["stage": "initial"]])
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.frequency), [.dailyAndCount])
    }

    func testWhenStoreCannotBeOpenedThenItIsKeptAndUnavailablePrivacyStatsIsReturned() throws {
        // An unreadable store stands in for one that is temporarily inaccessible, e.g. before first unlock.
        let store = location.appendingPathComponent("PrivacyStats.sqlite")
        try Data(repeating: 0xAB, count: 4096).write(to: store)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: store.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.path) }

        let privacyStats = PrivacyStatsDatabase.makePrivacyStats(location: location, pixelFiring: pixelKit)

        XCTAssertTrue(privacyStats is UnavailablePrivacyStats)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path))
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.parameters), [["stage": "initial"]])
    }

    func testOnlyCorruptOrIncompatibleStoresCountAsCorrupt() {
        func coreDataError(code: Int, sqliteCode: Int? = nil) -> NSError {
            NSError(domain: NSCocoaErrorDomain, code: code, userInfo: sqliteCode.map { ["NSSQLiteErrorDomain": $0] } ?? [:])
        }

        XCTAssertTrue(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSFileReadCorruptFileError, sqliteCode: 26)))
        XCTAssertTrue(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSFileReadCorruptFileError, sqliteCode: 11)))
        XCTAssertTrue(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSFileReadCorruptFileError)))
        XCTAssertTrue(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSPersistentStoreIncompatibleVersionHashError)))

        XCTAssertFalse(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSMigrationError, sqliteCode: 13)), "disk full")
        XCTAssertFalse(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSFileReadUnknownError, sqliteCode: 14)), "cannot open")
        XCTAssertFalse(PrivacyStatsDatabase.isCorrupt(coreDataError(code: NSFileReadNoPermissionError)))
        XCTAssertFalse(PrivacyStatsDatabase.isCorrupt(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
    }

    private func assertStoreIsUsable(_ privacyStats: PrivacyStatsProviding) async throws {
        try await privacyStats.clearPrivacyStats().get()
    }
}
