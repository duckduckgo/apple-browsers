//
//  TranslationModelsTests.swift
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


import CryptoKit
import Foundation
import Testing
import LocalModels
@_spi(Testing) import Persistence
@testable import WebPageTranslation

extension StubbedNetworkTests {

    @Suite
    struct TranslationModelsTests {

        private static let helloSHA256 = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

        private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        private let keyValueStore = InMemoryThrowingKeyValueStore()
        private let zst: Data

        init() throws {
            let url = try #require(Bundle.module.url(forResource: "hello.txt", withExtension: "zst", subdirectory: "Resources"))
            zst = try Data(contentsOf: url)
        }

        @available(iOS 16, macOS 13, *)
        @Test("install downloads, decompresses and checks the pair's files", .timeLimit(.minutes(1)))
        func installDecompressesAndVerifies() async throws {
            let models = try makeModels(manifest: manifest(), file: zst)
            await models.refreshManifest()

            for try await _ in models.install("fr-en") {}

            let folder = try #require(models.installed().first { $0.id == "fr-en" }?.folder)
            #expect(try String(contentsOf: folder.appendingPathComponent("hello.txt"), encoding: .utf8) == "hello")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["bundle.json", "hello.txt"])
        }

        @available(iOS 16, macOS 13, *)
        @Test("a wrong decompressed hash fails the install", .timeLimit(.minutes(1)))
        func decompressedHashMismatchFails() async throws {
            let models = try makeModels(manifest: manifest(decompressedHash: String(repeating: "0", count: 64)), file: zst)
            await models.refreshManifest()

            await #expect(throws: TranslationModelsError.decompressedHashMismatch(file: "hello.txt")) {
                for try await _ in models.install("fr-en") {}
            }
            #expect(models.installed().isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("a file that isn't zstd fails the install", .timeLimit(.minutes(1)))
        func corruptZstFails() async throws {
            let notZstd = Data("notzstd".utf8)
            let models = try makeModels(manifest: manifest(compressed: notZstd), file: notZstd)
            await models.refreshManifest()

            await #expect(throws: (any Error).self) { for try await _ in models.install("fr-en") {} }
            #expect(models.installed().isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("installing a pair the manifest doesn't list throws", .timeLimit(.minutes(1)))
        func unknownPairThrows() async throws {
            let models = try makeModels(manifest: manifest(), file: zst)
            await models.refreshManifest()

            await #expect(throws: TranslationModelsError.unknownPair("xx-en")) { for try await _ in models.install("xx-en") {} }
        }

        @available(iOS 16, macOS 13, *)
        @Test("installing before the manifest is available throws manifestUnavailable, then the manifest arrives", .timeLimit(.minutes(1)))
        func installWithoutManifestThrowsThenFetches() async throws {
            let models = try makeModels(manifest: manifest(), file: zst)

            await #expect(throws: TranslationModelsError.manifestUnavailable) { for try await _ in models.install("fr-en") {} }
            for _ in 0..<100 where models.manifest == nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            #expect(models.manifest?.models["fr-en"] != nil)
        }

        @available(iOS 16, macOS 13, *)
        @Test("refreshing deletes installed pairs the manifest no longer lists", .timeLimit(.minutes(1)))
        func refreshPrunesDroppedPairs() async throws {
            let models = try makeModels(manifest: manifest(), file: zst)
            await models.refreshManifest()
            for try await _ in models.install("fr-en") {}

            serve(manifest: manifest(pairID: "de-en"), file: zst)
            await models.refreshManifest()

            #expect(models.installed().isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("a refresh that gets no manifest deletes nothing", .timeLimit(.minutes(1)))
        func failedRefreshDoesNotPrune() async throws {
            let models = try makeModels(manifest: manifest(), file: zst)
            await models.refreshManifest()
            for try await _ in models.install("fr-en") {}

            StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
            let offline = try TranslationModels(directory: directory,
                                                keyValueStore: InMemoryThrowingKeyValueStore(),
                                                session: .localModels(configuration: StubURLProtocol.configuration()))

            await offline.refreshManifest()
            #expect(offline.installed().map(\.id) == ["fr-en"])
        }

        // MARK: - Helpers

        private func makeModels(manifest: Data, file: Data) throws -> TranslationModels {
            StubURLProtocol.reset()
            serve(manifest: manifest, file: file)
            return try TranslationModels(directory: directory,
                                         keyValueStore: keyValueStore,
                                         session: .localModels(configuration: StubURLProtocol.configuration()))
        }

        /// Serves `manifest` for models.json and `file` for every other URL.
        private func serve(manifest: Data, file: Data) {
            StubURLProtocol.handler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, request.url!.lastPathComponent == "models.json" ? manifest : file)
            }
        }

        /// A manifest with one pair whose single file is `hello.txt.zst`.
        private func manifest(pairID: String = "fr-en", compressed: Data? = nil, decompressedHash: String = helloSHA256) -> Data {
            let compressed = compressed ?? zst
            let sha256 = SHA256.hash(data: compressed).map { String(format: "%02x", $0) }.joined()
            return Data("""
            {"schemaVersion": 1, "baseUrl": "https://models.test/", "models": {"\(pairID)": {
              "sourceLanguage": "fr", "targetLanguage": "en", "version": "1", "totalBytes": \(compressed.count),
              "files": {"model": {"path": "\(pairID)/hello.txt.zst", "bytes": \(compressed.count), "sha256": "\(sha256)",
                                  "decompressedSize": 5, "decompressedHash": "\(decompressedHash)"}}}}}
            """.utf8)
        }
    }
}
