//
//  SubscriptionOnboardingPrefetcher.swift
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
import AIChat

/// Prefetches the data the flow's sections need before the customer reaches them: the current (pre-VPN) connection
/// info and the available Duck.ai models. Owned by ``SubscriptionOnboardingFlowViewModel`` and fetched once at flow
/// start, so the result is cached here and simply read by the VPN and Duck.ai screens rather than refetched on every
/// visit. A screen that finds its fetch still unresolved (or failed) calls the matching `fetchIfNeeded` method from
/// its own `onAppear`, which is a no-op unless that fetch is `.idle` or `.failed`.
@MainActor
final class SubscriptionOnboardingPrefetcher: ObservableObject {

    /// The lifecycle of one prefetched value.
    enum FetchState<Value> {
        case idle
        case loading
        case loaded(Value)
        case failed

        /// A fetch should (re)start only when nothing is in flight or already resolved.
        var shouldStartFetch: Bool {
            switch self {
            case .idle, .failed: return true
            case .loading, .loaded: return false
            }
        }
    }

    private enum Constants {
        /// Upper bound on how long the model fetch may stay `.loading` before it is treated as failed, so the
        /// Duck.ai screen never hangs on a callback that never arrives.
        static let modelFetchTimeout: TimeInterval = 10
    }

    @Published private(set) var connectionInfo: FetchState<SubscriptionOnboardingConnectionInfo> = .idle
    @Published private(set) var models: FetchState<[AIChatModel]> = .idle

    private let connectionInfoService: SubscriptionOnboardingConnectionInfoService
    private let modelProvider: SubscriptionOnboardingAIModelProviding
    private var modelFetchTimeoutTask: Task<Void, Never>?

    init(connectionInfoService: SubscriptionOnboardingConnectionInfoService = DefaultSubscriptionOnboardingConnectionInfoService(),
         modelProvider: SubscriptionOnboardingAIModelProviding = DefaultSubscriptionOnboardingAIModelProvider()) {
        self.connectionInfoService = connectionInfoService
        self.modelProvider = modelProvider
    }

    /// Kicks off both fetches at flow start.
    @MainActor
    func prefetch() {
        fetchConnectionInfoIfNeeded()
        fetchModelsIfNeeded()
    }

    func fetchConnectionInfoIfNeeded() {
        guard connectionInfo.shouldStartFetch else { return }
        connectionInfo = .loading
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.connectionInfo = .loaded(try await self.connectionInfoService.fetchConnectionInfo())
            } catch {
                self.connectionInfo = .failed
            }
        }
    }

    func fetchModelsIfNeeded() {
        guard models.shouldStartFetch else { return }
        models = .loading
        modelProvider.onModelsUpdated = { [weak self] in
            guard let self else { return }
            self.modelFetchTimeoutTask?.cancel()
            let fetched = self.modelProvider.models
            self.models = fetched.isEmpty ? .failed : .loaded(fetched)
        }
        modelProvider.fetchModels()
        modelFetchTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Constants.modelFetchTimeout * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            if case .loading = self.models { self.models = .failed }
        }
    }

    var persistedModelID: String? { modelProvider.persistedModelID }

    func updateSelectedModel(_ modelID: String) {
        modelProvider.updateSelectedModel(modelID)
    }
}
