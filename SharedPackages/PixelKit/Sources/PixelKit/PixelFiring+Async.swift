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
    /// A multi-request frequency such as `.dailyAndCount` fires one request per leg, and this
    /// waits for every one of them before returning.
    ///
    /// - Returns: `.sent` if any leg sent a request, `.suppressed` if the event's frequency rules
    ///   suppressed all of them. Suppression is a normal outcome, not a failure.
    /// - Throws: the first error reported by any leg, once every leg has finished.
    @discardableResult
    public func fireAsync(_ event: PixelKit.Event,
                          frequency: PixelKit.Frequency = .standard,
                          options: PixelKit.Options = .default) async throws -> PixelKit.FireResult {
        let legs = LegAggregator(expecting: frequency.legCount)
        return try await withCheckedThrowingContinuation { continuation in
            fire(event: event,
                 frequency: frequency,
                 options: options) { fired, error in
                guard let outcome = legs.record(fired: fired, error: error) else { return }

                switch outcome {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let result):
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

/// Collects the completions of a frequency's legs and yields the combined outcome once, on the
/// completion that satisfies the last one.
///
/// A two-leg frequency completes twice - each leg completes whether it sent or was suppressed - and
/// resuming a continuation twice traps, so exactly one completion may resolve it.
private final class LegAggregator {
    private let lock = NSLock()
    private let expected: Int
    private var received = 0
    private var firstError: Error?
    private var anyLegSent = false
    private var hasResolved = false

    init(expecting expected: Int) {
        self.expected = max(expected, 1)
    }

    /// Records one leg's completion, returning the combined outcome only on the completion that
    /// brings the total up to the expected leg count, and `nil` for every other call. Returns
    /// `nil` for anything after that, so an over-completing handler cannot resume twice.
    func record(fired: Bool, error: Error?) -> Result<PixelKit.FireResult, Error>? {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResolved else { return nil }

        received += 1
        anyLegSent = anyLegSent || fired
        if firstError == nil { firstError = error }

        guard received >= expected else { return nil }
        hasResolved = true

        if let firstError {
            return .failure(firstError)
        }
        return .success(anyLegSent ? .sent : .suppressed)
    }
}
