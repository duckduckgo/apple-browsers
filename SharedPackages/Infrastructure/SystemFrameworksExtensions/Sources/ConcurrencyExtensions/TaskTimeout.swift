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

/// Wraps an async operation in a timeout.
/// If the operation takes longer than the timeout, an error is thrown.
/// If the operation is cancelled, the error is propagated.
/// - Parameters:
///   - timeout: The timeout duration.
///   - error: The error to throw if the operation takes longer than the timeout.
///   - operation: The async operation to wrap.
/// - Returns: The result of the operation.
/// ❗ Note: If used to wait for a task's value, it WILL NOT cancel the task!
/// ❗ Use `task.value(cancellingTaskOnTimeout:)` to await the task's value with a timeout and automatic cancellation, or use `withTaskCancellationHandler` to cancel the task manually.
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

/// Wraps an async operation in a timeout.
/// If the operation takes longer than the timeout, an error is thrown.
/// If the operation is cancelled, the error is propagated.
/// - Parameters:
///   - timeout: The timeout duration.
///   - file: The file name.
///   - line: The line number.
///   - operation: The async operation to wrap.
/// - Returns: The result of the operation.
/// ❗ Note: If used to wait for a task's value, it WILL NOT cancel the task!
/// ❗ Use `task.value(cancellingTaskOnTimeout:)` to await the task's value with a timeout and automatic cancellation, or use `withTaskCancellationHandler` to cancel the task manually.
public func withTimeout<T>(_ timeout: TimeInterval,
                           file: StaticString = #file,
                           line: UInt = #line,
                           do operation: @escaping () async throws -> T) async throws -> T {
    try await withTimeout(timeout, throwing: TimeoutError(interval: timeout, file: file, line: line), do: operation)
}

extension Task {
    /// Awaits the task's value with a timeout, cancelling the task if the timeout is exceeded.
    /// If the task takes longer than the timeout, an error is thrown and the task is cancelled.
    /// If the task is cancelled, the error is propagated.
    /// - Parameters:
    ///   - timeout: The timeout duration after which the task will be cancelled.
    ///   - file: The file name.
    ///   - line: The line number.
    /// - Returns: The result of the task.
    public func value(cancellingTaskOnTimeout timeout: TimeInterval, file: StaticString = #file, line: UInt = #line) async throws -> Success {
        try await withTimeout(timeout, throwing: TimeoutError(interval: timeout, file: file, line: line), do: {
            try await withTaskCancellationHandler {
                try await self.value
            } onCancel: {
                self.cancel()
            }
        })
    }
}
extension Task where Failure == Never {
    /// Awaits the task's value with a timeout, cancelling the task if the timeout is exceeded.
    /// If the task takes longer than the timeout, an error is thrown and the task is cancelled.
    /// If the task is cancelled, the error is propagated.
    /// - Parameters:
    ///   - timeout: The timeout duration after which the task will be cancelled.
    ///   - file: The file name.
    ///   - line: The line number.
    /// - Returns: The result of the task.
    public func value(cancellingTaskOnTimeout timeout: TimeInterval, file: StaticString = #file, line: UInt = #line) async throws -> Success {
        try await withTimeout(timeout, throwing: TimeoutError(interval: timeout, file: file, line: line), do: {
            await withTaskCancellationHandler {
                await self.value
            } onCancel: {
                self.cancel()
            }
        })
    }
}
