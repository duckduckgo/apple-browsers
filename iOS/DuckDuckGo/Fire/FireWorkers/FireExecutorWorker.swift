//
//  FireExecutorWorker.swift
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

protocol FireExecutorWorker {
    @MainActor func burnNormalModeData() async
    @MainActor func burnFireModeData() async
    @MainActor func burnTabData(tabViewModel: TabViewModel, domains: [String]) async
}

extension FireExecutorWorker {

    /// Dispatches to the appropriate burn method based on scope.
    /// For `.all`, both `burnNormalModeData` and `burnFireModeData` run concurrently
    /// since clearing all data means clearing data from both normal and fire browsing modes.
    @MainActor
    func execute(scope: FireRequest.Scope, domains: [String]?) async {
        switch scope {
        case .tab(let viewModel):
            guard let domains else {
                Logger.general.error("Expected domains to be present when burning tab scoped data")
                return
            }
            await burnTabData(tabViewModel: viewModel, domains: domains)
        case .fireMode:
            await burnFireModeData()
        case .normalMode:
            await burnNormalModeData()
        case .all:
            async let fireModeTask: Void = burnFireModeData()
            async let normalTask: Void = burnNormalModeData()
            _ = await (fireModeTask, normalTask)
        }
    }

}
