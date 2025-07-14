//
//  LaunchTask.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// A unit of work scheduled by `LaunchTaskManager`.
///
/// You are responsible for calling `context.finish()` exactly once when your task completes.
/// Failing to do so will prevent the underlying operation from finishing,
/// potentially blocking the entire operation queue.
protocol LaunchTask {

    
    var name: String { get }

    /// Performs the task. Can be implemented using async/await, GCD, or synchronous code.
    /// - Parameter context: Provides control methods for cancellation checks and completion signaling.
    func run(context: LaunchTaskContext)

}

/// Context provided to a `LaunchTask` at runtime.
///
/// Use `isCancelled()` to check for cancellation and `finish()` to signal that your task has completed.
/// `finish()` must be called exactly once to avoid stalling the operation queue.
struct LaunchTaskContext {

    let isCancelled: () -> Bool
    let finish: () -> Void

}
