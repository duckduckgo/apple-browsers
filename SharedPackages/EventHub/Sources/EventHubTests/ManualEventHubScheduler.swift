//
//  ManualEventHubScheduler.swift
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
@testable import EventHub

/// Test double for `EventHubScheduler`: a manually-advanced virtual clock driving a single armed
/// callback. `advance(by:)` loops so an action that re-arms another already-due callback also fires
/// within the same call (see `EventHubTests.firingResetsTheCounterForTheNextPeriod`, which relies on
/// the period-end firing and the next period's timer both being live after one `advance`).
final class ManualEventHubScheduler: EventHubScheduler {
    private var currentMillis: Int64
    private var armedAtMillis: Int64?
    private var armedAction: (() -> Void)?

    init(startMillis: Int64) {
        self.currentMillis = startMillis
    }

    func nowMillis() -> Int64 { currentMillis }

    func arm(atMillis dateMillis: Int64?, _ action: @escaping () -> Void) {
        armedAtMillis = dateMillis
        armedAction = dateMillis == nil ? nil : action
    }

    func advance(by interval: TimeInterval) {
        currentMillis += Int64(interval * 1000)
        while let dueAt = armedAtMillis, dueAt <= currentMillis, let action = armedAction {
            armedAtMillis = nil
            armedAction = nil
            action()
        }
    }
}
