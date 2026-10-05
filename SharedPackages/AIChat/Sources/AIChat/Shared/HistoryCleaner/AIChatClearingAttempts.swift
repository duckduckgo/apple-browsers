//
//  AIChatClearingAttempts.swift
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

/// Runs a clear, and once more after a short pause if it failed in a way a fresh attempt can fix.
@MainActor
struct AIChatClearingAttempts {

    struct Outcome {
        let result: Result<Void, Error>
        let attempts: Int
        /// The first attempt's error, kept even when the retry succeeds so reports still show what went wrong.
        let firstAttemptError: Error?
    }

    let retryDelay: TimeInterval
    let isTransient: (Error) -> Bool

    func run(_ attempt: @MainActor () async -> Result<Void, Error>) async -> Outcome {
        let first = await attempt()
        guard case .failure(let firstError) = first else {
            return Outcome(result: first, attempts: 1, firstAttemptError: nil)
        }
        guard isTransient(firstError) else {
            return Outcome(result: first, attempts: 1, firstAttemptError: firstError)
        }
        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
        return Outcome(result: await attempt(), attempts: 2, firstAttemptError: firstError)
    }
}
