//
//  PageContextExtractionResolver.swift
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

/// Pairs page-context collection results with the requests that triggered them, FIFO, so extraction
/// pixels carry the right trigger/latency when several collects overlap for one navigation.
public struct PageContextExtractionResolver {

    public struct Resolution: Equatable {
        public let outcome: PageContextExtractionOutcome
        public let trigger: PageContextExtractionTrigger
        /// Request-to-result time; `nil` when no result arrived (a timed-out collection).
        public let latency: PageContextExtractionLatencyBucket?
    }

    private struct PendingCollection {
        let trigger: PageContextExtractionTrigger
        let startedAt: DispatchTime
    }

    private var pending: [PendingCollection] = []

    public init() {}

    public var hasPendingCollections: Bool { !pending.isEmpty }

    public mutating func requested(trigger: PageContextExtractionTrigger, at startedAt: DispatchTime = .now()) {
        pending.append(PendingCollection(trigger: trigger, startedAt: startedAt))
    }

    /// Drops all outstanding collects without emitting any resolution. Call on navigation so a
    /// previous page's slow or never-resolving collect can't pair (FIFO) with the next page's
    /// result and mis-attribute its trigger/latency/outcome.
    public mutating func reset() {
        pending.removeAll()
    }

    /// Returns `nil` when no request is outstanding (a duplicate or a collection we didn't initiate).
    public mutating func resolve(pageContext: AIChatPageContextData?, now: DispatchTime = .now()) -> Resolution? {
        guard !pending.isEmpty else { return nil }
        let request = pending.removeFirst()

        let outcome: PageContextExtractionOutcome
        if let pageContext {
            outcome = pageContext.isEmpty() ? .failure(.emptyContent) : .success
        } else {
            outcome = .failure(.deserializeFailed)
        }

        let seconds = Double(now.uptimeNanoseconds - request.startedAt.uptimeNanoseconds) / 1_000_000_000
        return Resolution(outcome: outcome, trigger: request.trigger, latency: PageContextExtractionLatencyBucket(seconds: seconds))
    }

    /// Drops requests that have been outstanding for at least `timeout` and returns a
    /// `.failure(.timeout)` resolution (no latency) for each, oldest first. A `collect()` that
    /// never yields a result would otherwise leave its entry pending indefinitely.
    public mutating func expireCollections(olderThan timeout: TimeInterval, now: DispatchTime = .now()) -> [Resolution] {
        let cutoffNanos = UInt64(timeout * 1_000_000_000)
        var expired: [Resolution] = []
        pending.removeAll { request in
            guard now.uptimeNanoseconds >= request.startedAt.uptimeNanoseconds,
                  now.uptimeNanoseconds - request.startedAt.uptimeNanoseconds >= cutoffNanos else {
                return false
            }
            expired.append(Resolution(outcome: .failure(.timeout), trigger: request.trigger, latency: nil))
            return true
        }
        return expired
    }
}
