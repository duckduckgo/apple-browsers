//
//  UpdatePromptServiceTests.swift
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

import Core
import Foundation
@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Update prompt release fetch")
final class UpdatePromptServiceTests {

    private final class StubLoader: @unchecked Sendable {
        var responses: [Result<Data, Error>] = []
        var requestedURLs: [URL] = []

        func load(_ url: URL) throws -> Data {
            requestedURLs.append(url)
            return try responses.removeFirst().get()
        }
    }

    private let storage: any ThrowingKeyedStoring<UpdatePromptKeys> = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
    private let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.updatePrompt])
    private let loader = StubLoader()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeService() -> UpdatePromptService {
        let loader = loader
        return UpdatePromptService(storage: storage, featureFlagger: featureFlagger, loadData: { try loader.load($0) })
    }

    private func metadata(_ version: String) -> Data {
        Data("""
        {"latest_appstore_version": {"latest_version": "\(version)", "build_number": 1,
         "release_date": "2026-11-23T15:00:45Z", "minimum_os_version": "16.0"}}
        """.utf8)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Caches the latest release from the iOS metadata file", .timeLimit(.minutes(1)))
    func cachesRelease() async throws {
        loader.responses = [.success(metadata("7.250.0"))]

        await makeService().refreshIfNeeded(now: start)

        #expect(loader.requestedURLs == [URL(string: "https://staticcdn.duckduckgo.com/ios-browser/release_metadata.json")!])
        #expect(try storage.latestRelease?.version == "7.250.0")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Fetches at most once a day", .timeLimit(.minutes(1)))
    func oncePerDay() async throws {
        loader.responses = [.success(metadata("7.250.0")), .success(metadata("7.251.0"))]
        let service = makeService()

        await service.refreshIfNeeded(now: start)
        await service.refreshIfNeeded(now: start.addingTimeInterval(23 * 60 * 60))
        #expect(loader.requestedURLs.count == 1)

        await service.refreshIfNeeded(now: start.addingTimeInterval(24 * 60 * 60))
        #expect(loader.requestedURLs.count == 2)
        #expect(try storage.latestRelease?.version == "7.251.0")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed or unreadable fetch keeps the cached release", .timeLimit(.minutes(1)))
    func failureKeepsCache() async throws {
        loader.responses = [.success(metadata("7.250.0")), .failure(URLError(.badServerResponse)), .success(Data("<html>".utf8))]
        let service = makeService()

        await service.refreshIfNeeded(now: start)
        await service.refreshIfNeeded(now: start.addingTimeInterval(25 * 60 * 60))
        await service.refreshIfNeeded(now: start.addingTimeInterval(50 * 60 * 60))

        #expect(loader.requestedURLs.count == 3)
        #expect(try storage.latestRelease?.version == "7.250.0")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Doesn't fetch while the flag is off", .timeLimit(.minutes(1)))
    func flagOff() async {
        featureFlagger.enabledFeatureFlags = []

        await makeService().refreshIfNeeded(now: start)

        #expect(loader.requestedURLs.isEmpty)
    }
}
