//
//  AppSwitcherSnapshotCleanerTests.swift
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

import Foundation
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

final class AppSwitcherSnapshotCleanerTests: XCTestCase {

    func testClearSnapshotsRemovesContentsAndKeepsSnapshotsDirectory() async throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        let sceneDirectory = snapshotsDirectory.appendingPathComponent("scene", isDirectory: true)
        try FileManager.default.createDirectory(at: sceneDirectory, withIntermediateDirectories: true)
        try Data("snapshot".utf8).write(to: sceneDirectory.appendingPathComponent("portrait.ktx"))

        let cleaner = AppSwitcherSnapshotCleaner(libraryDirectoryOverride: libraryDirectory)
        await cleaner.clearSnapshots()

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotsDirectory.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: snapshotsDirectory,
                                                                   includingPropertiesForKeys: nil), [])
    }

    func testWhenSnapshotsDirectoryIsMissingThenNoFailurePixelIsFired() async throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        let splashBoardDirectory = libraryDirectory.appendingPathComponent("SplashBoard", isDirectory: true)
        try FileManager.default.createDirectory(at: splashBoardDirectory, withIntermediateDirectories: true)

        let pixelFiring = PixelKitMock()
        let cleaner = AppSwitcherSnapshotCleaner(libraryDirectoryOverride: libraryDirectory, pixelFiring: pixelFiring)
        await cleaner.clearSnapshots()

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotsDirectory.path))
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testWhenSnapshotsDirectoryCannotBeEnumeratedThenEnumerationFailurePixelIsFired() async throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        let pixelFiring = PixelKitMock()
        let cleaner = AppSwitcherSnapshotCleaner(fileManager: FailingEnumerationFileManager(),
                                                  libraryDirectoryOverride: libraryDirectory,
                                                  pixelFiring: pixelFiring)

        await cleaner.clearSnapshots()

        let fireCall = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(fireCall.pixel.name, "app-switcher_snapshot_enumeration_failed")
        XCTAssertEqual(fireCall.pixel.error?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(fireCall.pixel.error?.code, CocoaError.fileReadNoPermission.rawValue)
        XCTAssertEqual(fireCall.pixel.platformSuffixPolicy, .legacyOmitted)
        XCTAssertEqual(fireCall.frequency, .dailyAndCount)
    }

    func testWhenSnapshotItemIsAlreadyGoneThenNoRemovalFailurePixelIsFired() async throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        let snapshotItem = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
            .appendingPathComponent("scene", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotItem, withIntermediateDirectories: true)

        let pixelFiring = PixelKitMock()
        let cleaner = AppSwitcherSnapshotCleaner(fileManager: AlreadyRemovedFileManager(),
                                                  libraryDirectoryOverride: libraryDirectory,
                                                  pixelFiring: pixelFiring)
        await cleaner.clearSnapshots()

        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotItem.path))
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testClearSnapshotsContinuesAfterItemsCannotBeRemovedAndFiresOneRemovalFailurePixel() async throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        let firstSceneDirectory = snapshotsDirectory.appendingPathComponent("scene-1", isDirectory: true)
        let secondSceneDirectory = snapshotsDirectory.appendingPathComponent("scene-2", isDirectory: true)
        try FileManager.default.createDirectory(at: firstSceneDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSceneDirectory, withIntermediateDirectories: true)

        let fileManager = FailingRemovalFileManager()
        let pixelFiring = PixelKitMock()
        let cleaner = AppSwitcherSnapshotCleaner(fileManager: fileManager,
                                                  libraryDirectoryOverride: libraryDirectory,
                                                  pixelFiring: pixelFiring)
        await cleaner.clearSnapshots()

        XCTAssertEqual(Set(fileManager.removalAttempts), Set([firstSceneDirectory, secondSceneDirectory]))
        XCTAssertTrue(fileManager.fileExists(atPath: firstSceneDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: secondSceneDirectory.path))

        let fireCall = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(fireCall.pixel.name, "app-switcher_snapshot_removal_failed")
        XCTAssertEqual(fireCall.pixel.error?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(fireCall.pixel.error?.code, CocoaError.fileWriteNoPermission.rawValue)
        XCTAssertEqual(fireCall.pixel.platformSuffixPolicy, .standard)
        XCTAssertEqual(fireCall.frequency, .dailyAndCount)
    }

    private func makeTemporaryLibraryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSwitcherSnapshotCleanerTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class FailingEnumerationFileManager: FileManager, @unchecked Sendable {

    override func contentsOfDirectory(at url: URL,
                                      includingPropertiesForKeys keys: [URLResourceKey]?,
                                      options mask: FileManager.DirectoryEnumerationOptions = []) throws -> [URL] {
        throw CocoaError(.fileReadNoPermission)
    }
}

private final class AlreadyRemovedFileManager: FileManager, @unchecked Sendable {

    override func removeItem(at URL: URL) throws {
        try super.removeItem(at: URL)
        try super.removeItem(at: URL)
    }
}

private final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    private(set) var removalAttempts: [URL] = []

    override func removeItem(at URL: URL) throws {
        removalAttempts.append(URL)
        throw CocoaError(.fileWriteNoPermission)
    }
}
