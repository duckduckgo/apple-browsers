//
//  EventHubDebugEvent.swift
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

/// The EventHub failures worth fleet-wide visibility, rather than only a local log entry. Delivered
/// through an injected `EventMapping`, so this package stays free of any pixel dependency and tests can
/// assert on events instead of on side effects.
///
/// Deliberately narrow: every fail-safe boundary in EventHub logs to `Logger.eventHub`, but only failures
/// that are both *actionable* and *invisible from the outside* earn an event here. Excluded on purpose are
/// the paths that encode our own structs (no failure mode reachable from remote input) and the ones that
/// degrade gracefully and self-heal on the next period.
public enum EventHubDebugEvent: Equatable {
    /// EventHub could not read or write its own persisted state, so counting silently restarts or a
    /// finished period is lost. `operation` says which step failed; the fired pixel carries it as a
    /// parameter rather than splitting into one pixel name per operation.
    case pixelStatePersistenceFailed(operation: PersistenceOperation)

    /// A consent-gated telemetry entry could not be removed from the settings, so EventHub failed closed
    /// and is now running no telemetry at all. Does not fire for the normal "nothing configured yet"
    /// state, only when telemetry exists in a shape we cannot process.
    case consentStripFailed

    public enum PersistenceOperation: String {
        /// The key-value store threw while reading.
        case read
        /// Something was stored, but it is not state we can decode.
        case decode
        /// The key-value store threw while persisting.
        case write
        /// The key-value store threw while deleting.
        case delete
    }
}
