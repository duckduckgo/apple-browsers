//
//  UpdatePromptService.swift
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
import FeatureFlags_iOS
import Foundation
import Persistence
import PrivacyConfig

enum UpdatePromptStorageKeys: String, StorageKeyDescribing {
    case latestRelease = "update-prompt-latest-release"
    case state = "update-prompt-state"
    case lastFetchDate = "update-prompt-last-fetch-date"
}

struct UpdatePromptKeys: StoringKeys {
    let latestRelease = StorageKey<AppStoreRelease>(UpdatePromptStorageKeys.latestRelease)
    let state = StorageKey<UpdatePromptState>(UpdatePromptStorageKeys.state)
    let lastFetchDate = StorageKey<Date>(UpdatePromptStorageKeys.lastFetchDate)
}

/// Keeps the latest App Store release cached for the update prompt, fetching it at most once a day on foreground.
@MainActor
final class UpdatePromptService {

    typealias LoadData = @Sendable (URL) async throws -> Data

    static let fetchInterval: TimeInterval = 24 * 60 * 60

    private let storage: any ThrowingKeyedStoring<UpdatePromptKeys>
    private let featureFlagger: FeatureFlagger
    private let loadData: LoadData
    private var isFetching = false

    init(storage: any ThrowingKeyedStoring<UpdatePromptKeys>,
         featureFlagger: FeatureFlagger,
         loadData: @escaping LoadData = UpdatePromptService.loadFromNetwork) {
        self.storage = storage
        self.featureFlagger = featureFlagger
        self.loadData = loadData
    }

    func resume() {
        Task { await refreshIfNeeded(now: Date()) }
    }

    /// Fetch failures keep the cached release: the file may not exist yet, and a missed day is harmless.
    func refreshIfNeeded(now: Date) async {
        guard featureFlagger.isFeatureOn(.updatePrompt), !isFetching else { return }
        if let lastFetch = try? storage.lastFetchDate,
           now >= lastFetch, now.timeIntervalSince(lastFetch) < Self.fetchInterval {
            return
        }

        isFetching = true
        defer { isFetching = false }
        try? storage.set(now, for: \.lastFetchDate)

        guard let data = try? await loadData(URL.iOSReleaseMetadata),
              let metadata = try? AppStoreReleaseMetadata.decode(from: data) else {
            return
        }
        try? storage.set(metadata.latest, for: \.latestRelease)
    }

    nonisolated static func loadFromNetwork(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
