//
//  DataStoreWarmupWorker.swift
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

actor DataStoreWarmupWorker: FireExecutorWorker {

    /// Returns `true` when the warm-up completed, `false` when it timed out.
    typealias WarmUp = @MainActor (_ applicationState: DataStoreWarmup.ApplicationState, _ fireMode: Bool) async -> Bool

    private enum Store {
        case normal
        case fireMode
    }

    private(set) var applicationState: DataStoreWarmup.ApplicationState = .unknown
    private let warmUp: WarmUp
    // Concurrent callers await the same warm-up, so the Duck.ai clear and the data burn share one.
    private var warmUps: [Store: Task<Bool, Never>] = [:]

    init(warmUp: @escaping WarmUp = { await DataStoreWarmup().ensureReady(applicationState: $0, fireMode: $1) }) {
        self.warmUp = warmUp
    }

    func setApplicationState(_ applicationState: DataStoreWarmup.ApplicationState) {
        self.applicationState = applicationState
    }

    
    func burnNormalModeData() async {
        await ensureNormalStoreIsReady()
    }
    
    func burnFireModeData() async {
        // Fire mode clearing destroys the entire WKWebsiteDataStore container rather than
        // clearing data within it, so warmup is unnecessary.
    }
    
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        if await tabViewModel.tab.fireTab {
            await ensureFireModeStoreIsReady()
        } else {
            await ensureNormalStoreIsReady()
        }
    }
    
    func ensureNormalStoreIsReady() async {
        await ensureIsReady(.normal)
    }

    private func ensureFireModeStoreIsReady() async {
        await ensureIsReady(.fireMode)
    }

    /// Succeeds once per app launch. A warm-up that timed out left the data store in an unknown state,
    /// so it is retried by the next burn rather than kept.
    private func ensureIsReady(_ store: Store) async {
        let warmUpTask = warmUps[store] ?? makeWarmUpTask(for: store)
        warmUps[store] = warmUpTask
        let completed = await warmUpTask.value
        if !completed, warmUps[store] == warmUpTask {
            warmUps[store] = nil
        }
    }

    private func makeWarmUpTask(for store: Store) -> Task<Bool, Never> {
        let warmUp = warmUp
        let applicationState = applicationState
        return Task { await warmUp(applicationState, store == .fireMode) }
    }
}
