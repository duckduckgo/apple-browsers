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

/// Controllable `PixelKit.FireRequest`, modelling the network sender that `PixelRetryQueue` decorates.
/// Like the real sender it is retry-agnostic: it records every fire and returns `defaultResult`, with no
/// notion of organic-vs-replay. Tests drive scenarios through the pixel identities they control — naming
/// the pixels they enqueue and asserting on calls by name. Named fires can be held (deferred) via
/// `deferredPixelNames` to drive concurrency tests, mirroring iOS `DelayedPixelFiringMock`.
final class FireRequestMock {

    struct Call {
        let pixelName: String
        let headers: [String: String]
        let parameters: [String: String]
        let allowedQueryReservedCharacters: CharacterSet?
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var pendingCompletions: [PixelKit.CompletionBlock] = []

    /// Result returned for every fire that isn't held by `deferredPixelNames`.
    var defaultResult: (success: Bool, error: Error?) = (true, nil)
    /// Fires for these pixel names have their completions held until `completePendingFires` is called.
    var deferredPixelNames: Set<String> = []

    /// Invoked (synchronously, on the firing thread) after each call is recorded.
    var onFireReceived: ((Call) -> Void)?

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    var fireRequest: PixelKit.FireRequest {
        { [self] pixelName, headers, parameters, allowedChars, _, onComplete in
            let call = Call(pixelName: pixelName,
                            headers: headers,
                            parameters: parameters,
                            allowedQueryReservedCharacters: allowedChars)
            lock.lock()
            _calls.append(call)
            let shouldDefer = deferredPixelNames.contains(pixelName)
            if shouldDefer { pendingCompletions.append(onComplete) }
            let result = defaultResult
            lock.unlock()

            onFireReceived?(call)

            if shouldDefer { return }
            onComplete(result.success, result.error)
        }
    }

    func completePendingFires(success: Bool, error: Error? = nil) {
        lock.lock()
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        lock.unlock()
        completions.forEach { $0(success, error) }
    }
}
