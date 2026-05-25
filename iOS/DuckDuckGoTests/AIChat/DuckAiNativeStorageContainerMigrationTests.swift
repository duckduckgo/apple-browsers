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
    private var protectionAppliedKey: String { migrationKey + ".protectionApplied" }
    private var protectionAttemptsKey: String { migrationKey + ".protectionAttempts" }

    private func markerURL(forNew newURL: URL) -> URL {
        newURL.deletingLastPathComponent()
            .appendingPathComponent(".\(migrationKey).migrated")
    }

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

    func testWhenOldDirectoryDoesNotExistThenMarkerIsWrittenAndNotNeededPixelFires() {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("files.bin")), Data("files".utf8))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    func testWhenMarkerExistsAndOldDoesNotExistThenMigrationIsNoOp() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        // Simulate completed migration: marker present, oldURL absent.
        try FileManager.default.createDirectory(at: markerURL(forNew: newURL).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: markerURL(forNew: newURL))
        userDefaults.set(true, forKey: doneKey)

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

        // Marker exists → second call is a pure no-op.
        // We do NOT delete the re-created oldURL: it could be the only complete
        // copy of pre-upgrade data when the marker was written via the
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

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
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

        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    // MARK: - Retry behavior (move failure)

    func testWhenMoveFailsThenAttemptIsRecordedAndDoneFlagNotSetAndOutcomeIsSkip() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)

        let outcome = migrate(from: oldURL, to: newURL, fileManager: FailingMoveFileManager(), maxAttempts: 3)

        XCTAssertEqual(outcome, .skip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
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

        XCTAssertEqual(outcomes, [.skip, .skip, .proceed])
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 3)
        XCTAssertEqual(pixelSpy.firedEventNames, ["attemptFailed", "attemptFailed", "gaveUp"])
        // Source data must NOT be deleted — accepting data loss in exchange for
        // privacy hygiene is the wrong trade-off for chat history.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "give-up sweep must not delete source data")
        // No marker yet — a future launch can re-try via the legacy transition
        // if conditions improve.
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path),
                       "marker must NOT be written on give-up so retries can resume when conditions improve")
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
        // resolves. Next launch with a working FileManager should succeed via
        // the legacy doneKey transition.
        let recoveryOutcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(recoveryOutcome, .proceed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
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
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 1)
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))

        let secondOutcome = migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertEqual(secondOutcome, .proceed)
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
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
        XCTAssertFalse(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 0,
                       "retry counter must not be burned by a locked-device launch")
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["protectedDataUnavailable"])
    }

    func testWhenProtectedDataReturnsToAvailableThenMigrationCompletes() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("user".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        let lockedOutcome = migrate(from: oldURL, to: newURL, isProtectedDataAvailable: { false })
        XCTAssertEqual(lockedOutcome, .skip)
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 0)

        let unlockedOutcome = migrate(from: oldURL, to: newURL, isProtectedDataAvailable: { true })

        XCTAssertEqual(unlockedOutcome, .proceed)
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(pixelSpy.firedEventNames, ["protectedDataUnavailable", "success"])
    }

    // MARK: - Legacy doneKey transition (iCloud restore + pre-marker upgrades)

    func testWhenLegacyDoneFlagSetAndDestinationHasDataThenMarkerIsWrittenAndCallIsNoOp() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        // Simulate a user who completed migration on a pre-marker build:
        // doneKey set, oldURL absent, newURL contains chats.db, no marker yet.
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("migrated".utf8).write(to: newURL.appendingPathComponent("chats.db"))
        userDefaults.set(true, forKey: doneKey)

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path),
                      "marker should be written on first launch under the new code")
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty,
                      "no migration events should fire for a no-op transition")
    }

    func testWhenLegacyDoneFlagSetButDestinationEmptyAndSourceHasDataThenStateResetsAndMigrationRuns() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        // Simulate iCloud restore: doneKey survived backup, App Group oldURL
        // was restored, but Application Support newURL was excluded from backup
        // so the destination is empty. The migration must re-run.
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("restored".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        userDefaults.set(true, forKey: doneKey)

        migrate(from: oldURL, to: newURL)

        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("restored".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success"])
    }

    func testWhenLegacyDoneFlagSetAndNeitherSourceNorDestinationHasDataThenMarkerIsWritten() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        userDefaults.set(true, forKey: doneKey)

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    // MARK: - Marker-present steady state

    func testWhenMarkerExistsAndOldStillExistsThenMigrationIsNoOpAndOldIsPreserved() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: markerURL(forNew: newURL).deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: markerURL(forNew: newURL))
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("preserved".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL)

        // Marker-present state must NOT delete oldURL. After the destination
        // conflict path runs, oldURL can be the only complete copy.
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "oldURL data must be preserved once marker exists")
        XCTAssertTrue(pixelSpy.firedEventNames.isEmpty)
    }

    func testWhenGaveUpLeftPartialDestinationAndNextLaunchRunsThenDestinationConflictFires() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: oldURL.appendingPathComponent("chats.db"))
        // Simulate the post-gaveUp + partial-copy state without writing a marker:
        // newURL has a partial chats.db, oldURL still has the complete copy,
        // doneKey was set when migration gave up. No marker.
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: newURL.appendingPathComponent("chats.db"))
        userDefaults.set(true, forKey: doneKey)
        userDefaults.set(3, forKey: attemptsKey)

        migrate(from: oldURL, to: newURL)

        // Legacy transition sees `oldExists` and resets state. The standard
        // flow then takes the destinationConflict path, writes the marker,
        // and preserves both sides so the complete oldURL data remains
        // recoverable.
        XCTAssertEqual(pixelSpy.firedEventNames, ["destinationConflict"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL(forNew: newURL).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.appendingPathComponent("chats.db").path),
                      "post-gaveUp source must survive — newURL might be a partial copy")
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
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
        XCTAssertEqual(try Data(contentsOf: newURL.appendingPathComponent("chats.db")), Data("chats".utf8))
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed"])
        XCTAssertEqual((pixelSpy.lastProtectionFailedError as NSError?)?.domain, FailingSetAttributesFileManager.errorDomain)
        XCTAssertEqual((pixelSpy.lastProtectionFailedError as NSError?)?.code, FailingSetAttributesFileManager.errorCode)
        XCTAssertFalse(userDefaults.bool(forKey: protectionAppliedKey))
        XCTAssertEqual(userDefaults.integer(forKey: protectionAttemptsKey), 1)
    }

    func testWhenProtectionFailsThenRetriedOnSubsequentLaunchAndSucceedsThenProtectionAppliedIsSet() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try Data("chats".utf8).write(to: oldURL.appendingPathComponent("chats.db"))

        migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)
        XCTAssertFalse(userDefaults.bool(forKey: protectionAppliedKey))

        migrate(from: oldURL, to: newURL, maxAttempts: 3)

        XCTAssertTrue(userDefaults.bool(forKey: protectionAppliedKey))
        XCTAssertEqual(userDefaults.integer(forKey: protectionAttemptsKey), 0)
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
        XCTAssertTrue(userDefaults.bool(forKey: protectionAppliedKey))
        XCTAssertEqual(userDefaults.integer(forKey: protectionAttemptsKey), 0,
                       "protectionAttempts should be cleared when the cap marks applied=true")
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed", "protectionFailed", "protectionFailed"])

        migrate(from: oldURL, to: newURL, fileManager: FailingSetAttributesFileManager(), maxAttempts: 3)
        XCTAssertEqual(pixelSpy.firedEventNames, ["success", "protectionFailed", "protectionFailed", "protectionFailed"])
    }

    func testWhenMigrationIsNotNeededThenProtectionAppliedIsSetWithoutEnumeratingFiles() throws {
        let oldURL = sandbox.appendingPathComponent("old/DuckAi")
        let newURL = sandbox.appendingPathComponent("new/DuckAi")

        migrate(from: oldURL, to: newURL)

        XCTAssertTrue(userDefaults.bool(forKey: protectionAppliedKey))
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

    func testWhenApplyDefaultFileProtectionEnumeratorReturnsNilThenReturnsError() throws {
        let url = sandbox.appendingPathComponent("nonexistent-directory")
        // No directory created; default FileManager.enumerator(at:) returns nil
        // because the path can't be opened. setAttributes on the root will also
        // fail, so we should get a non-nil error rather than a false success.

        let error = DuckAiNativeStorageContainerMigration.applyDefaultFileProtection(at: url)

        XCTAssertNotNil(error, "nil enumerator must not be treated as success")
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

        XCTAssertEqual(outcome, .proceed, "maxAttempts clamped to 1 triggers gaveUp on the first failure")
        XCTAssertTrue(userDefaults.bool(forKey: doneKey))
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

        XCTAssertEqual(outcome, .proceed)
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
        XCTAssertEqual(userDefaults.integer(forKey: attemptsKey), 0,
                       "locked-device launch must not consume the retry budget")
    }

    // MARK: - Helpers

    @discardableResult
    private func migrate(from oldURL: URL,
                         to newURL: URL,
                         fileManager: FileManager = .default,
                         isProtectedDataAvailable: () -> Bool = { true },
                         maxAttempts: Int = DuckAiNativeStorageContainerMigration.defaultMaxAttempts) -> DuckAiNativeStorageContainerMigrationOutcome {
        DuckAiNativeStorageContainerMigration.migrateIfNeeded(
            from: oldURL,
            to: newURL,
            migrationKey: migrationKey,
            label: label,
            userDefaults: userDefaults,
            fileManager: fileManager,
            pixelFiring: pixelSpy,
            isProtectedDataAvailable: isProtectedDataAvailable,
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
                            isProtectedDataAvailable: () -> Bool = { true },
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
        case .destinationConflict: firedEventNames.append("destinationConflict")
        case .excludeFromBackupFailed(_, let error):
            firedEventNames.append("excludeFromBackupFailed")
            lastExcludeFromBackupError = error
        case .protectedDataUnavailable: firedEventNames.append("protectedDataUnavailable")
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

/// Rejects `createDirectory(at:withIntermediateDirectories:)` so
/// `excludeFromBackup` surfaces the failure via pixel.
private final class FailingCreateDirectoryFileManager: FileManager {
    override func createDirectory(at url: URL,
                                  withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        throw NSError(domain: "DuckAiNativeStorageContainerMigrationTests.createDirectory", code: -4)
    }
}
