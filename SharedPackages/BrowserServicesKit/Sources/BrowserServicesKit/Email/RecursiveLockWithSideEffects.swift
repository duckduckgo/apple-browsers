//
//  RecursiveLockWithSideEffects.swift
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

/// A recursive lock that allows registering side effects to be executed when the lock is released.
/// 
/// This type provides synchronization with the ability to register side effects that will be executed
/// when the lock scope ends. Side effects are useful for deferring notifications or cleanup work
/// until after critical sections complete to avoid deadlocks.
///
/// Example usage:
/// ```
/// let lock = RecursiveLockWithSideEffects()
/// 
/// try lock.withLock { 
///     // Perform synchronized work
///     
///     lock.dispatchSideEffect {
///         // This will execute when the lock is released
///         notifyObservers()
///     }
/// }
/// ```
struct RecursiveLockWithSideEffects {
    private let lock = NSRecursiveLock()

    private class SideEffects {
        private var sideEffects: [() -> Void] = []

        func append(_ sideEffect: @escaping () -> Void) {
            sideEffects.append(sideEffect)
        }

        deinit {
            for sideEffect in sideEffects {
                sideEffect()
            }
        }
    }

    @TaskLocal
    private static var sideEffects: SideEffects?

    var isLocked: Bool {
        return Self.sideEffects != nil
    }

    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        return try Self.$sideEffects.withValue(Self.sideEffects ?? SideEffects()) {
            return try lock.withLock {
                return try block()
            }
        }
    }

    func dispatchSideEffect(_ sideEffect: @escaping () -> Void) {
        assert(Self.sideEffects != nil, "Running outside of a locked context")
        Self.sideEffects?.append(sideEffect)
    }

}
