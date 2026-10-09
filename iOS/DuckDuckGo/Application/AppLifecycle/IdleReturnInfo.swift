//
//  IdleReturnInfo.swift
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

/// A cold start's return from idle, evaluated once at launch and applied by the launch handling.
struct IdleReturnInfo: Equatable {

    let outcome: IdleReturnOutcome
    /// The New Tab Page is the first screen, rather than replacing the restored tab after authentication.
    let newTabPageDrawnAtLaunch: Bool

    /// App Lock: nothing covers the window before authentication on a cold launch, so the page isn't drawn early.
    /// Clearing tabs: the cleared model already lands on a New Tab Page.
    init(outcome: IdleReturnOutcome, isAppLockEnabled: Bool, clearsTabsOnLaunch: Bool) {
        self.outcome = outcome
        if case .afterIdle(.ntp, _) = outcome {
            newTabPageDrawnAtLaunch = !isAppLockEnabled && !clearsTabsOnLaunch
        } else {
            newTabPageDrawnAtLaunch = false
        }
    }

}
