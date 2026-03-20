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
    
    private(set) var applicationState: DataStoreWarmup.ApplicationState = .unknown
    private var normalDataStoreWarmup: DataStoreWarmup? = DataStoreWarmup()
    private var fireModeDataStoreWarmup: DataStoreWarmup? = DataStoreWarmup()
    
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
    
    private func ensureNormalStoreIsReady() async {
        // This needs to happen only once per app launch
        if let normalDataStoreWarmup {
            await normalDataStoreWarmup.ensureReady(applicationState: applicationState, fireMode: false)
            self.normalDataStoreWarmup = nil
        }
    }
    
    private func ensureFireModeStoreIsReady() async {
        // This needs to happen only once per app launch
        if let fireModeDataStoreWarmup {
            await fireModeDataStoreWarmup.ensureReady(applicationState: applicationState, fireMode: true)
            self.fireModeDataStoreWarmup = nil
        }
    }
}
