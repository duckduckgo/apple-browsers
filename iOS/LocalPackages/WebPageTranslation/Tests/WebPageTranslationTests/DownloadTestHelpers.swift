//
//  DownloadTestHelpers.swift
//  DuckDuckGo
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
@testable import WebPageTranslation

/// Each install is a stream the test drives: `send`, `finish` or `fail` the latest one.
final class StubInstalls: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<Double, Error>.Continuation] = []
    private(set) var wasCancelled = false

    var count: Int { lock.withLock { continuations.count } }

    func start() -> AsyncThrowingStream<Double, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination { self?.lock.withLock { self?.wasCancelled = true } }
            }
            lock.withLock { continuations.append(continuation) }
        }
    }

    func send(_ fraction: Double) { lock.withLock { continuations.last }?.yield(fraction) }
    func finish() { lock.withLock { continuations.last }?.finish() }
    func fail() { lock.withLock { continuations.last }?.finish(throwing: PageTranslatorError.countMismatch) }
}

/// The fractions a progress stream gave so far, and how it ended.
final class ProgressListener: @unchecked Sendable {
    private let lock = NSLock()
    private var _fractions: [Double] = []
    private var _ended: Result<Void, Error>?
    var fractions: [Double] { lock.withLock { _fractions } }
    var ended: Result<Void, Error>? { lock.withLock { _ended } }

    @discardableResult
    func listen(to stream: AsyncThrowingStream<Double, Error>) -> Task<Void, Never> {
        Task {
            do {
                for try await fraction in stream { lock.withLock { _fractions.append(fraction) } }
                lock.withLock { _ended = .success(()) }
            } catch {
                lock.withLock { _ended = .failure(error) }
            }
        }
    }
}

func waitUntil(_ condition: () -> Bool) async {
    while !condition() { await Task.yield() }
}
