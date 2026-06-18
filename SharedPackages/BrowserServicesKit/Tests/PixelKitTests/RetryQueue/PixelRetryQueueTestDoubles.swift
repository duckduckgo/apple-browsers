//
//  PixelRetryQueueTestDoubles.swift
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
@testable import PixelKit

/// In-memory `PixelRetryQueueStoring` for tests, with optional injected errors.
final class MockPixelRetryQueueStore: PixelRetryQueueStoring {

    private let lock = NSLock()
    private var _items: [PixelRetryQueueItem] = []

    var appendError: Error?
    var removeError: Error?
    var storedItemsError: Error?

    var items: [PixelRetryQueueItem] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    init(initialItems: [PixelRetryQueueItem] = []) {
        _items = initialItems
    }

    func append(_ newItems: [PixelRetryQueueItem]) throws {
        if let appendError { throw appendError }
        lock.lock(); defer { lock.unlock() }
        _items.append(contentsOf: newItems)
    }

    func remove(itemsWithIDs ids: Set<UUID>) throws {
        if let removeError { throw removeError }
        lock.lock(); defer { lock.unlock() }
        _items.removeAll { ids.contains($0.id) }
    }

    func storedItems() throws -> [PixelRetryQueueItem] {
        if let storedItemsError { throw storedItemsError }
        lock.lock(); defer { lock.unlock() }
        return _items
    }
}

/// Controllable `PixelKit.FireRequest`. Distinguishes organic fires from retries by the `retriedPixel`
/// parameter that `PixelRetryQueue` adds on replay. Retries can be held (deferred) to drive concurrency
/// tests, mirroring iOS `DelayedPixelFiringMock`.
final class FireRequestMock {

    struct Call {
        let pixelName: String
        let headers: [String: String]
        let parameters: [String: String]
        let allowedQueryReservedCharacters: CharacterSet?
        let isRetry: Bool
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var pendingRetryCompletions: [PixelKit.CompletionBlock] = []

    /// Result returned for organic (non-retry) fires.
    var organicResult: (success: Bool, error: Error?) = (true, nil)
    /// Result returned for retry fires when `deferRetries` is false.
    var retryResult: (success: Bool, error: Error?) = (true, nil)
    /// When true, retry fires' completions are held until `completePendingRetries` is called.
    var deferRetries = false

    /// Invoked (synchronously, on the firing thread) after each call is recorded.
    var onFireReceived: ((Call) -> Void)?

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    var pendingRetryCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pendingRetryCompletions.count
    }

    var fireRequest: PixelKit.FireRequest {
        { [self] pixelName, headers, parameters, allowedChars, _, onComplete in
            let isRetry = parameters["retriedPixel"] == "1"
            let call = Call(pixelName: pixelName,
                            headers: headers,
                            parameters: parameters,
                            allowedQueryReservedCharacters: allowedChars,
                            isRetry: isRetry)
            lock.lock()
            _calls.append(call)
            let shouldDefer = isRetry && deferRetries
            if shouldDefer { pendingRetryCompletions.append(onComplete) }
            let organic = organicResult
            let retry = retryResult
            lock.unlock()

            onFireReceived?(call)

            if shouldDefer { return }
            if isRetry {
                onComplete(retry.success, retry.error)
            } else {
                onComplete(organic.success, organic.error)
            }
        }
    }

    func completePendingRetries(success: Bool, error: Error? = nil) {
        lock.lock()
        let completions = pendingRetryCompletions
        pendingRetryCompletions.removeAll()
        lock.unlock()
        completions.forEach { $0(success, error) }
    }
}
