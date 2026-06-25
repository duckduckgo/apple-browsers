//
//  Error+Cancellation.swift
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

public extension Error {

    /// Whether this error is a Swift `CancellationError`, directly or wrapped via `NSUnderlyingErrorKey`.
    ///
    /// A cancelled VPN start surfaces as a `CancellationError` (e.g. from the tunnel startup monitor's
    /// task cancellation), but it can be wrapped inside another error — for example
    /// `StartError.startTunnelFailure(CancellationError())` — which otherwise gets reported as a genuine
    /// start failure. This walks the underlying-error chain so a wrapped cancellation is still recognised.
    ///
    /// Once wrapped, a `CancellationError` is bridged to an `NSError` when read back from `userInfo`, so
    /// its Swift type is lost; the domain comparison recovers that case (it is the
    /// `"Swift.CancellationError"` value seen in the underlying-error pixel parameter).
    var isCancellation: Bool {
        var error: Error? = self
        // Bounded walk to guard against pathological cycles in the underlying-error chain.
        for _ in 0..<10 {
            guard let current = error else { break }

            if current is CancellationError {
                return true
            }

            let nsError = current as NSError
            if nsError.domain == "Swift.CancellationError" {
                return true
            }

            error = nsError.userInfo[NSUnderlyingErrorKey] as? Error
        }

        return false
    }
}
