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

        let result = await removeLeftoverBlobFiles(with: makeSUT())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.filesFound, 3)
        XCTAssertEqual(result.filesRemoved, 3)
        XCTAssertEqual(try blobFiles(in: database), [])
        XCTAssertTrue(fileManager.fileExists(atPath: database.appendingPathComponent("IndexedDB.sqlite3").path))
        XCTAssertTrue(fileManager.fileExists(atPath: database.appendingPathComponent("IndexedDB.sqlite3-wal").path))
    }

    func testWhenOriginIsDuckDuckGoThenBlobFilesAreRemoved() async throws {
        let database = try makeOrigin(host: "duckduckgo.com", blobFiles: ["1.blob"])

        _ = await removeLeftoverBlobFiles(with: makeSUT())

        XCTAssertEqual(try blobFiles(in: database), [])
    }

    func testWhenOriginIsNotDuckAiThenBlobFilesAreKept() async throws {
        let other = try makeOrigin(host: "example.com", blobFiles: ["1.blob"])
        let subdomain = try makeOrigin(host: "internal.duck.ai", blobFiles: ["1.blob"])
        let http = try makeOrigin(scheme: "http", host: "duck.ai", blobFiles: ["1.blob"])

        let result = await removeLeftoverBlobFiles(with: makeSUT())

        XCTAssertNil(result.error)
        XCTAssertEqual(try blobFiles(in: other), ["1.blob"])
        XCTAssertEqual(try blobFiles(in: subdomain), ["1.blob"], "A length-prefixed match must not treat a subdomain as duck.ai")
        XCTAssertEqual(try blobFiles(in: http), ["1.blob"])
    }

    func testWhenOriginHasMultipleDatabasesThenBlobFilesInEachAreRemoved() async throws {
        let first = try makeOrigin(host: "duck.ai", blobFiles: ["1.blob"])
        let second = try makeDatabase(in: first.deletingLastPathComponent(), blobFiles: ["1.blob", "2.blob"])

        _ = await removeLeftoverBlobFiles(with: makeSUT())

        XCTAssertEqual(try blobFiles(in: first), [])
        XCTAssertEqual(try blobFiles(in: second), [])
    }

    func testWhenOriginHasNoIndexedDBThenRemovalSucceeds() async throws {
        let originDirectory = storageDirectory.appendingPathComponent("hash").appendingPathComponent("hash")
        try fileManager.createDirectory(at: originDirectory, withIntermediateDirectories: true)
        try originData(scheme: "https", host: "duck.ai").write(to: originDirectory.appendingPathComponent("origin"))

        let result = await removeLeftoverBlobFiles(with: makeSUT())

        XCTAssertNil(result.error)
        XCTAssertEqual(result.filesFound, 0)
    }

    func testWhenStorageDirectoryDoesNotExistThenRemovalSucceeds() async {
        let sut = AIChatIndexedDBBlobCleaner(originStorageDirectories: [storageDirectory.appendingPathComponent("missing")],
                                             fileManager: fileManager)

        let result = await removeLeftoverBlobFiles(with: sut)

        XCTAssertNil(result.error)
    }

    func testWhenAThirdPartyFrameInsideDuckAiHasStorageThenItsBlobFilesAreKept() async throws {
        let frame = try makeOrigin(topHost: "duck.ai", frameHost: "example.com", blobFiles: ["1.blob"])

        _ = await removeLeftoverBlobFiles(with: makeSUT())

        XCTAssertEqual(try blobFiles(in: frame), ["1.blob"])
    }

    func testWhenABlobFileIsAddedAfterTheListingThenItIsKept() async throws {
        let database = try makeOrigin(host: "duck.ai", blobFiles: ["1.blob"])
        let sut = makeSUT()
        let listed = await sut.blobFiles()
        try Data("new image".utf8).write(to: database.appendingPathComponent("2.blob"))

        _ = await sut.removeBlobFiles(listed)

        XCTAssertEqual(try blobFiles(in: database), ["2.blob"])
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

    func testWhenOnlyTheTopOriginIsDuckAiThenTheOriginFileDoesNotMatch() {
        let data = originData(scheme: "https", topHost: "duck.ai", frameHost: "example.com")

        XCTAssertFalse(AIChatIndexedDBBlobCleaner.isMatchingOrigin(data, hosts: ["duck.ai"]))
    }

    func testWhenTheOriginFileIsTruncatedThenItDoesNotMatch() {
        let data = originData(scheme: "https", topHost: "duck.ai", frameHost: "duck.ai").dropLast(3)

        XCTAssertFalse(AIChatIndexedDBBlobCleaner.isMatchingOrigin(Data(data), hosts: ["duck.ai"]))
    }

    // MARK: - Helpers

    private func removeLeftoverBlobFiles(with sut: AIChatIndexedDBBlobCleaner) async -> AIChatBlobCleanupResult {
        await sut.removeBlobFiles(await sut.blobFiles())
    }

    /// Creates `<storage>/<hash>/<hash>/origin` plus one IndexedDB database directory; returns the database directory.
    private func makeOrigin(scheme: String = "https", host: String, blobFiles: [String]) throws -> URL {
        try makeOrigin(scheme: scheme, topHost: host, frameHost: host, blobFiles: blobFiles)
    }

    private func makeOrigin(scheme: String = "https", topHost: String, frameHost: String, blobFiles: [String]) throws -> URL {
        let originDirectory = storageDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: originDirectory, withIntermediateDirectories: true)
        try originData(scheme: scheme, topHost: topHost, frameHost: frameHost).write(to: originDirectory.appendingPathComponent("origin"))
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
        originData(scheme: scheme, topHost: host, frameHost: host)
    }

    private func originData(scheme: String, topHost: String, frameHost: String) -> Data {
        var data = Data()
        for host in [topHost, frameHost] {
            data.append(encodedOriginString(scheme))
            data.append(encodedOriginString(host))
            data.append(0x00)
        }
        return data
    }

    /// Encodes a string the way WebKit writes it to the `origin` file.
    private func encodedOriginString(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        var length = UInt32(bytes.count).littleEndian
        var data = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        data.append(0x01)
        data.append(bytes)
        return data
    }

    private func blobFiles(in database: URL) throws -> Set<String> {
        Set(try fileManager.contentsOfDirectory(atPath: database.path).filter { $0.hasSuffix(".blob") })
    }
}
