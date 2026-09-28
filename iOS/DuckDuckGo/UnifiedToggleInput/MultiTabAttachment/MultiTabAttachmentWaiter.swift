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

enum MultiTabAttachmentWaiter {
    enum Result<Value> {
        case value(Value)
        case timedOut
        case cancelled
        case finished
    }

    /// Subscribe before starting, and release the subscription on every exit, including cancellation.
    @MainActor
    static func firstValue<Value>(from publisher: AnyPublisher<Value, Never>,
                                  timeout: TimeInterval,
                                  afterSubscription: () -> Void = {}) async -> Result<Value> {
        guard !Task.isCancelled else { return .cancelled }
        let stream = AsyncStream<Result<Value>> { continuation in
            let subscription = publisher.first().sink(receiveCompletion: { _ in
                continuation.yield(.finished)
                continuation.finish()
            }, receiveValue: { value in
                continuation.yield(.value(value))
                continuation.finish()
            })
            continuation.onTermination = { _ in subscription.cancel() }
            afterSubscription()
        }

        return await withTaskGroup(of: Result<Value>.self) { group in
            group.addTask {
                for await result in stream {
                    return result
                }
                return .cancelled
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }
            let result = await group.next() ?? .cancelled
            group.cancelAll()
            return Task.isCancelled ? .cancelled : result
        }
    }
}
