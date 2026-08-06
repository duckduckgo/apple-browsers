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

/// Prefetches what the flow's sections need, once at flow start, so screens read the result rather than
/// refetching on every visit.
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

    private var connectionInfoTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?

    init(connectionInfoService: SubscriptionOnboardingConnectionInfoService = DefaultSubscriptionOnboardingConnectionInfoService(),
         modelProvider: SubscriptionOnboardingAIModelProviding? = nil) {
        self.connectionInfoService = connectionInfoService
        self.modelProvider = modelProvider ?? DefaultSubscriptionOnboardingAIModelProvider()
    }

    deinit {
        connectionInfoTask?.cancel()
        modelsTask?.cancel()
    }

    /// Kicks off both fetches at flow start.
    func prefetch() {
        fetchConnectionInfoIfNeeded()
        fetchModelsIfNeeded()
    }

    func fetchConnectionInfoIfNeeded() {
        guard connectionInfo.shouldStartFetch else { return }
        connectionInfo = .loading
        connectionInfoTask = Task { @MainActor [weak self] in
            guard let service = self?.connectionInfoService else { return }
            do {
                let info = try await service.fetchConnectionInfo()
                guard !Task.isCancelled else {
                    self?.connectionInfo = .idle
                    return
                }
                self?.connectionInfo = .loaded(info)
            } catch {
                guard !Task.isCancelled else {
                    self?.connectionInfo = .idle
                    return
                }
                self?.connectionInfo = .failed
            }
        }
    }

    func fetchModelsIfNeeded() {
        guard models.shouldStartFetch else { return }
        models = .loading
        modelsTask = Task { @MainActor [weak self] in
            guard let provider = self?.modelProvider else { return }
            let fetched = await provider.fetchModels()
            guard !Task.isCancelled else {
                self?.models = .idle
                return
            }
            self?.models = fetched.isEmpty ? .failed : .loaded(fetched)
        }
    }

    func updateSelectedModel(_ modelID: String) {
        modelProvider.updateSelectedModel(modelID)
    }
}

extension SubscriptionOnboardingPrefetcher.FetchState: Equatable where Value: Equatable {}

#if DEBUG
extension SubscriptionOnboardingPrefetcher {
    /// Seed previews here rather than on the view model: `@Published` re-emits on subscribe, so a value seeded
    /// on the view model would be clobbered by the prefetcher's `.idle`.
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
