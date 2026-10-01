//
//  CallbackWaiter.swift
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

/// Waits for one callback at a time, with a timeout, ignoring callbacks meant for another wait (e.g. an earlier navigation).
@MainActor
final class CallbackWaiter {

    private var pendingHandle: AnyObject?
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var timeoutTask: Task<Void, Never>?

    nonisolated init() {}

    /// - Parameter start: Starts the awaited work and returns its handle (e.g. a `WKNavigation`), or `nil` if it has none.
    func wait(timeout: TimeInterval, timeoutError: Error, start: () -> AnyObject? = { nil }) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            pendingHandle = start()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(timeoutError))
            }
        }
    }

    /// Only the pending wait's own handle completes it; work started without a handle completes with `nil`.
    func complete(_ handle: AnyObject?, with result: Result<Void, Error>) {
        guard handle === pendingHandle else { return }
        finish(with: result)
    }

    func failPending(with error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingHandle = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
