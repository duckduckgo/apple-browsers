//
//  PixelFiring+Async.swift
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

extension PixelFiring {

    /// Fires a pixel and waits for the request to complete.
    ///
    /// Prefer the synchronous `fire` unless the caller genuinely needs the outcome: awaiting a
    /// pixel makes the caller wait on a network round trip.
    ///
    /// - Returns: `.sent` if a request was sent, `.suppressed` if the event's frequency rules
    ///   suppressed it. Suppression is a normal outcome, not a failure.
    /// - Throws: the underlying error if sending the request failed.
    @discardableResult
    public func fireAsync(_ event: PixelKit.Event,
                          frequency: PixelKit.Frequency = .standard,
                          options: PixelKit.Options = .default) async throws -> PixelKit.FireResult {
        let firstCompletion = OneTimeFlag()
        return try await withCheckedThrowingContinuation { continuation in
            fire(event: event,
                 frequency: frequency,
                 options: options) { fired, error in
                // Multi-request frequencies such as `.dailyAndCount` complete more than once.
                // Resolve on the first completion and drop the rest, otherwise the second resume
                // traps.
                guard firstCompletion.trySet() else { return }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: fired ? .sent : .suppressed)
            }
        }
    }
}

/// Thread-safe latch that can only be set once. Guards the continuation above against the multiple
/// completions of multi-request frequencies, which would otherwise trap on the second resume.
private final class OneTimeFlag {
    private let lock = NSLock()
    private var isSet = false

    /// Sets the flag, returning `true` only for the call that actually set it.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSet else { return false }
        isSet = true
        return true
    }
}
