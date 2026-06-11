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

import Persistence
import PersistenceTestingUtils
import XCTest
@testable import DuckDuckGo

final class DuckAiNativeStorageContainerMigrationTests: XCTestCase {

    private var sandbox: URL!
    private var keyValueStore: MockKeyValueStore!
    private var pixelSpy: SpyContainerMigrationPixelFiring!
    private let migrationKey = "test.migration"
    private let label: DuckAiNativeStorageContainerMigrationLabel = .default

    private var migratedKey: String { migrationKey + ".migrated" }
    private var attemptsKey: String { migrationKey + ".attempts" }
    private var protectionAttemptsKey: String { migrationKey + ".protectionAttempts" }

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckAiNativeStorageContainerMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        keyValueStore = MockKeyValueStore()
        pixelSpy = SpyContainerMigrationPixelFiring()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
        keyValueStore = nil
        sandbox = nil
        pixelSpy = nil
        try super.tearDownWithError()
    }

    // MARK: - Happy paths

    func testWhenOldDirectoryDoesNotExistThenMigratedFlagIsSetAndNotNeededPixelFires() {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
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

        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("files.bin")), Data("files".utf8))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    func testWhenMigratedAndOldDoesNotExistThenMigrationIsNoOp() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        // Simulate completed migration: migrated flag set, oldURL absent.
        try? keyValueStore.set(true, forKey: migratedKey)

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    func testWhenMigrationSucceedsThenSecondCallIsNoOpAndPreservesAnyReappearedOldURL() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        // Re-create oldURL contents to verify the second call ignores them.
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("reappeared".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        // Migrated flag set → second call is a pure no-op.
        // We do NOT delete the re-created oldURL: it could be the only complete
        // copy of pre-upgrade data when the migrated flag was set via the
        // destination-conflict path, so we preserve it for recovery.
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("first".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "reappeared oldURL data must be preserved — we can't prove it's redundant")
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    // MARK: - Destination conflict (replaces blind orphan-removal)

    func testWhenBothOldAndNewExistWithDataThenDestinationConflictFiresAndOldIsPreserved() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        try Data("keep-me".utf8).write(to: newURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("keep-me".utf8))
        // Source must be preserved so the user's pre-upgrade data is recoverable.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "source data must be preserved for recovery when destination already has data")
        XCTAssertEqual(pixelSpy.firedEventNames, ["destinationConflict"])
    }

    func testWhenDestinationDirectoryIsEmptyThenItIsRemovedAndMoveSucceeds() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        // Empty newURL — e.g. scaffolding created by a prior excludeFromBackup call.
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)

        migrate(from: oldURL, to: newURL)

        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    // MARK: - Retry behavior (move failure)

    func testWhenMoveFailsThenAttemptIsRecordedAndOutcomeIsSkip() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)

        XCTAssertEqual(outcome, .skip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 1)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed"])
    }

    func testWhenMoveFailsRepeatedlyThenGivesUpAtMaxAttemptsWithoutSweepingSource() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("sensitive".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        var outcomes: [DuckAiNativeStorageContainerMigrationOutcome] = []
        for _ in 0..<3 {
            outcomes.append(migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3))
        }

        XCTAssertEqual(outcomes, [.skip, .skip, .skip])
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 3,
                       "attempts must stay at the cap so the next launch detects the exhausted budget")
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
        // Source data must NOT be deleted — accepting data loss in exchange for
        // privacy hygiene is the wrong trade-off for chat history.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "give-up sweep must not delete source data")
        XCTAssertFalse(keyValueStore.bool(forKey: migratedKey),
                       "migrated flag must NOT be set on give-up so retries can resume when conditions improve")
        // Returning .skip on give-up is what keeps the caller from creating an
        // empty destination DB — without that, the next launch's
        // destinationConflict path would claim the empty destination and
        // permanently orphan the user's pre-upgrade data at oldURL.
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path),
                       "give-up must leave destination untouched so the caller short-circuits")
    }

    func testWhenGaveUpAndNextLaunchSucceedsThenMigrationCompletes() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user-data".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        for _ in 0..<3 {
            migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)
        }

        // Disk pressure clears / locked storage unlocks / FS error transient
        // resolves. Next launch sees attempts at the cap with no migrated
        // flag and resets the retry budget before re-attempting the move.
        let recoveryOutcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(recoveryOutcome, .proceed)
        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("user-data".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp", "success"])
    }

    func testWhenMoveFailsThenSucceedsThenAttemptsAreClearedAndSuccessPixelFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("data".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let firstOutcome = migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)
        XCTAssertEqual(firstOutcome, .skip)
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 1)

        let secondOutcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(secondOutcome, .proceed)
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 0)
        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "success"])
    }

    // MARK: - Protected data gate

    func testWhenProtectedDataIsUnavailableThenOutcomeIsSkipAndStateUnchanged() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let outcome = migrate(from: oldURL, to: newURL, isProtectedDataAvailable: { false })

        XCTAssertEqual(outcome, .skip)
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 0,
                       "retry counter must not be burned by a locked-device launch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["protectedDataUnavailable"])
    }

    /// Without the up-front kv-store sanity check, the `try?` computed
    /// properties below silently fall back to defaults and the migration
    /// proceeds — likely landing in `notNeeded` (when oldURL is absent) or
    /// `destinationConflict` (once the destination has data). Deferring on
    /// unhealthy reads keeps the source on disk and gives the next launch a
    /// chance to recover with a healthy store.
    func testWhenKeyValueStoreReadFailsThenMigrationDefersWithoutMutatingState() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        let failingStore = FailingReadKeyValueStore()

        let outcome = DuckAiNativeStorageContainerMigration(
            oldURL: oldURL,
            newURL: newURL,
            migrationKey: migrationKey,
            label: label,
            keyValueStore: failingStore,
            pixelFiring: pixelSpy,
            isProtectedDataAvailable: { true },
            protectionDispatcher: { $0() }
        ).run()

        XCTAssertEqual(outcome, .skip)
        XCTAssertEqual(pixelSpy.firedEventNames, ["keyValueStoreReadFailed"])
        XCTAssertEqual((pixelSpy.lastKeyValueStoreReadError as NSError?)?.domain, FailingReadKeyValueStore.errorDomain)
        XCTAssertEqual((pixelSpy.lastKeyValueStoreReadError as NSError?)?.code, FailingReadKeyValueStore.errorCode)
        XCTAssertTrue(failingStore.writeCalls.isEmpty,
                      "unhealthy store must not be written to — no attempts counter increments, no migrated flag set")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path),
                       "destination must not be touched on a kv-store failure")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "source must be preserved on a kv-store failure")
    }

    func testWhenProtectedDataReturnsToAvailableThenMigrationCompletes() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let lockedOutcome = migrate(from: oldURL, to: newURL, isProtectedDataAvailable: { false })
        XCTAssertEqual(lockedOutcome, .skip)
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 0)

        let unlockedOutcome = migrate(from: oldURL, to: newURL, isProtectedDataAvailable: { true })

        XCTAssertEqual(unlockedOutcome, .proceed)
        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(pixelSpy.firedEventNames, ["protectedDataUnavailable", "success"])
    }

    // MARK: - Exhausted retry budget reset

    func testWhenAttemptsAreAtCapWithoutMigratedFlagThenBudgetResetsAndMigrationRuns() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        // Simulate the post-gaveUp state: attempts pegged at the cap, no migrated flag.
        try? keyValueStore.set(3, forKey: attemptsKey)
        try? keyValueStore.set(3, forKey: protectionAttemptsKey)

        migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("user".utf8))
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 0)
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    func testWhenAttemptsAreAtCapWithMigratedFlagThenBudgetIsNotReset() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try? keyValueStore.set(true, forKey: migratedKey)
        try? keyValueStore.set(3, forKey: attemptsKey)

        migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 3,
                       "migrated state must not touch the retry counter")
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    // MARK: - Migrated-flag steady state

    func testWhenMigratedAndOldStillExistsThenMigrationIsNoOpAndOldIsPreserved() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try? keyValueStore.set(true, forKey: migratedKey)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("preserved".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        // Migrated state must NOT delete oldURL. After the destination
        // conflict path runs, oldURL can be the only complete copy.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "oldURL data must be preserved once migrated flag is set")
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    /// Fire-mode stores DBs in `<UUID>/chats.db` subdirectories rather than at
    /// the destination root, so a regression in `destinationHasData` that only
    /// looked for `chats.db` at the root would silently mis-classify a populated
    /// fire-mode container as empty scaffolding and `removeItem` it before the
    /// next move attempt.
    func testWhenFireModeDestinationHasUUIDSubdirectoryThenDestinationConflictFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi-fireMode")
        let newURL = sandbox.appendingPathComponent("new/DuckAi-fireMode")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        // Stage fire-mode shape at the destination: <UUID>/chats.db, no
        // chats.db at the root.
        let uuidSubdir = newURL.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: uuidSubdir, withIntermediateDirectories: true)
        try Data("foreign".utf8).write(to: uuidSubdir.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL, label: .fireMode)

        XCTAssertEqual(pixelSpy.firedEventNames, ["destinationConflict"],
                       "destinationHasData must detect <UUID>/chats.db, not only chats.db at the root")
        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "oldURL must survive — the foreign fire-mode destination may not be a complete copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: uuidSubdir.appendingPathComponent("chats.db").path),
                      "foreign fire-mode contents must not be wiped")
    }

    func testWhenForeignDataIsPresentAtDestinationWithoutMigratedFlagThenDestinationConflictFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        // The migration's own give-up path returns .skip and never leaves
        // anything at newURL, so this state is only reachable when some external
        // source (sibling process, OS-level sync, manual data drop) populates
        // the destination before our migration runs. Stage that here: foreign
        // chats.db at newURL, complete copy still at oldURL.
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("foreign".utf8).write(to: newURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        // The standard flow takes the destinationConflict path, claims newURL
        // going forward, and preserves oldURL so the user's pre-upgrade data
        // remains on disk.
        XCTAssertEqual(pixelSpy.firedEventNames, ["destinationConflict"])
        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "oldURL must survive — the foreign destination may not be a complete copy")
        XCTAssertEqual(try Data(contentsOf: oldURL.appendingPathComponent("chats.db")), Data("complete".utf8))
    }

    // MARK: - File protection failure surfacing

    func testWhenMoveSucceedsButSetAttributesFailsThenSuccessAndProtectionFailedBothFire() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)

        XCTAssertEqual(outcome, .proceed)
        XCTAssertTrue(keyValueStore.bool(forKey: migratedKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed"])
        XCTAssertEqual((pixelSpy.lastProtectionFailedError as NSError?)?.domain, FailingSetAttributesFileManager.errorDomain)
        XCTAssertEqual((pixelSpy.lastProtectionFailedError as NSError?)?.code, FailingSetAttributesFileManager.errorCode)
        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey), 1,
                       "protection retry counter must reflect the single failed attempt")
    }

    func testWhenProtectionFailsThenRetriedOnSubsequentLaunchAndSucceedsThenProtectionIsDone() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)
        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey), 1)

        migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey), 3,
                       "successful apply must set the counter to the done sentinel (maxAttempts)")
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed"])
    }

    func testWhenProtectionFailsRepeatedlyThenGivesUpAtMaxAttemptsAndStopsFiringPixel() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        for _ in 0..<3 {
            migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)
        }
        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey), 3,
                       "counter sits at the done sentinel once the cap is reached")
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed", "protectionFailed", "protectionFailed"])

        migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed", "protectionFailed", "protectionFailed"])
    }

    func testWhenMigrationIsNotNeededThenProtectionIsMarkedDoneWithoutEnumeratingFiles() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")

        migrate(from: oldURL, to: newURL)

        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey), DuckAiNativeStorageContainerMigration.defaultMaxAttempts)
        XCTAssertEqual(pixelSpy.firedEventNames, ["notNeeded"])
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

    func testWhenApplyDefaultFileProtectionRootSucceedsButChildFailsThenReturnsChildError() throws {
        let url = sandbox.appendingPathComponent("DuckAi")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: url.appendingPathComponent("chats.db"))

        let fileManager = FailingSetAttributesOnChildFileManager(rootPath: url.path)
        let error = DuckAiNativeStorageContainerMigration.applyDefaultFileProtection(at: url, fileManager: fileManager)

        XCTAssertEqual((error as NSError?)?.domain, FailingSetAttributesOnChildFileManager.errorDomain,
                       "child-only failure must surface as a non-nil error")
        XCTAssertEqual((error as NSError?)?.code, FailingSetAttributesOnChildFileManager.errorCode)
    }

    func testWhenApplyDefaultFileProtectionEnumeratorReturnsNilThenReturnsError() throws {
        let url = sandbox.appendingPathComponent("nonexistent-directory")
        // No directory created; default FileManager.enumerator(at:) returns nil
        // because the path can't be opened. setAttributes on the root will also
        // fail, so we should get a non-nil error rather than a false success.

        let error = DuckAiNativeStorageContainerMigration.applyDefaultFileProtection(at: url)

        XCTAssertNotNil(error, "nil enumerator must not be treated as success")
    }

    // MARK: - Protection dispatch

    /// Pins the contract that `ensureProtection`'s recursive setAttributes
    /// walk is deferred off the launch thread. The synchronous return path
    /// must complete before the protection work runs — otherwise a large
    /// `files/` tree could push past the iOS launch watchdog.
    func testWhenMoveSucceedsThenProtectionWorkIsDispatched() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        var capturedWork: (() -> Void)?
        let outcome = DuckAiNativeStorageContainerMigration(
            oldURL: oldURL,
            newURL: newURL,
            migrationKey: migrationKey,
            label: label,
            keyValueStore: keyValueStore,
            pixelFiring: pixelSpy,
            isProtectedDataAvailable: { true },
            protectionDispatcher: { capturedWork = $0 }
        ).run()

        XCTAssertEqual(outcome, .proceed)
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"],
                       "success fires synchronously; protection pixel only fires after the dispatched work runs")
        XCTAssertNotNil(capturedWork,
                        "protection work must be dispatched, not executed inline on the launch thread")
        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey), 0,
                       "protection counter must not be touched until the dispatched work runs")

        capturedWork?()

        XCTAssertEqual(keyValueStore.integer(forKey: protectionAttemptsKey),
                       DuckAiNativeStorageContainerMigration.defaultMaxAttempts,
                       "after the dispatched work completes, the counter is set to the done sentinel")
    }

    // MARK: - excludeFromBackup pixel

    func testWhenExcludeFromBackupSucceedsThenNoPixelFires() {
        let url = sandbox.appendingPathComponent("DuckAi")

        DuckAiNativeStorageContainerMigration.excludeFromBackup(url, label: .default, pixelFiring: pixelSpy)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    func testWhenExcludeFromBackupFailsThenPixelFires() {
        let url = sandbox.appendingPathComponent("DuckAi")

        DuckAiNativeStorageContainerMigration.excludeFromBackup(url,
                                                                label: .default,
                                                                pixelFiring: pixelSpy,
                                                                fileManager: FailingCreateDirectoryFileManager())

        XCTAssertEqual(pixelSpy.firedEventNames, ["excludeFromBackupFailed"])
    }

    // MARK: - maxAttempts clamp

    func testWhenMaxAttemptsIsZeroThenClampedToOneAndGivesUpOnFirstFailure() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 0)

        XCTAssertEqual(outcome, .skip, "maxAttempts clamped to 1 triggers gaveUp on the first failure")
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 1,
                       "attempts must be left at the clamped cap so the next launch resets the budget")
        XCTAssertEqual(pixelSpy.firedEventNames, ["gaveUp"])
        // Even at maxAttempts=0 (clamped), source must be preserved.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "source data must be preserved even at the clamped lower bound")
    }

    func testWhenMaxAttemptsIsNegativeThenClampedToOne() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: -5)

        XCTAssertEqual(outcome, .skip)
        XCTAssertEqual(pixelSpy.firedEventNames, ["gaveUp"])
    }

    // MARK: - Caller-contract regression (factory pattern)

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
                DuckAiNativeStorageContainerMigration.excludeFromBackup(newURL,
                                                                        label: .default,
                                                                        pixelFiring: self.pixelSpy)
            }
        )

        XCTAssertNil(result, "factory must short-circuit when migration returns .skip")
        XCTAssertFalse(handlerCreated, "handler creation must be skipped after a failed move")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
        XCTAssertFalse(keyValueStore.bool(forKey: migratedKey))
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
                DuckAiNativeStorageContainerMigration.excludeFromBackup(newURL,
                                                                        label: .default,
                                                                        pixelFiring: self.pixelSpy)
            }
        )

        XCTAssertNotNil(secondLaunch)
        XCTAssertTrue(secondLaunchHandlerCreated)
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("user-chats".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "success"])
    }

    func testGivenThreeFailedMoveLaunchesWhenFourthLaunchSucceedsThenNoDestinationConflict() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user-chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        for _ in 0..<3 {
            let launch = runFactory(
                oldURL: oldURL,
                newURL: newURL,
                fileManager: FailingMoveFileManager(),
                createHandler: {
                    XCTFail("createHandler must never run when the migration short-circuits on .skip")
                }
            )
            XCTAssertNil(launch, "factory must short-circuit on .skip for every failing launch")
            XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path),
                           "destination must stay absent across all failing launches — its presence is the orphan precondition")
        }
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 3)
        XCTAssertFalse(keyValueStore.bool(forKey: migratedKey))

        var recoveryHandlerCreated = false
        let recovery = runFactory(
            oldURL: oldURL,
            newURL: newURL,
            fileManager: .default,
            createHandler: {
                recoveryHandlerCreated = true
                DuckAiNativeStorageContainerMigration.excludeFromBackup(newURL,
                                                                        label: .default,
                                                                        pixelFiring: self.pixelSpy)
            }
        )

        XCTAssertNotNil(recovery)
        XCTAssertTrue(recoveryHandlerCreated)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp", "success"],
                       "recovery must take the normal success path — destinationConflict would prove the orphan bug regressed")
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("user-chats".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path),
                       "successful recovery moves oldURL, so it is consumed normally")
    }

    func testGivenProtectedDataUnavailableWhenFactoryRunsThenDestinationStaysAbsent() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user-chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        var handlerCreated = false
        let result = runFactory(
            oldURL: oldURL,
            newURL: newURL,
            fileManager: .default,
            isProtectedDataAvailable: { false },
            createHandler: {
                handlerCreated = true
            }
        )

        XCTAssertNil(result, "locked-device launch must not construct a handler")
        XCTAssertFalse(handlerCreated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path),
                       "locked-device launch must not create destination — otherwise next launch sees it as orphan")
        XCTAssertEqual(keyValueStore.integer(forKey: attemptsKey), 0,
                       "locked-device launch must not consume the retry budget")
    }

    // MARK: - Helpers

    @discardableResult
    private func migrate(from oldURL: URL,
                         to newURL: URL,
                         label: DuckAiNativeStorageContainerMigrationLabel? = nil,
                         fileManager: FileManager = .default,
                         isProtectedDataAvailable: @escaping () -> Bool = { true },
                         maxAttempts: Int = DuckAiNativeStorageContainerMigration.defaultMaxAttempts,
                         protectionDispatcher: @escaping DuckAiNativeStorageContainerMigration.ProtectionDispatcher = { $0() }) -> DuckAiNativeStorageContainerMigrationOutcome {
        DuckAiNativeStorageContainerMigration(
            oldURL: oldURL,
            newURL: newURL,
            migrationKey: migrationKey,
            label: label ?? self.label,
            keyValueStore: keyValueStore,
            fileManager: fileManager,
            pixelFiring: pixelSpy,
            isProtectedDataAvailable: isProtectedDataAvailable,
            maxAttempts: maxAttempts,
            protectionDispatcher: protectionDispatcher
        ).run()
    }

    /// Mirrors the caller pattern in `Launching.makeNativeStorageHandler` and
    /// `FireModeNativeStorageController.init`: bail out on `.skip`, otherwise
    /// create the destination and open a handler. Returns a non-nil sentinel
    /// when a handler would have been created.
    private func runFactory(oldURL: URL,
                            newURL: URL,
                            fileManager: FileManager,
                            isProtectedDataAvailable: @escaping () -> Bool = { true },
                            createHandler: () -> Void) -> AnyObject? {
        let outcome = migrate(from: oldURL,
                              to: newURL,
                              fileManager: fileManager,
                              isProtectedDataAvailable: isProtectedDataAvailable)
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
    private(set) var lastExcludeFromBackupError: Error?
    private(set) var lastKeyValueStoreReadError: Error?

    func fire(_ event: DuckAiNativeStorageContainerMigrationEvent) {
        switch event {
        case .notNeeded: firedEventNames.append("notNeeded")
        case .success: firedEventNames.append("success")
        case .attemptFailed: firedEventNames.append("attemptFailed")
        case .gaveUp: firedEventNames.append("gaveUp")
        case .protectionFailed(_, let error):
            firedEventNames.append("protectionFailed")
            lastProtectionFailedError = error
        case .destinationConflict: firedEventNames.append("destinationConflict")
        case .excludeFromBackupFailed(_, let error):
            firedEventNames.append("excludeFromBackupFailed")
            lastExcludeFromBackupError = error
        case .protectedDataUnavailable: firedEventNames.append("protectedDataUnavailable")
        case .keyValueStoreReadFailed(_, let error):
            firedEventNames.append("keyValueStoreReadFailed")
            lastKeyValueStoreReadError = error
        }
    }
}

/// Throws on every `object(forKey:)` read, accepts writes. Mirrors a
/// genuinely-broken store at the boundary the migration uses.
private final class FailingReadKeyValueStore: ThrowingKeyValueStoring {
    static let errorDomain = "DuckAiNativeStorageContainerMigrationTests.kvStoreRead"
    static let errorCode = -7

    private(set) var writeCalls: [(key: String, value: Any?)] = []

    func object(forKey defaultName: String) throws -> Any? {
        throw NSError(domain: Self.errorDomain, code: Self.errorCode)
    }

    func set(_ value: Any?, forKey defaultName: String) throws {
        writeCalls.append((defaultName, value))
    }

    func removeObject(forKey defaultName: String) throws {
        writeCalls.append((defaultName, nil))
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

/// Succeeds on `setAttributes` for the root path and rejects it for every
/// descendant — exercises the child-only branch of `applyDefaultFileProtection`.
private final class FailingSetAttributesOnChildFileManager: FileManager {
    static let errorDomain = "DuckAiNativeStorageContainerMigrationTests.setAttributesOnChild"
    static let errorCode = -5

    private let rootPath: String

    init(rootPath: String) {
        self.rootPath = rootPath
        super.init()
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if path == rootPath { return }
        throw NSError(domain: Self.errorDomain, code: Self.errorCode)
    }
}

/// Rejects `createDirectory(at:withIntermediateDirectories:)` so
/// `excludeFromBackup` surfaces the failure via pixel.
private final class FailingCreateDirectoryFileManager: FileManager {
    override func createDirectory(at url: URL,
                                  withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        throw NSError(domain: "DuckAiNativeStorageContainerMigrationTests.createDirectory", code: -4)
    }
}

private extension MockKeyValueStore {
    func integer(forKey key: String) -> Int { object(forKey: key) as? Int ?? 0 }
    func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
}
