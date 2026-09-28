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

/// Shares cancellation with WebView action handling, CAPTCHA polling, and email-confirmation polling.
/// Access is locked because those paths may check cancellation concurrently with the runner cancelling.
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
        !isCancelled && shouldRunNextStepHandler()
    }

    /// Returns `true` only for the first cancellation request.
    public func markCancelled() -> Bool {
        lock.withLock {
            guard !cancelled else { return false }

            cancelled = true
            return true
        }
    }
}
