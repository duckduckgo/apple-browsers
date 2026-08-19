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

    func testClearSnapshotsWhenSnapshotsDirectoryIsMissingDoesNothing() async {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        let cleaner = AppSwitcherSnapshotCleaner(libraryDirectoryOverride: libraryDirectory)
        await cleaner.clearSnapshots()

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotsDirectory.path))
    }

    func testClearSnapshotsContinuesAfterAnItemCannotBeRemoved() async throws {
        let libraryDirectory = makeTemporaryLibraryDirectory()
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }

        let snapshotsDirectory = libraryDirectory
            .appendingPathComponent("SplashBoard", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        let protectedSceneDirectory = snapshotsDirectory.appendingPathComponent("protected-scene", isDirectory: true)
        let removableSceneDirectory = snapshotsDirectory.appendingPathComponent("removable-scene", isDirectory: true)
        try FileManager.default.createDirectory(at: protectedSceneDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: removableSceneDirectory, withIntermediateDirectories: true)

        let fileManager = SelectivelyFailingFileManager(failingItemName: protectedSceneDirectory.lastPathComponent)
        let cleaner = AppSwitcherSnapshotCleaner(fileManager: fileManager, libraryDirectoryOverride: libraryDirectory)
        await cleaner.clearSnapshots()

        XCTAssertTrue(fileManager.fileExists(atPath: protectedSceneDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: removableSceneDirectory.path))
        XCTAssertTrue(fileManager.fileExists(atPath: snapshotsDirectory.path))
        XCTAssertEqual(fileManager.removalAttempts.map(\.lastPathComponent), ["protected-scene", "removable-scene"])
    }

    private func makeTemporaryLibraryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSwitcherSnapshotCleanerTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class SelectivelyFailingFileManager: FileManager, @unchecked Sendable {

    private let failingItemName: String
    private(set) var removalAttempts: [URL] = []

    init(failingItemName: String) {
        self.failingItemName = failingItemName
        super.init()
    }

    override func contentsOfDirectory(at url: URL,
                                      includingPropertiesForKeys keys: [URLResourceKey]?,
                                      options mask: DirectoryEnumerationOptions = []) throws -> [URL] {
        var items = try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
        guard let failingItemIndex = items.firstIndex(where: { $0.lastPathComponent == failingItemName }) else {
            return items
        }
        let failingItem = items.remove(at: failingItemIndex)
        return [failingItem] + items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    override func removeItem(at URL: URL) throws {
        removalAttempts.append(URL)
        guard URL.lastPathComponent != failingItemName else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
        }
        try super.removeItem(at: URL)
    }
}
