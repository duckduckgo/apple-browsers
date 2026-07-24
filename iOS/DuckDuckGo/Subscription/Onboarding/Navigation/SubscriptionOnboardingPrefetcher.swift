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
/// info and the available Duck.ai models. Fetched once at flow start, so the result is cached here and simply read
/// by the VPN and Duck.ai screens rather than refetched on every visit. A screen that finds its fetch still
/// unresolved (or failed) calls the matching `fetchIfNeeded` method from its own `onAppear`, which is a no-op
/// unless that fetch is `.idle` or `.failed`.
///
// TODO: will be owned by SubscriptionOnboardingFlowViewModel.swift calling `prefetch()` once at flow start
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

    @Published private(set) var connectionInfo: FetchState<SubscriptionOnboardingConnectionInfo> = .idle
    @Published private(set) var models: FetchState<[AIChatModel]> = .idle

    private let connectionInfoService: SubscriptionOnboardingConnectionInfoService
    private let modelProvider: SubscriptionOnboardingAIModelProviding

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
        Task { @MainActor [weak self] in
            guard let self else { return }
            let fetched = await self.modelProvider.fetchModels()
            self.models = fetched.isEmpty ? .failed : .loaded(fetched)
        }
    }

    var persistedModelID: String? { modelProvider.persistedModelID }

    func updateSelectedModel(_ modelID: String) {
        modelProvider.updateSelectedModel(modelID)
    }
}

extension SubscriptionOnboardingPrefetcher.FetchState: Equatable where Value: Equatable {}

#if DEBUG
extension SubscriptionOnboardingPrefetcher {
    /// Builds a prefetcher pre-seeded with resolved fetch states for previews. Seeding here rather than on the
    /// view model matters: the view model subscribes to `$connectionInfo`, and a live `@Published` re-emits its
    /// current value on subscribe — which would otherwise immediately clobber a value seeded on the view model
    /// with the prefetcher's `.idle`. A `.loaded` seed also makes `fetchConnectionInfoIfNeeded()` a no-op.
    @MainActor
    static func preview(connectionInfo: FetchState<SubscriptionOnboardingConnectionInfo> = .idle,
                        models: FetchState<[AIChatModel]> = .idle) -> SubscriptionOnboardingPrefetcher {
        let prefetcher = SubscriptionOnboardingPrefetcher(connectionInfoService: PreviewSubscriptionOnboardingConnectionInfoService())
        prefetcher.connectionInfo = connectionInfo
        prefetcher.models = models
        return prefetcher
    }
}
#endif
