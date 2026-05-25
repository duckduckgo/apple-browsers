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

    func testWhenMoveFailsThenAttemptIsRecordedAndDoneFlagNotSetAndOutcomeIsSkip() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        let failingFM = FailingMoveFileManager()

        let outcome = migrate(from: oldURL, to: newURL, fileManager: failingFM, maxAttempts: 3)

        XCTAssertEqual(outcome, .skip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed"])
    }

    func testWhenMoveFailsRepeatedlyThenGivesUpAtMaxAttemptsAndOutcomeIsProceed() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        let failingFM = FailingMoveFileManager()

        var outcomes: [DuckAiNativeStorageContainerMigrationOutcome] = []
        for _ in 0..<3 {
            outcomes.append(migrate(from: oldURL, to: newURL, fileManager: failingFM, maxAttempts: 3))
        }

        XCTAssertEqual(outcomes, [.skip, .skip, .proceed])
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 3)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
    }

    func testWhenMoveFailsThenSucceedsThenAttemptsAreClearedAndSuccessPixelFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("data".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let firstOutcome = migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)
        XCTAssertEqual(firstOutcome, .skip)
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))

        let secondOutcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(secondOutcome, .proceed)
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
        let outcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(outcome, .proceed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
    }

    // MARK: - Orphan removal retry behavior

    func testWhenOrphanRemovalFailsThenDoneFlagNotSetAndAttemptFailedFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        try Data("keep-me".utf8).write(to: newURL.appendingPathComponent("chats.db"))

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingRemoveFileManager(), maxAttempts: 3)

        // newURL is still usable so we proceed, but old data remains and we'll retry.
        XCTAssertEqual(outcome, .proceed)
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed"])
    }

    func testWhenOrphanRemovalFailsRepeatedlyThenGivesUpAtMaxAttempts() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)

        for _ in 0..<3 {
            migrate(from: oldURL, to: newURL, fileManager: FailingRemoveFileManager(), maxAttempts: 3)
        }

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 3)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
        // The gaveUp event indicates abandoned data — orphanRemoved should NOT have fired.
        XCTAssertFalse(pixelSpy.firedEventNames.contains("orphanRemoved"))
    }

    func testWhenOrphanRemovalFailsThenSucceedsThenAttemptsAreClearedAndOrphanRemovedFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)

        migrate(from: oldURL, to: newURL, fileManager: FailingRemoveFileManager(), maxAttempts: 3)
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))

        let outcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(outcome, .proceed)
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "orphanRemoved"])
    }

    // MARK: - File protection failure surfacing

    func testWhenMoveSucceedsButSetAttributesFailsThenSuccessAndProtectionFailedBothFire() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)

        // The move itself succeeded so we proceed and mark done — data is at newURL.
        XCTAssertEqual(outcome, .proceed)
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        // But protection failed, so both pixels fire — `.success` then `.protectionFailed`.
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed"])
        XCTAssertEqual((pixelSpy.lastProtectionFailedError as NSError?)?.domain, FailingSetAttributesFileManager.errorDomain)
        XCTAssertEqual((pixelSpy.lastProtectionFailedError as NSError?)?.code, FailingSetAttributesFileManager.errorCode)
    }

    func testWhenApplyDefaultFileProtectionSucceedsForAllPathsThenReturnsNil() throws {
        let url = sandbox.appendingPathComponent("DuckAi")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: url.appendingPathComponent("chats.db"))

        let error = DuckAiNativeStorageContainerMigration.applyDefaultFileProtection(at: url)

        XCTAssertNil(error)
    }

    func testWhenApplyDefaultFileProtectionFailsThenReturnsFirstError() throws {
        let url = sandbox.appendingPathComponent("DuckAi")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: url.appendingPathComponent("chats.db"))

        let error = DuckAiNativeStorageContainerMigration.applyDefaultFileProtection(at: url, fileManager: FailingSetAttributesFileManager())

        XCTAssertEqual((error as NSError?)?.domain, FailingSetAttributesFileManager.errorDomain)
        XCTAssertEqual((error as NSError?)?.code, FailingSetAttributesFileManager.errorCode)
    }

    // MARK: - Caller-contract regression (Issue 4)

    /// Models the launch-time factory: if migration says `.skip`, do not call
    /// `excludeFromBackup` and do not construct a handler at `newURL`.
    func testGivenFailedMoveWhenFactoryRunsThenDestinationStaysAbsentAndHandlerIsNotCreated() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user-chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        var handlerCreated = false
        let result = runFactory(
            oldURL: oldURL,
            newURL: newURL,
            fileManager: FailingMoveFileManager(),
            createHandler: {
                handlerCreated = true
                DuckAiNativeStorageContainerMigration.excludeFromBackup(newURL)
            }
        )

        XCTAssertNil(result, "factory must short-circuit when migration returns .skip")
        XCTAssertFalse(handlerCreated, "handler creation must be skipped after a failed move")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path), "destination must remain absent so next-launch retry can move the data")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path), "user data must remain at the old location")
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed"])
    }

    func testGivenFailedMoveOnFirstLaunchWhenSecondLaunchSucceedsThenHandlerIsCreatedWithMigratedData() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user-chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let firstLaunch = runFactory(oldURL: oldURL, newURL: newURL, fileManager: FailingMoveFileManager(), createHandler: {})
        XCTAssertNil(firstLaunch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))

        var secondLaunchHandlerCreated = false
        let secondLaunch = runFactory(
            oldURL: oldURL,
            newURL: newURL,
            fileManager: .default,
            createHandler: {
                secondLaunchHandlerCreated = true
                DuckAiNativeStorageContainerMigration.excludeFromBackup(newURL)
            }
        )

        XCTAssertNotNil(secondLaunch)
        XCTAssertTrue(secondLaunchHandlerCreated)
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("user-chats".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "success"])
    }

    // MARK: - Helpers

    @discardableResult
    private func migrate(from oldURL: URL,
                         to newURL: URL,
                         fileManager: FileManager = .default,
                         maxAttempts: Int = DuckAiNativeStorageContainerMigration.defaultMaxAttempts) -> DuckAiNativeStorageContainerMigrationOutcome {
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

    /// Mirrors the caller pattern in `Launching.makeNativeStorageHandler` and
    /// `FireModeNativeStorageController.init`: bail out on `.skip`, otherwise
    /// create the destination and open a handler. Returns a non-nil sentinel
    /// when a handler would have been created.
    private func runFactory(oldURL: URL,
                            newURL: URL,
                            fileManager: FileManager,
                            createHandler: () -> Void) -> AnyObject? {
        let outcome = migrate(from: oldURL, to: newURL, fileManager: fileManager)
        if outcome == .skip {
            return nil
        }
        createHandler()
        return NSObject()
    }
}

// MARK: - Test doubles

private final class SpyContainerMigrationPixelFiring: DuckAiNativeStorageContainerMigrationPixelFiring {
    private(set) var firedEventNames: [String] = []
    private(set) var lastProtectionFailedError: Error?

    func fire(_ event: DuckAiNativeStorageContainerMigrationEvent) {
        switch event {
        case .notNeeded: firedEventNames.append("notNeeded")
        case .orphanRemoved: firedEventNames.append("orphanRemoved")
        case .success: firedEventNames.append("success")
        case .attemptFailed: firedEventNames.append("attemptFailed")
        case .gaveUp: firedEventNames.append("gaveUp")
        case .protectionFailed(_, let error):
            firedEventNames.append("protectionFailed")
            lastProtectionFailedError = error
        }
    }
}

private final class FailingMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: "DuckAiNativeStorageContainerMigrationTests", code: -1)
    }
}

private final class FailingRemoveFileManager: FileManager {
    override func removeItem(at URL: URL) throws {
        throw NSError(domain: "DuckAiNativeStorageContainerMigrationTests", code: -2)
    }
}

/// Lets `moveItem` and directory creation succeed but rejects `setAttributes`
/// so `applyDefaultFileProtection` records a failure on every path.
private final class FailingSetAttributesFileManager: FileManager {
    static let errorDomain = "DuckAiNativeStorageContainerMigrationTests.setAttributes"
    static let errorCode = -3

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        throw NSError(domain: Self.errorDomain, code: Self.errorCode)
    }
}
