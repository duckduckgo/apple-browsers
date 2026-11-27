//
//  AssistedOptOutInstrumentation.swift
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

/// How an assisted attempt ended. `cancelled` covers the user closing the window as well as the app stopping it.
public enum AssistedOptOutOutcome: String, Sendable {
    case submitted, cancelled, timedOut, failed
}

@MainActor
/// Reports how long assisted attempts take and how much of that time the user spends on their part.
public protocol AssistedOptOutInstrumentation {
    func started()
    func reachedUserTurn(after duration: TimeInterval)
    func ended(outcome: AssistedOptOutOutcome, totalDuration: TimeInterval, userTurnDuration: TimeInterval)
}
