//
//  TranslationManifestStoreTests.swift
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

import Foundation
import Testing
import LocalModels
@_spi(Testing) import Persistence
@testable import WebPageTranslation

extension StubbedNetworkTests {

    @Suite
    struct TranslationManifestStoreTests {

        private let keyValueStore = InMemoryThrowingKeyValueStore()
        private let url = URL(string: "https://models.test/models.json")!
        private let fixture: Data

        init() throws {
            let fixtureURL = try #require(Bundle.module.url(forResource: "models", withExtension: "json", subdirectory: "Resources"))
            fixture = try Data(contentsOf: fixtureURL)
        }

        @available(iOS 16, macOS 13, *)
        @Test("the first fetch saves the manifest and its ETag, and the next fetch sends the ETag", .timeLimit(.minutes(1)))
        func firstFetchSavesManifestAndETag() async throws {
            let store = makeStore { _ in (response(200, etag: "v1"), fixture) }

            let manifest = await store.refresh()
            _ = await store.refresh()

            #expect(manifest == (try TranslationManifest.decode(fixture)))
            #expect(store.cached == manifest)
            #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
            #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "v1")
        }

        @available(iOS 16, macOS 13, *)
        @Test("304 returns the cached manifest", .timeLimit(.minutes(1)))
        func notModifiedReturnsCached() async throws {
            seedCache(etag: "v1")
            let store = makeStore { _ in (response(304), Data()) }

            #expect(await store.refresh() == (try TranslationManifest.decode(fixture)))
        }

        @available(iOS 16, macOS 13, *)
        @Test("a network error falls back to the cached manifest", .timeLimit(.minutes(1)))
        func networkErrorFallsBackToCache() async throws {
            seedCache(etag: "v1")
            let store = makeStore { _ in throw URLError(.notConnectedToInternet) }

            #expect(await store.refresh() == (try TranslationManifest.decode(fixture)))
        }

        @available(iOS 16, macOS 13, *)
        @Test("offline with no cache returns nil", .timeLimit(.minutes(1)))
        func offlineWithNoCacheReturnsNil() async throws {
            let store = makeStore { _ in throw URLError(.notConnectedToInternet) }

            #expect(await store.refresh() == nil)
        }

        @available(iOS 16, macOS 13, *)
        @Test("an unreadable body keeps the cached manifest and its ETag", .timeLimit(.minutes(1)))
        func garbageBodyKeepsCacheAndETag() async throws {
            seedCache(etag: "v1")
            let store = makeStore { _ in (response(200, etag: "v2"), Data("<html>".utf8)) }

            #expect(await store.refresh() == (try TranslationManifest.decode(fixture)))
            #expect(keyValueStore.underlyingDict[TranslationManifestStore.Key.etag] as? String == "v1")
        }

        @available(iOS 16, macOS 13, *)
        @Test("a newer schema keeps the cached manifest", .timeLimit(.minutes(1)))
        func newerSchemaKeepsCache() async throws {
            seedCache(etag: "v1")
            let newer = Data(#"{"schemaVersion": 2, "baseUrl": "https://models.test/", "models": {}}"#.utf8)
            let store = makeStore { _ in (response(200, etag: "v2"), newer) }

            #expect(await store.refresh() == (try TranslationManifest.decode(fixture)))
        }

        @available(iOS 16, macOS 13, *)
        @Test("a manifest that can't be saved is still returned, and its ETag isn't saved", .timeLimit(.minutes(1)))
        func failedSaveStillReturnsManifest() async throws {
            keyValueStore.shouldThrowOnSet = true
            let store = makeStore { _ in (response(200, etag: "v1"), fixture) }

            #expect(await store.refresh() == (try TranslationManifest.decode(fixture)))
            #expect(keyValueStore.underlyingDict.isEmpty)
            #expect(store.cached == (try TranslationManifest.decode(fixture)))
        }

        @available(iOS 16, macOS 13, *)
        @Test("an ETag is sent only when the saved manifest can be read", .timeLimit(.minutes(1)))
        func unreadableCacheSendsNoETag() async throws {
            keyValueStore.underlyingDict[TranslationManifestStore.Key.manifest] = Data("<html>".utf8)
            keyValueStore.underlyingDict[TranslationManifestStore.Key.etag] = "v1"
            let store = makeStore { _ in (response(200, etag: "v2"), fixture) }

            #expect(await store.refresh() == (try TranslationManifest.decode(fixture)))
            #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "If-None-Match") == nil)
        }

        @available(iOS 16, macOS 13, *)
        @Test("a refresh started while another runs makes no request", .timeLimit(.minutes(1)))
        func overlappingRefreshMakesNoRequest() async throws {
            let store = makeStore { _ in (response(200, etag: "v1"), fixture) }
            StubURLProtocol.delay = 0.3

            async let first = store.refresh()
            async let second = store.refresh()
            _ = await (first, second)

            #expect(StubURLProtocol.requests.count == 1)
        }

        // MARK: - Helpers

        private func makeStore(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> TranslationManifestStore {
            StubURLProtocol.reset()
            StubURLProtocol.handler = handler
            return TranslationManifestStore(keyValueStore: keyValueStore, session: .localModels(configuration: StubURLProtocol.configuration()), url: url)
        }

        private func response(_ status: Int, etag: String? = nil) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: etag.map { ["ETag": $0] })!
        }

        /// Saves what a successful fetch leaves behind.
        private func seedCache(etag: String) {
            keyValueStore.underlyingDict[TranslationManifestStore.Key.manifest] = fixture
            keyValueStore.underlyingDict[TranslationManifestStore.Key.etag] = etag
        }
    }
}
