//
//  AIChatIndexedDBBlobCleanerTests.swift
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

import WebKit
import XCTest
@testable import AIChat

final class AIChatIndexedDBBlobCleanerTests: XCTestCase {

    private let fileManager = FileManager.default
    private var storageDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storageDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AIChatIndexedDBBlobCleanerTests-\(UUID().uuidString)")
            .appendingPathComponent("Default")
        try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: storageDirectory.deletingLastPathComponent())
        storageDirectory = nil
        try super.tearDownWithError()
    }

    private func makeSUT(hosts: Set<String> = AIChatIndexedDBBlobCleaner.duckAiHosts) -> AIChatIndexedDBBlobCleaner {
        AIChatIndexedDBBlobCleaner(originStorageDirectories: [storageDirectory], hosts: hosts, fileManager: fileManager)
    }

    // MARK: - Removal

    func testWhenOriginIsDuckAiThenAllBlobFilesAreRemovedAndDatabaseIsKept() async throws {
        let database = try makeOrigin(host: "duck.ai", blobFiles: ["1.blob", "2.blob", "17.blob"])

        let result = await makeSUT().removeAllBlobFiles()

        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(try blobFiles(in: database), [])
        XCTAssertTrue(fileManager.fileExists(atPath: database.appendingPathComponent("IndexedDB.sqlite3").path))
        XCTAssertTrue(fileManager.fileExists(atPath: database.appendingPathComponent("IndexedDB.sqlite3-wal").path))
    }

    func testWhenOriginIsDuckDuckGoThenBlobFilesAreRemoved() async throws {
        let database = try makeOrigin(host: "duckduckgo.com", blobFiles: ["1.blob"])

        _ = await makeSUT().removeAllBlobFiles()

        XCTAssertEqual(try blobFiles(in: database), [])
    }

    func testWhenOriginIsNotDuckAiThenBlobFilesAreKept() async throws {
        let other = try makeOrigin(host: "example.com", blobFiles: ["1.blob"])
        let subdomain = try makeOrigin(host: "internal.duck.ai", blobFiles: ["1.blob"])
        let http = try makeOrigin(scheme: "http", host: "duck.ai", blobFiles: ["1.blob"])

        let result = await makeSUT().removeAllBlobFiles()

        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(try blobFiles(in: other), ["1.blob"])
        XCTAssertEqual(try blobFiles(in: subdomain), ["1.blob"], "A length-prefixed match must not treat a subdomain as duck.ai")
        XCTAssertEqual(try blobFiles(in: http), ["1.blob"])
    }

    func testWhenOriginHasMultipleDatabasesThenBlobFilesInEachAreRemoved() async throws {
        let first = try makeOrigin(host: "duck.ai", blobFiles: ["1.blob"])
        let second = try makeDatabase(in: first.deletingLastPathComponent(), blobFiles: ["1.blob", "2.blob"])

        _ = await makeSUT().removeAllBlobFiles()

        XCTAssertEqual(try blobFiles(in: first), [])
        XCTAssertEqual(try blobFiles(in: second), [])
    }

    func testWhenOriginHasNoIndexedDBThenRemovalSucceeds() async throws {
        let originDirectory = storageDirectory.appendingPathComponent("hash").appendingPathComponent("hash")
        try fileManager.createDirectory(at: originDirectory, withIntermediateDirectories: true)
        try originData(scheme: "https", host: "duck.ai").write(to: originDirectory.appendingPathComponent("origin"))

        let result = await makeSUT().removeAllBlobFiles()

        XCTAssertNotNil(try? result.get())
    }

    func testWhenStorageDirectoryDoesNotExistThenRemovalSucceeds() async {
        let sut = AIChatIndexedDBBlobCleaner(originStorageDirectories: [storageDirectory.appendingPathComponent("missing")],
                                             fileManager: fileManager)

        let result = await sut.removeAllBlobFiles()

        XCTAssertNotNil(try? result.get())
    }

    // MARK: - Directory resolution

    func testWhenDataStoreIsDefaultThenDefaultOriginStorageDirectoriesAreResolvedForBothWebKitRoots() {
        let library = URL(fileURLWithPath: "/Library")

        let directories = AIChatIndexedDBBlobCleaner.originStorageDirectories(libraryDirectory: library,
                                                                             bundleIdentifier: "com.duckduckgo.test",
                                                                             dataStoreIdentifier: nil)

        XCTAssertEqual(directories.map(\.path), [
            "/Library/WebKit/WebsiteData/Default",
            "/Library/WebKit/com.duckduckgo.test/WebsiteData/Default"
        ])
    }

    func testWhenDataStoreHasIdentifierThenOriginsDirectoryUnderIdentifierIsResolved() throws {
        let library = URL(fileURLWithPath: "/Library")
        let identifier = try XCTUnwrap(UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000000"))

        let directories = AIChatIndexedDBBlobCleaner.originStorageDirectories(libraryDirectory: library,
                                                                             bundleIdentifier: nil,
                                                                             dataStoreIdentifier: identifier)

        XCTAssertEqual(Set(directories.map(\.path)), [
            "/Library/WebKit/WebsiteData/0A1B2C3D-0000-4000-8000-000000000000/Origins",
            "/Library/WebKit/WebsiteData/0a1b2c3d-0000-4000-8000-000000000000/Origins"
        ])
    }

    @MainActor
    func testWhenDataStoreIsNonPersistentThenNoDirectoriesAreResolved() {
        let directories = AIChatIndexedDBBlobCleaner.originStorageDirectories(for: .nonPersistent(), fileManager: fileManager)

        XCTAssertTrue(directories.isEmpty)
    }

    // MARK: - Origin file matching

    func testWhenOriginFileIsRealWebKitEncodingThenDuckAiIsMatched() {
        // Bytes as written by WebKit for https://duck.ai (top and opening origin).
        let data = Data([
            0x05, 0x00, 0x00, 0x00, 0x01, 0x68, 0x74, 0x74, 0x70, 0x73,
            0x07, 0x00, 0x00, 0x00, 0x01, 0x64, 0x75, 0x63, 0x6b, 0x2e, 0x61, 0x69, 0x00,
            0x05, 0x00, 0x00, 0x00, 0x01, 0x68, 0x74, 0x74, 0x70, 0x73,
            0x07, 0x00, 0x00, 0x00, 0x01, 0x64, 0x75, 0x63, 0x6b, 0x2e, 0x61, 0x69, 0x00
        ])

        XCTAssertTrue(AIChatIndexedDBBlobCleaner.isMatchingOrigin(data, hosts: ["duck.ai"]))
        XCTAssertFalse(AIChatIndexedDBBlobCleaner.isMatchingOrigin(data, hosts: ["duckduckgo.com"]))
    }

    // MARK: - Helpers

    /// Creates `<storage>/<hash>/<hash>/origin` plus one IndexedDB database directory; returns the database directory.
    private func makeOrigin(scheme: String = "https", host: String, blobFiles: [String]) throws -> URL {
        let hash = UUID().uuidString
        let originDirectory = storageDirectory.appendingPathComponent(hash).appendingPathComponent(hash)
        try fileManager.createDirectory(at: originDirectory, withIntermediateDirectories: true)
        try originData(scheme: scheme, host: host).write(to: originDirectory.appendingPathComponent("origin"))
        return try makeDatabase(in: originDirectory, blobFiles: blobFiles)
    }

    private func makeDatabase(in originDirectory: URL, blobFiles: [String]) throws -> URL {
        let database = originDirectory
            .appendingPathComponent("IndexedDB")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: database, withIntermediateDirectories: true)
        for file in blobFiles + ["IndexedDB.sqlite3", "IndexedDB.sqlite3-wal"] {
            try Data("content".utf8).write(to: database.appendingPathComponent(file))
        }
        return database
    }

    private func originData(scheme: String, host: String) -> Data {
        var data = Data()
        for _ in 0..<2 {
            data.append(AIChatIndexedDBBlobCleaner.encodedOriginString(scheme))
            data.append(AIChatIndexedDBBlobCleaner.encodedOriginString(host))
            data.append(0x00)
        }
        return data
    }

    private func blobFiles(in database: URL) throws -> Set<String> {
        Set(try fileManager.contentsOfDirectory(atPath: database.path).filter { $0.hasSuffix(".blob") })
    }
}
