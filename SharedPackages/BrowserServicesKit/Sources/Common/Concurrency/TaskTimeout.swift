//
//  TaskTimeout.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public func withTimeout<T>(_ timeout: TimeInterval,
                           throwing error: @autoclosure @escaping () -> Error,
                           do operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group -> T in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(interval: timeout)
            throw error()
        }

        // If the timeout finishes first, it will throw and cancel the long running task.
        for try await result in group {
            group.cancelAll()
            return result
        }

        fatalError("unexpected flow")
    }
}

public func withTimeout<T>(_ timeout: TimeInterval,
                           file: StaticString = #file,
                           line: UInt = #line,
                           do operation: @escaping () async throws -> T) async throws -> T {
    try await withTimeout(timeout, throwing: TimeoutError(interval: timeout, file: file, line: line), do: operation)
}
