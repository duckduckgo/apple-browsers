//
//  TranslationManifestStore.swift
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
import os.log
import Persistence

/// Fetches the translation manifest and keeps the last good copy, so it's still there offline.
public final class TranslationManifestStore: @unchecked Sendable {

    public static let defaultURL = URL(string: "https://staticcdn.duckduckgo.com/translations/models/models.json")!

    enum Key {
        static let manifest = "webPageTranslation.manifest"
        static let etag = "webPageTranslation.manifestETag"
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let session: URLSession
    private let url: URL
    private let lock = NSLock()
    private var latest: TranslationManifest?
    private var isFetching = false

    public init(keyValueStore: ThrowingKeyValueStoring, session: URLSession, url: URL = TranslationManifestStore.defaultURL) {
        self.keyValueStore = keyValueStore
        self.session = session
        self.url = url
    }

    /// The newest manifest fetched since launch, else the last saved one; nil when there's neither.
    public var cached: TranslationManifest? {
        lock.withLock { latest } ?? saved
    }

    /// The last saved manifest, or nil when there's none or it can't be read.
    private var saved: TranslationManifest? {
        guard let data = (try? keyValueStore.object(forKey: Key.manifest)) as? Data else {
            return nil
        }

        return try? TranslationManifest.decode(data)
    }

    /// Fetches the manifest when the server has a newer one. Any failure, or a fetch already running, returns the cached copy.
    public func refresh() async -> TranslationManifest? {
        // One fetch at a time, so two can't interleave their manifest and ETag saves.
        guard beginFetching() else {
            return cached
        }
        defer { endFetching() }

        var request = URLRequest(url: url)
        // Without a readable saved copy, a 304 would leave us with nothing.
        if saved != nil, let etag = (try? keyValueStore.object(forKey: Key.etag)) as? String {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let manifest = try? TranslationManifest.decode(data) else {
            return cached
        }

        // Kept in memory too, so a failed save doesn't lose it for this launch.
        lock.withLock { latest = manifest }
        // The ETag is saved only once its manifest is, so a failed save can't pair it with an older copy
        do {
            try keyValueStore.set(data, forKey: Key.manifest)
            try keyValueStore.set(response.value(forHTTPHeaderField: "ETag"), forKey: Key.etag)
        } catch {
            Logger.webPageTranslation.error("Saving the translation manifest failed: \(error.localizedDescription, privacy: .public)")
        }
        return manifest
    }

    private func beginFetching() -> Bool {
        lock.withLock {
            guard !isFetching else {
                return false
            }

            isFetching = true
            return true
        }
    }

    private func endFetching() {
        lock.withLock { isFetching = false }
    }
}
