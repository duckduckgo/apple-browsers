//
//  DuckAiNativeStorageContainerMigrationTests.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo

final class DuckAiNativeStorageContainerMigrationTests: XCTestCase {

    private var sandbox: URL!
    private var userDefaults: UserDefaults!
    private let migrationKey = "test.migrationDone"
    private let suiteName = "DuckAiNativeStorageContainerMigrationTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckAiNativeStorageContainerMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suiteName)
        userDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        sandbox = nil
        try super.tearDownWithError()
    }

    func testWhenOldDirectoryDoesNotExistThenFlagIsSetAndNothingMoves() {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")

        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationDoneKey: migrationKey,
            userDefaults: userDefaults
        )

        XCTAssertTrue(userDefaults.bool(forKey: migrationKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testWhenOldDirectoryExistsAndNewDoesNotThenContentsAreMovedAndFlagIsSet() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        try Data("files".utf8).write(to: oldURL.appendingPathComponent("files.bin"))

        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationDoneKey: migrationKey,
            userDefaults: userDefaults
        )

        XCTAssertTrue(userDefaults.bool(forKey: migrationKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("files.bin")), Data("files".utf8))
    }

    func testWhenBothOldAndNewExistThenOldIsRemovedAndNewIsPreserved() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        try Data("keep-me".utf8).write(to: newURL.appendingPathComponent("chats.db"))

        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationDoneKey: migrationKey,
            userDefaults: userDefaults
        )

        XCTAssertTrue(userDefaults.bool(forKey: migrationKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("keep-me".utf8))
    }

    func testWhenFlagAlreadySetThenNoMigrationHappensEvenIfOldExists() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("untouched".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        userDefaults.set(true, forKey: migrationKey)

        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationDoneKey: migrationKey,
            userDefaults: userDefaults
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testWhenMigrationRunsTwiceThenSecondCallIsNoOp() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationDoneKey: migrationKey,
            userDefaults: userDefaults
        )

        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("reappeared".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationDoneKey: migrationKey,
            userDefaults: userDefaults
        )

        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("first".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
    }
}
