//
//  ActionResult.swift
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
import PixelKit

/// Result structure containing both the operation result and pre-measured duration.
///
/// Used for actions that measure their own duration internally (e.g., parallel async operations)
/// and return the completed measurement along with success/failure status.
///
/// This pattern is particularly useful when:
/// - Multiple operations run in parallel using `async let`
/// - You need individual task durations, not wall-clock time
/// - The operation itself is responsible for timing measurement
///
/// Example usage:
/// ```swift
/// func performWork() async -> ActionResult {
///     var interval = WideEvent.MeasuredInterval.startingNow()
///     do {
///         try await doWork()
///         interval.complete()
///         return ActionResult(result: .success(()), measuredInterval: interval)
///     } catch {
///         interval.complete()
///         return ActionResult(result: .failure(error), measuredInterval: interval)
///     }
/// }
/// ```
public struct ActionResult {
    public let result: Result<Void, Error>
    public let measuredInterval: WideEvent.MeasuredInterval

    public init(result: Result<Void, Error>, measuredInterval: WideEvent.MeasuredInterval) {
        self.result = result
        self.measuredInterval = measuredInterval
    }
}
