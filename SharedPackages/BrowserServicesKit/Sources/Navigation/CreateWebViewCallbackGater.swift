//
//  CreateWebViewCallbackGater.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Orders `createWebView...completionHandler:` style callbacks behind any currently-executing
/// `decidePolicyForNavigationAction` responder-chain processing.
///
/// - Note: This class intentionally does not reference the caller, so enqueued callbacks do not retain it.
@MainActor
final class CreateWebViewCallbackGater {

    private var executingNavigationActionIdentifiers = Set<UInt64>()

    private struct PendingCallback {
        var waitingOnIdentifiers: Set<UInt64>
        let callback: @MainActor @Sendable () -> Void
    }

    private var pendingCallbacks: [PendingCallback] = []

    func beginExecutingNavigationAction(identifier: UInt64) {
        executingNavigationActionIdentifiers.insert(identifier)
    }

    func endExecutingNavigationAction(identifier: UInt64) {
        executingNavigationActionIdentifiers.remove(identifier)

        // Update pending callbacks and dispatch those that are now unblocked.
        var indicesToRemove = IndexSet()
        for index in pendingCallbacks.indices {
            pendingCallbacks[index].waitingOnIdentifiers.remove(identifier)
            if pendingCallbacks[index].waitingOnIdentifiers.isEmpty {
                indicesToRemove.insert(index)
                DispatchQueue.main.async(execute: pendingCallbacks[index].callback)
            }
        }
        indicesToRemove.reversed().forEach { pendingCallbacks.remove(at: $0) }
    }

    func dispatchCreateWebView(_ callback: @escaping @MainActor @Sendable () -> Void) {
        guard !executingNavigationActionIdentifiers.isEmpty else {
            callback()
            return
        }
        pendingCallbacks.append(.init(waitingOnIdentifiers: executingNavigationActionIdentifiers, callback: callback))
    }
}
