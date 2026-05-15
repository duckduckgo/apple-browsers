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
    private var pixelSpy: SpyContainerMigrationPixelFiring!
    private let migrationKey = "test.migration"
    private let label: DuckAiNativeStorageContainerMigrationLabel = .default
    private let suiteName = "DuckAiNativeStorageContainerMigrationTests"

    private var doneKey: String { migrationKey + ".done" }
    private var attemptsKey: String { migrationKey + ".attempts" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckAiNativeStorageContainerMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suiteName)
        userDefaults = UserDefaults(suiteName: suiteName)
        pixelSpy = SpyContainerMigrationPixelFiring()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        sandbox = nil
        pixelSpy = nil
        try super.tearDownWithError()
    }

    // MARK: - Happy paths

    func testWhenOldDirectoryDoesNotExistThenFlagIsSetAndNotNeededPixelFires() {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["notNeeded"])
    }

    func testWhenOldDirectoryExistsAndNewDoesNotThenContentsAreMovedAndSuccessPixelFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        try Data("files".utf8).write(to: oldURL.appendingPathComponent("files.bin"))

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("files.bin")), Data("files".utf8))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    func testWhenBothOldAndNewExistThenOldIsRemovedAndOrphanRemovedPixelFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        try Data("keep-me".utf8).write(to: newURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("keep-me".utf8))
        XCTAssertEqual(pixelSpy.firedEventNames, ["orphanRemoved"])
    }

    func testWhenDoneFlagAlreadySetThenNoMigrationHappensAndNoPixelFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("untouched".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        userDefaults.set(true, forKey: doneKey)

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    func testWhenMigrationSucceedsThenSecondCallIsNoOp() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("reappeared".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("first".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    // MARK: - Retry behavior

    func testWhenMoveFailsThenAttemptIsRecordedAndDoneFlagNotSet() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        let failingFM = FailingMoveFileManager()

        migrate(from: oldURL, to: newURL, fileManager: failingFM, maxAttempts: 3)

        XCTAssertFalse(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed"])
    }

    func testWhenMoveFailsRepeatedlyThenGivesUpAtMaxAttempts() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        let failingFM = FailingMoveFileManager()

        for _ in 0..<3 {
            migrate(from: oldURL, to: newURL, fileManager: failingFM, maxAttempts: 3)
        }

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 3)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
    }

    func testWhenMoveFailsThenSucceedsThenAttemptsAreClearedAndSuccessPixelFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("data".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))

        migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 0)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "success"])
    }

    func testWhenGaveUpThenSubsequentCallsAreSkipped() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)

        for _ in 0..<3 {
            migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)
        }
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))

        // Even with a non-failing FM and old data still present, we don't retry.
        migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
    }

    // MARK: - Helpers

    private func migrate(from oldURL: URL,
                         to newURL: URL,
                         fileManager: FileManager = .default,
                         maxAttempts: Int = DuckAiNativeStorageContainerMigration.defaultMaxAttempts) {
        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationKey: migrationKey,
            label: label,
            userDefaults: userDefaults,
            fileManager: fileManager,
            pixelFiring: pixelSpy,
            maxAttempts: maxAttempts
        )
    }
}

// MARK: - Test doubles

private final class SpyContainerMigrationPixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring {
    private(set) var firedEventNames: [String] = []

    func fire(_ event: DuckAiNativeStorageContainerMigrationEvent) {
        switch event {
        case .notNeeded: firedEventNames.append("notNeeded")
        case .orphanRemoved: firedEventNames.append("orphanRemoved")
        case .success: firedEventNames.append("success")
        case .attemptFailed: firedEventNames.append("attemptFailed")
        case .gaveUp: firedEventNames.append("gaveUp")
        }
    }
}

private final class FailingMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: "DuckAiNativeStorageContainerMigrationTests", code: -1)
    }
}
