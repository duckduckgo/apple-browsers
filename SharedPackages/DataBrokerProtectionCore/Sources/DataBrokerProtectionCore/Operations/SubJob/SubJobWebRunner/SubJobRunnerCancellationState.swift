//
//  SubJobRunnerCancellationState.swift
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

/// Shares cancellation between the runner task and callback-driven work that may execute in other tasks or executors,
/// where `Task.isCancelled` does not reflect cancellation of the runner. Access is locked because captcha and
/// email-confirmation polling can read the state off the main actor.
public final class SubJobRunnerCancellationState {

    private let lock = NSLock()
    private var cancelled = false
    private let shouldRunNextStepHandler: () -> Bool

    public init(shouldRunNextStep: @escaping () -> Bool) {
        self.shouldRunNextStepHandler = shouldRunNextStep
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public var shouldRunNextStep: Bool {
        // The caller's predicate is arbitrary code, so it runs outside the lock.
        !isCancelled && shouldRunNextStepHandler()
    }

    /// Returns `true` only for the first caller, so cancellation teardown runs exactly once.
    public func markCancelled() -> Bool {
        lock.withLock {
            guard !cancelled else { return false }

            cancelled = true
            return true
        }
    }
}
