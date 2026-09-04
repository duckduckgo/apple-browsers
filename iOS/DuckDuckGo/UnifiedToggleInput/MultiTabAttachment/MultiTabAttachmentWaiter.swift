//
//  MultiTabAttachmentWaiter.swift
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

import Combine
import Foundation

/// Mirrors macOS's bounded publisher waits, subscribing before the operation starts.
enum MultiTabAttachmentWaiter {
    @MainActor
    static func firstValue<Value>(from publisher: AnyPublisher<Value, Never>,
                                  timeout: TimeInterval,
                                  start: () -> Void = {}) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let stream = AsyncStream<Value> { continuation in
            let cancellable = publisher.prefix(1).sink { value in
                continuation.yield(value)
                continuation.finish()
            }
            continuation.onTermination = { _ in cancellable.cancel() }
            start()
        }
        return await withTaskGroup(of: Value?.self) { group in
            group.addTask {
                for await value in stream { return value }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                return nil
            }
            let value = await group.next() ?? nil
            group.cancelAll()
            return Task.isCancelled ? nil : value
        }
    }
}
