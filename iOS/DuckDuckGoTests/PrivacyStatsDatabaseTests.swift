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

    func testWhenStoreLoadsThenDatabaseIsUsableAndNoPixelIsFired() throws {
        let database = try XCTUnwrap(PrivacyStatsDatabase(location: location, pixelFiring: pixelKit))

        try assertStoreIsUsable(database)
        XCTAssertTrue(pixelKit.actualFireCalls.isEmpty)
    }

    func testWhenStoreIsCorruptedThenItIsRecreatedAndPixelIsFired() throws {
        try Data(repeating: 0xAB, count: 4096).write(to: location.appendingPathComponent("PrivacyStats.sqlite"))

        // Before the fix, creating PrivacyStats never returned here.
        let database = try XCTUnwrap(PrivacyStatsDatabase(location: location, pixelFiring: pixelKit))

        try assertStoreIsUsable(database)
        XCTAssertEqual(pixelKit.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixelKit.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "privacy-stats_database_load_failed")
        XCTAssertEqual(call.pixel.parameters, ["outcome": "recreated"])
        XCTAssertEqual(call.pixel.error?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(call.frequency, .dailyAndCount)
    }

    func testWhenStoreFailsToLoadForAnotherReasonThenDatabaseIsNilWithoutRecreatingIt() throws {
        // A regular file in the store's path means the store directory can't be created, which isn't corruption.
        let blockingFile = location.appendingPathComponent("blocker")
        try Data().write(to: blockingFile)

        let database = PrivacyStatsDatabase(location: blockingFile.appendingPathComponent("store"), pixelFiring: pixelKit)

        XCTAssertNil(database)
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.parameters), [["outcome": "unavailable"]])
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.frequency), [.dailyAndCount])
    }

    func testWhenCorruptedStoreCannotBeDeletedThenDatabaseIsNilAndRecreateFailedIsFired() throws {
        let storeFile = location.appendingPathComponent("PrivacyStats.sqlite")
        try Data(repeating: 0xAB, count: 4096).write(to: storeFile)
        // A read-only directory means the corrupted store can't be deleted.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: location.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: location.path) }

        let database = PrivacyStatsDatabase(location: location, pixelFiring: pixelKit)

        XCTAssertNil(database)
        XCTAssertEqual(pixelKit.actualFireCalls.map(\.pixel.parameters), [["outcome": "recreate_failed"]])
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeFile.path))
    }

    func testIsCorruption() {
        let corrupt: [Error] = [
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError),
            NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSSQLiteErrorDomain: NSNumber(value: 11)]),
            NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSSQLiteErrorDomain: NSNumber(value: 26)]),
            NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSSQLiteErrorDomain: NSNumber(value: 779)]), // SQLITE_CORRUPT_INDEX
            NSError(domain: NSSQLiteErrorDomain, code: 11)
        ]
        let recoverable: [Error] = [
            NSError(domain: NSCocoaErrorDomain, code: 256),
            NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSSQLiteErrorDomain: NSNumber(value: 4618)]), // SQLITE_IOERR_SHMOPEN
            NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSSQLiteErrorDomain: NSNumber(value: 13)]), // SQLITE_FULL
            NSError(domain: NSSQLiteErrorDomain, code: 13)
        ]

        corrupt.forEach { XCTAssertTrue(PrivacyStatsDatabase.isCorruption($0), "\($0)") }
        recoverable.forEach { XCTAssertFalse(PrivacyStatsDatabase.isCorruption($0), "\($0)") }
    }

    func testWhenUnavailablePrivacyStatsIsClearedThenStoreFilesAreDeleted() async throws {
        let files = ["PrivacyStats.sqlite", "PrivacyStats.sqlite-wal", "PrivacyStats.sqlite-shm"].map { location.appendingPathComponent($0) }
        try files.forEach { try Data("stats".utf8).write(to: $0) }

        let result = await UnavailablePrivacyStats(storeLocation: location).clearPrivacyStats()

        XCTAssertNoThrow(try result.get())
        files.forEach { XCTAssertFalse(FileManager.default.fileExists(atPath: $0.path)) }
    }

    func testWhenUnavailablePrivacyStatsIsClearedWithNoStoreFilesThenItSucceeds() async {
        let result = await UnavailablePrivacyStats(storeLocation: location).clearPrivacyStats()

        XCTAssertNoThrow(try result.get())
    }

    func testWhenUnavailablePrivacyStatsCannotDeleteStoreFilesThenClearFails() async throws {
        try Data("stats".utf8).write(to: location.appendingPathComponent("PrivacyStats.sqlite"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: location.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: location.path) }

        let result = await UnavailablePrivacyStats(storeLocation: location).clearPrivacyStats()

        XCTAssertThrowsError(try result.get())
    }

    private func assertStoreIsUsable(_ database: PrivacyStatsDatabase) throws {
        let context = database.initializeDatabase().makeContext(concurrencyType: .privateQueueConcurrencyType)
        var saveError: Error?
        context.performAndWait {
            XCTAssertFalse(context.persistentStoreCoordinator?.persistentStores.isEmpty ?? true)
            do {
                try context.save()
            } catch {
                saveError = error
            }
        }
        if let saveError { throw saveError }
    }
}
