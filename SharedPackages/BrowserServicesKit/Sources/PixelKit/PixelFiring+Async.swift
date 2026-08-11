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

    /// Async/await variant of PixelKit `fire`
    ///
    /// - Returns: `true` if a request was fired, `false` if it was suppressed by frequency rules.
    /// - Throws: the underlying error if firing the request failed.
    @discardableResult
    public func fireAsync(_ event: PixelKitEvent,
                          frequency: PixelKit.Frequency = .standard,
                          includeAppVersionParameter: Bool = true,
                          withAdditionalParameters parameters: [String: String]? = nil,
                          withNamePrefix namePrefix: String? = nil,
                          doNotEnforcePrefix: Bool = false) async throws -> Bool {
        let firstCompletion = OneTimeFlag()
        return try await withCheckedThrowingContinuation { continuation in
            fire(event,
                 frequency: frequency,
                 includeAppVersionParameter: includeAppVersionParameter,
                 withAdditionalParameters: parameters,
                 withNamePrefix: namePrefix,
                 doNotEnforcePrefix: doNotEnforcePrefix) { fired, error in
                guard firstCompletion.trySet() else { return }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: fired)
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
