//
//  NavigationCompletionWaiter.swift
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

/// Waits for one web view navigation at a time, with a timeout, ignoring callbacks from any other navigation.
@MainActor
final class NavigationCompletionWaiter {

    private var pendingNavigation: AnyObject?
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var timeoutTask: Task<Void, Never>?

    nonisolated init() {}

    /// - Parameter start: Starts the navigation and returns its handle (a `WKNavigation`).
    func wait(timeout: TimeInterval, timeoutError: Error, start: () -> AnyObject?) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            pendingNavigation = start()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(with: .failure(timeoutError))
            }
        }
    }

    func complete(_ navigation: AnyObject?, with result: Result<Void, Error>) {
        guard navigation === pendingNavigation else { return }
        finish(with: result)
    }

    func failPendingNavigation(with error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        pendingNavigation = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
